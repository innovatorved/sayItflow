package com.sayitflow.android.ml

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.os.Process
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * 100% On-Device `desert-ant-labs/voz` Speech-to-Text Engine for Android (Google Pixel Tensor).
 *
 * Ports `Desert-Ant-Labs/desert-ant-core/Sources/Voz/Pipeline.swift` directly to Kotlin + ONNX Runtime:
 * - Uses `web/encoder.onnx` + `web/encoder.onnx.data` (FP16 weights, fused mel frontend)
 * - Uses `web/decoder.onnx` (`reducesInGraph = true`, outputs `tok`, `dur`, `h_out`, `c_out`)
 * - Uses `web/embedding.f16` (`[8193, 640]` widened once to float32 on load)
 * - Uses zero-copy Direct `FloatBuffer`s, `NO_OPT` (avoiding slow naive `Gemm`), 4 big-core threads,
 *   and `THREAD_PRIORITY_URGENT_DISPLAY` scheduling for maximum speed on Pixel Tensor G2.
 */
class VozEngine(private val context: Context) {

    companion object {
        private const val TAG = "VozEngine"
        const val IDLE_UNLOAD_DELAY_MS = 1_800_000L // Keep warm in RAM for 30 minutes of inactivity
        const val KEY_BIAS_MASK = -40000.0f // Float16-representable -infinity

        private fun allocateDirectFloatBuffer(floatCount: Int): FloatBuffer {
            return ByteBuffer.allocateDirect(floatCount * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
        }

        /**
         * Mel frames that hold audio. NeMo's centered STFT gives `samples / hop + 1`.
         */
        fun validMelFrames(sampleCount: Int, c: VozConfiguration): Int {
            return max(1, min(c.validFrames, sampleCount / c.hopLength + 1))
        }

        /**
         * Encoder frames that hold audio. Subsampling rounds up `(melValid + 7) / 8`.
         */
        fun validEncoderFrames(sampleCount: Int, c: VozConfiguration): Int {
            val melValid = validMelFrames(sampleCount, c)
            return min(c.encFrames, (melValid + 7) / 8)
        }

        /**
         * Encoder frames the window attends to (`(sampleCount + 1279) / 1280`).
         */
        fun attendedEncoderFrames(sampleCount: Int, c: VozConfiguration): Int {
            val samplesPerFrame = c.hopLength * 8
            return max(1, min(c.encFrames, (sampleCount + samplesPerFrame - 1) / samplesPerFrame))
        }

        /**
         * Lays out a 15.0s PCM window into `audio_rows` `[160, 1503]`, `mel_mask` `[1500]`,
         * and `key_bias` `[188]`, matching `Pipeline.swift:stage(window:lane:into:)`.
         */
        fun stageWindow(window: FloatArray, c: VozConfiguration): StagedFrontend {
            val stride = c.hopLength * c.nRows
            val audioRows = FloatArray(stride)
            val hop = c.hopLength
            val pad = c.nFFT / 2
            val total = min(c.nPaddedSamples, c.nRows * hop)
            val n = c.nSamples
            val last: Float = if (window.size == n && window.isNotEmpty()) window[window.size - 1] else 0f

            for (i in pad until total) {
                val k = i - pad
                val value: Float = if (k < n) {
                    if (k < window.size) window[k] else 0f
                } else {
                    if (last == 0f) 0f else c.preemph.pow((k - n + 1).toFloat()) * last
                }
                if (value != 0f) {
                    audioRows[(i % hop) * c.nRows + (i / hop)] = value
                }
            }

            val melValid = validMelFrames(window.size, c)
            val melMask = FloatArray(c.validFrames) { idx ->
                if (idx < melValid) 1.0f else 0.0f
            }

            val attended = attendedEncoderFrames(window.size, c)
            val keyBias = FloatArray(c.encFrames) { idx ->
                if (idx < attended) 0.0f else KEY_BIAS_MASK
            }

            return StagedFrontend(
                audioRows = audioRows,
                melMask = melMask,
                keyBias = keyBias
            )
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val engineMutex = Mutex()
    private var idleUnloadJob: Job? = null

    private var ortEnv: OrtEnvironment? = null
    private var encoderSession: OrtSession? = null
    private var decoderSession: OrtSession? = null
    private var configuration: VozConfiguration = VozConfiguration()
    private var vocabulary: List<String> = emptyList()
    private var embeddingTable: FloatArray = FloatArray(0)

    // Pre-allocated zero-copy Direct FloatBuffers & scratch arrays (initialized on load)
    private var directAudioRows: FloatBuffer? = null
    private var directMelMask: FloatBuffer? = null
    private var directKeyBias: FloatBuffer? = null
    private var reusableEncProj: FloatArray = FloatArray(0)

    private val _isLoaded = MutableStateFlow(false)
    val isLoaded: StateFlow<Boolean> = _isLoaded.asStateFlow()

    private val _isWarmingUp = MutableStateFlow(false)
    val isWarmingUp: StateFlow<Boolean> = _isWarmingUp.asStateFlow()

    private val _lastLoadMs = MutableStateFlow(0L)
    val lastLoadMs: StateFlow<Long> = _lastLoadMs.asStateFlow()

    val modelDirectory: File
        get() = File(context.filesDir, "models/desert-ant-voz")

    fun areModelFilesInstalled(): Boolean {
        val dir = modelDirectory
        return File(dir, "encoder.onnx").exists() &&
            File(dir, "encoder.onnx.data").exists() &&
            File(dir, "decoder.onnx").exists() &&
            File(dir, "embedding.f16").exists() &&
            File(dir, "meta.json").exists() &&
            File(dir, "vocab.json").exists()
    }

    /**
     * Pre-warms `desert-ant-labs/voz` in the background so dictation starts with 0ms model-load latency.
     */
    fun warmUpAsync() {
        scope.launch {
            try {
                ensureLoaded()
            } catch (e: Exception) {
                Log.w(TAG, "Background warm-up skipped: ${e.message}")
            }
        }
    }

    suspend fun ensureLoaded() = engineMutex.withLock {
        resetIdleUnloadTimerLocked()
        if (_isLoaded.value && encoderSession != null && decoderSession != null) {
            return@withLock
        }
        _isWarmingUp.value = true
        try {
            withContext(Dispatchers.IO) {
                val dir = modelDirectory
                require(areModelFilesInstalled()) {
                    "Desert Ant Voz model files are not yet downloaded in ${dir.absolutePath}"
                }

                val t0 = System.currentTimeMillis()
                val metaJson = File(dir, "meta.json").readText()
                val config = VozConfiguration.fromJson(metaJson)
                val vocabJson = File(dir, "vocab.json").readText()
                val vocab = VozWords.parseVocabulary(vocabJson)
                require(vocab.size >= config.vocabSize) {
                    "Vocabulary size ${vocab.size} < ${config.vocabSize}"
                }

                val embBytes = File(dir, "embedding.f16").readBytes()
                val expectedElements = (config.vocabSize + 1) * config.predHidden
                val embTable = VozWords.decodeFloat16Embedding(embBytes, expectedElements)

                val env = OrtEnvironment.getEnvironment()
                val sessionOptions = OrtSession.SessionOptions().apply {
                    // Desert Ant Labs (`voz.js`): graphOptimizationLevel: "disabled" (NO_OPT) is deliberate
                    // because ONNX Runtime's MatMul+Add->Gemm fusion emits a naive kernel on this encoder.
                    setOptimizationLevel(OrtSession.SessionOptions.OptLevel.NO_OPT)
                    // Pixel 7a (Tensor G2) has 4 performance cores (2x Cortex-X1 + 2x Cortex-A78).
                    // Using 4 intra-op threads keeps execution off the 4 slow in-order Cortex-A55 cores.
                    setIntraOpNumThreads(4)
                    setInterOpNumThreads(1)
                    // Avoid 350 MB duplicate CPU arena allocation so Android does not swap process to ZRAM.
                    setCPUArenaAllocator(false)
                    setMemoryPatternOptimization(false)
                    runCatching {
                        addConfigEntry("session.intra_op.allow_spinning", "1")
                    }
                }

                val encSession = env.createSession(File(dir, "encoder.onnx").absolutePath, sessionOptions)
                val decSession = env.createSession(File(dir, "decoder.onnx").absolutePath, sessionOptions)

                directAudioRows = allocateDirectFloatBuffer(config.hopLength * config.nRows)
                directMelMask = allocateDirectFloatBuffer(config.validFrames)
                directKeyBias = allocateDirectFloatBuffer(config.encFrames)
                reusableEncProj = FloatArray(config.jointHidden * config.encFrames)

                ortEnv = env
                encoderSession = encSession
                decoderSession = decSession
                configuration = config
                vocabulary = vocab
                embeddingTable = embTable

                // Warm up decoder threadpool & JNI buffers with a 1-frame pass
                runCatching {
                    runDecoderWindow(env, decSession, reusableEncProj, 1, config)
                }

                val elapsed = System.currentTimeMillis() - t0
                _lastLoadMs.value = elapsed
                _isLoaded.value = true

                Log.i(TAG, "Loaded & warmed desert-ant-labs/voz in $elapsed ms")
            }
        } finally {
            _isWarmingUp.value = false
        }
    }

    /**
     * Unloads ONNX sessions and embedding buffers from RAM after 30 minutes of inactivity.
     */
    suspend fun unloadModels() = engineMutex.withLock {
        idleUnloadJob?.cancel()
        idleUnloadJob = null
        if (!_isLoaded.value) return@withLock
        try {
            encoderSession?.close()
            decoderSession?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing ONNX sessions: ${e.message}")
        }
        encoderSession = null
        decoderSession = null
        directAudioRows = null
        directMelMask = null
        directKeyBias = null
        reusableEncProj = FloatArray(0)
        vocabulary = emptyList()
        embeddingTable = FloatArray(0)
        _isLoaded.value = false
        System.gc()
        Log.i(TAG, "Auto-unloaded desert-ant-labs/voz after idle — 0 MB ML RAM used.")
    }

    private fun resetIdleUnloadTimerLocked() {
        idleUnloadJob?.cancel()
        idleUnloadJob = scope.launch {
            delay(IDLE_UNLOAD_DELAY_MS)
            unloadModels()
        }
    }

    /**
     * Transcribes 16 kHz mono float32 PCM samples using `desert-ant-labs/voz`.
     */
    suspend fun transcribe(samples: FloatArray): String {
        if (samples.isEmpty()) return ""
        ensureLoaded()

        return engineMutex.withLock {
            resetIdleUnloadTimerLocked()
            withContext(Dispatchers.Default) {
                val prevPriority = runCatching {
                    val tid = Process.myTid()
                    val old = Process.getThreadPriority(tid)
                    Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_DISPLAY)
                    old
                }.getOrDefault(Process.THREAD_PRIORITY_DEFAULT)
                try {
                    val c = configuration
                    val env = requireNotNull(ortEnv)
                    val enc = requireNotNull(encoderSession)
                    val dec = requireNotNull(decoderSession)

                // Add a small 160ms right-context silence pad if utterance is short (< 2.5s)
                // so FastConformer's 8x subsampling has clean trailing context frames.
                val preparedSamples = if (samples.size < (c.sampleRate * 5) / 2) {
                    val padSamples = (c.sampleRate * 0.16).toInt()
                    FloatArray(min(c.nSamples, samples.size + padSamples)).also { padded ->
                        System.arraycopy(samples, 0, padded, 0, min(samples.size, padded.size))
                    }
                } else {
                    samples
                }

                val secondsPerEncoderFrame = (c.hopLength * 8).toDouble() / c.sampleRate.toDouble()
                val windows = sliceWindows(preparedSamples, c)
                var mergedWords = emptyList<VozWords.TimedWord>()
                var prevWindowEndSec = 0.0

                for ((windowStartSample, windowSlice) in windows) {
                    val windowStartSec = windowStartSample.toDouble() / c.sampleRate.toDouble()
                    val windowEndSec = (windowStartSample + windowSlice.size).toDouble() / c.sampleRate.toDouble()

                    val tEnc0 = System.currentTimeMillis()
                    val decoded = transcribeSingleWindow(env, enc, dec, windowSlice, c)
                    val tEnc1 = System.currentTimeMillis()

                    val windowWords = VozWords.assembleWords(
                        tokens = decoded.tokens,
                        frames = decoded.frames,
                        ends = decoded.ends,
                        windowStartSeconds = windowStartSec,
                        secondsPerEncoderFrame = secondsPerEncoderFrame,
                        vocabulary = vocabulary
                    )

                    Log.i(
                        TAG,
                        "Window [${String.format("%.2f", windowStartSec)}s..${String.format("%.2f", windowEndSec)}s] " +
                            "transcribed in ${tEnc1 - tEnc0}ms -> ${decoded.tokens.size} tokens (${windowWords.size} words)"
                    )

                    mergedWords = if (mergedWords.isEmpty()) {
                        windowWords
                    } else if (windowStartSec < prevWindowEndSec) {
                        VozWords.spliceOverlap(
                            prefix = mergedWords,
                            suffix = windowWords,
                            overlapStart = windowStartSec,
                            overlapEnd = prevWindowEndSec
                        )
                    } else {
                        val (repairedP, repairedS) = VozWords.repairJoin(mergedWords, windowWords)
                        repairedP + repairedS
                    }
                    prevWindowEndSec = windowEndSec
                }

                    val finalTranscript = mergedWords.joinToString(" ") { it.text }.trim()
                    Log.i(TAG, "Final transcript: \"$finalTranscript\"")
                    finalTranscript
                } finally {
                    runCatching {
                        Process.setThreadPriority(prevPriority)
                    }
                }
            }
        }
    }

    private fun transcribeSingleWindow(
        env: OrtEnvironment,
        enc: OrtSession,
        dec: OrtSession,
        windowSlice: FloatArray,
        c: VozConfiguration
    ): DecodeWindowOutput {
        val t0 = System.currentTimeMillis()
        val encProj = runEncoderWindow(env, enc, windowSlice, c)
        val t1 = System.currentTimeMillis()
        val validEncFrames = validEncoderFrames(windowSlice.size, c)
        val out = runDecoderWindow(
            env = env,
            dec = dec,
            encProj = encProj,
            validFrames = validEncFrames,
            c = c
        )
        val t2 = System.currentTimeMillis()
        Log.i(TAG, "Voz timing: encoder=${t1 - t0}ms, decoder=${t2 - t1}ms (validFrames=$validEncFrames, tokens=${out.tokens.size})")
        return out
    }

    /**
     * Splits long recordings into 15.0s windows (`nSamples = 240,000`) with a 1.0s overlap
     * anchored at the quietest 20ms frame near the boundary.
     */
    internal fun sliceWindows(samples: FloatArray, c: VozConfiguration): List<Pair<Int, FloatArray>> {
        if (samples.size <= c.nSamples) {
            return listOf(0 to samples)
        }
        val windows = mutableListOf<Pair<Int, FloatArray>>()
        val step = c.nSamples - c.sampleRate // 14.0s nominal advance (1.0s overlap)
        var start = 0
        while (start < samples.size) {
            val end = min(samples.size, start + c.nSamples)
            windows.add(start to samples.copyOfRange(start, end))
            if (end >= samples.size) break
            val nominalNext = start + step
            start = quietestPoint(samples, nominalNext, start + c.sampleRate, samples.size, c.sampleRate)
        }
        return windows
    }

    private fun quietestPoint(
        samples: FloatArray,
        at: Int,
        lowest: Int,
        limit: Int,
        sampleRate: Int
    ): Int {
        val frame = max(1, (0.02 * sampleRate).toInt()) // 20 ms
        val first = max(lowest, at - sampleRate)
        val last = min(limit - frame, at + sampleRate / 2)
        if (last <= first) return max(lowest, min(at, limit - 1))

        var bestAt = at
        var bestEnergy = Float.MAX_VALUE
        var index = first
        while (index + frame <= last) {
            var sum = 0f
            for (i in index until (index + frame)) {
                val v = samples[i]
                sum += v * v
            }
            if (sum < bestEnergy) {
                bestEnergy = sum
                bestAt = index + frame / 2
            }
            index += frame / 2
        }
        return bestAt
    }

    private fun runEncoderWindow(
        env: OrtEnvironment,
        encSession: OrtSession,
        window: FloatArray,
        c: VozConfiguration
    ): FloatArray {
        val staged = stageWindow(window, c)
        val rowsShape = longArrayOf(1L, c.hopLength.toLong(), 1L, c.nRows.toLong())
        val melMaskShape = longArrayOf(1L, 1L, 1L, c.validFrames.toLong())
        val keyBiasShape = longArrayOf(1L, c.encFrames.toLong(), 1L, 1L)

        val rowsBuf = (directAudioRows ?: allocateDirectFloatBuffer(staged.audioRows.size)).apply {
            clear()
            put(staged.audioRows)
            rewind()
        }
        val maskBuf = (directMelMask ?: allocateDirectFloatBuffer(staged.melMask.size)).apply {
            clear()
            put(staged.melMask)
            rewind()
        }
        val biasBuf = (directKeyBias ?: allocateDirectFloatBuffer(staged.keyBias.size)).apply {
            clear()
            put(staged.keyBias)
            rewind()
        }

        OnnxTensor.createTensor(env, rowsBuf, rowsShape).use { rowsTensor ->
            OnnxTensor.createTensor(env, maskBuf, melMaskShape).use { maskTensor ->
                OnnxTensor.createTensor(env, biasBuf, keyBiasShape).use { biasTensor ->
                    val inputs = mapOf(
                        "audio_rows" to rowsTensor,
                        "mel_mask" to maskTensor,
                        "key_bias" to biasTensor
                    )
                    encSession.run(inputs).use { result ->
                        val outTensor = result[0] as OnnxTensor
                        val fb = outTensor.floatBuffer
                        val expectedSize = c.jointHidden * c.encFrames
                        val out = if (reusableEncProj.size == expectedSize) {
                            reusableEncProj
                        } else {
                            FloatArray(expectedSize).also { reusableEncProj = it }
                        }
                        fb.get(out)
                        return out
                    }
                }
            }
        }
    }

    private data class DecodeWindowOutput(
        val tokens: IntArray,
        val frames: IntArray,
        val ends: IntArray
    )

    private fun runDecoderWindow(
        env: OrtEnvironment,
        dec: OrtSession,
        encProj: FloatArray,
        validFrames: Int,
        c: VozConfiguration
    ): DecodeWindowOutput {
        val width = c.decodeWidth
        val joint = c.jointHidden
        val total = c.encFrames
        val hidden = c.predLayers * c.predHidden
        val blank = c.blankIdx
        val limit = max(1, min(total, validFrames))

        val declaredLanes = (dec.inputInfo["embed"]?.info as? ai.onnxruntime.TensorInfo)
            ?.shape?.firstOrNull()?.toInt() ?: c.decodeLanes
        val lanes = if (declaredLanes > 0) declaredLanes else max(1, c.decodeLanes)

        var position = 0
        var label = blank
        var emitted = 0

        val hIn = FloatArray(lanes * hidden)
        val cIn = FloatArray(lanes * hidden)
        val hOutBuf = FloatArray(hidden)
        val cOutBuf = FloatArray(hidden)
        val embed = FloatArray(lanes * c.predHidden)
        val encStep = FloatArray(lanes * joint * width)

        val embedDirect = allocateDirectFloatBuffer(embed.size)
        val hInDirect = allocateDirectFloatBuffer(hIn.size)
        val cInDirect = allocateDirectFloatBuffer(cIn.size)
        val encStepDirect = allocateDirectFloatBuffer(encStep.size)

        val tokens = ArrayList<Int>(64)
        val frames = ArrayList<Int>(64)
        val ends = ArrayList<Int>(64)

        val embedShape = longArrayOf(lanes.toLong(), c.predHidden.toLong(), 1L, 1L)
        val stateShape = longArrayOf(lanes.toLong(), hidden.toLong(), 1L, 1L)
        val stepShape = longArrayOf(lanes.toLong(), joint.toLong(), 1L, width.toLong())
        val maxDecodeSteps = limit + 48
        var decodeSteps = 0

        while (position < limit && decodeSteps < maxDecodeSteps) {
            decodeSteps++
            // 1. Copy embedding row for `label` into lane 0
            System.arraycopy(embeddingTable, label * c.predHidden, embed, 0, c.predHidden)

            // 2. Gather `span` encoder frames across all `joint` channels for lane 0
            val span = min(width, limit - position)
            for (channel in 0 until joint) {
                val dstBase = channel * width
                val srcBase = channel * total + position
                for (w in 0 until span) {
                    encStep[dstBase + w] = encProj[srcBase + w]
                }
                for (w in span until width) {
                    encStep[dstBase + w] = 0f
                }
            }

            // 3. Stage into zero-copy Direct FloatBuffers & run TDT decode step (`reducesInGraph = true`)
            embedDirect.clear(); embedDirect.put(embed); embedDirect.rewind()
            hInDirect.clear(); hInDirect.put(hIn); hInDirect.rewind()
            cInDirect.clear(); cInDirect.put(cIn); cInDirect.rewind()
            encStepDirect.clear(); encStepDirect.put(encStep); encStepDirect.rewind()

            var tok0 = blank
            var tok1 = blank
            var dur0 = 0
            var dur1 = 0

            OnnxTensor.createTensor(env, embedDirect, embedShape).use { embedTensor ->
                OnnxTensor.createTensor(env, hInDirect, stateShape).use { hInTensor ->
                    OnnxTensor.createTensor(env, cInDirect, stateShape).use { cInTensor ->
                        OnnxTensor.createTensor(env, encStepDirect, stepShape).use { stepTensor ->
                            val inputs = mapOf(
                                "embed" to embedTensor,
                                "h_in" to hInTensor,
                                "c_in" to cInTensor,
                                "enc_step" to stepTensor
                            )
                            dec.run(inputs).use { result ->
                                val tokTensor = result.get("tok").get() as OnnxTensor
                                val durTensor = result.get("dur").get() as OnnxTensor
                                val hOutTensor = result.get("h_out").get() as OnnxTensor
                                val cOutTensor = result.get("c_out").get() as OnnxTensor

                                val tokIb = tokTensor.intBuffer
                                val durIb = durTensor.intBuffer
                                tok0 = tokIb.get(0)
                                if (width > 1 && tokIb.remaining() > 1) tok1 = tokIb.get(1)
                                dur0 = durIb.get(0)
                                if (width > 1 && durIb.remaining() > 1) dur1 = durIb.get(1)

                                hOutTensor.floatBuffer.get(hOutBuf, 0, hidden)
                                cOutTensor.floatBuffer.get(cOutBuf, 0, hidden)
                            }
                        }
                    }
                }
            }

            // 4. Advance TDT state machine across `span` frames
            var offset = 0
            var didEmit = false
            while (offset < span) {
                val bestTok = if (offset == 0) tok0 else tok1
                val bestDurIdx = if (offset == 0) dur0 else dur1
                val duration = c.durations.getOrElse(bestDurIdx) { 1 }

                if (bestTok != blank) {
                    tokens.add(bestTok)
                    frames.add(position + offset)
                    ends.add(position + offset + duration)
                    System.arraycopy(hOutBuf, 0, hIn, 0, hidden)
                    System.arraycopy(cOutBuf, 0, cIn, 0, hidden)
                    label = bestTok
                    emitted += 1
                    var step = duration
                    // TDT may predict a zero duration; force progress after 3 emissions on one frame
                    if (step == 0 && emitted >= 3) {
                        step = 1
                        emitted = 0
                    }
                    position += offset + step
                    didEmit = true
                    break
                }
                emitted = 0
                offset += if (duration > 0) duration else 1
            }
            if (!didEmit) {
                position += max(offset, 1)
            }
        }

        return DecodeWindowOutput(
            tokens = tokens.toIntArray(),
            frames = frames.toIntArray(),
            ends = ends.toIntArray()
        )
    }

    data class StagedFrontend(
        val audioRows: FloatArray,
        val melMask: FloatArray,
        val keyBias: FloatArray
    )

    fun validMelFrames(sampleCount: Int, c: VozConfiguration): Int = Companion.validMelFrames(sampleCount, c)
}
