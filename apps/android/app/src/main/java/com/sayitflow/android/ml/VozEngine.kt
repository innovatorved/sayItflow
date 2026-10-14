package com.sayitflow.android.ml

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
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
import java.nio.FloatBuffer
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
 * - Automatically unloads ONNX sessions and embedding tables after 2 minutes of idle silence
 *   so background RAM & battery footprint drop to near zero.
 */
class VozEngine(private val context: Context) {

    companion object {
        private const val TAG = "VozEngine"
        const val IDLE_UNLOAD_DELAY_MS = 120_000L // 2 minutes auto-unload
        const val KEY_BIAS_MASK = -40000.0f // Float16-representable -infinity

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

    private val _isLoaded = MutableStateFlow(false)
    val isLoaded: StateFlow<Boolean> = _isLoaded.asStateFlow()

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
     * Pre-warms `desert-ant-labs/voz` in the background while the user is holding the hardware button.
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
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                // Use 4 performance cores on Google Pixel Tensor
                setIntraOpNumThreads(4)
            }

            // Passing the File path allows ONNX Runtime to resolve `encoder.onnx.data` in the same directory
            val encSession = env.createSession(File(dir, "encoder.onnx").absolutePath, sessionOptions)
            val decSession = env.createSession(File(dir, "decoder.onnx").absolutePath, sessionOptions)

            ortEnv = env
            encoderSession = encSession
            decoderSession = decSession
            configuration = config
            vocabulary = vocab
            embeddingTable = embTable
            _isLoaded.value = true

            Log.i(TAG, "Loaded desert-ant-labs/voz in ${System.currentTimeMillis() - t0} ms")
        }
    }

    /**
     * Unloads ONNX sessions and embedding buffers from RAM after 2 minutes of inactivity.
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
        vocabulary = emptyList()
        embeddingTable = FloatArray(0)
        _isLoaded.value = false
        System.gc()
        Log.i(TAG, "Auto-unloaded desert-ant-labs/voz after 2 minutes idle — 0 MB ML RAM used.")
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
                val c = configuration
                val env = requireNotNull(ortEnv)
                val enc = requireNotNull(encoderSession)
                val dec = requireNotNull(decoderSession)

                val secondsPerEncoderFrame = (c.hopLength * 8).toDouble() / c.sampleRate.toDouble()
                val windows = sliceWindows(samples, c)
                var mergedWords = emptyList<VozWords.TimedWord>()
                var prevWindowEndSec = 0.0

                for ((windowStartSample, windowSlice) in windows) {
                    val windowStartSec = windowStartSample.toDouble() / c.sampleRate.toDouble()
                    val windowEndSec = (windowStartSample + windowSlice.size).toDouble() / c.sampleRate.toDouble()

                    val encProj = runEncoderWindow(env, enc, windowSlice, c)
                    val validEncFrames = validEncoderFrames(windowSlice.size, c)
                    val (tokens, frames, ends) = runDecoderWindow(
                        env = env,
                        dec = dec,
                        encProj = encProj,
                        validFrames = validEncFrames,
                        c = c
                    )

                    val windowWords = VozWords.assembleWords(
                        tokens = tokens,
                        frames = frames,
                        ends = ends,
                        windowStartSeconds = windowStartSec,
                        secondsPerEncoderFrame = secondsPerEncoderFrame,
                        vocabulary = vocabulary
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

                mergedWords.joinToString(" ") { it.text }.trim()
            }
        }
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

        OnnxTensor.createTensor(env, FloatBuffer.wrap(staged.audioRows), rowsShape).use { rowsTensor ->
            OnnxTensor.createTensor(env, FloatBuffer.wrap(staged.melMask), melMaskShape).use { maskTensor ->
                OnnxTensor.createTensor(env, FloatBuffer.wrap(staged.keyBias), keyBiasShape).use { biasTensor ->
                    val inputs = mapOf(
                        "audio_rows" to rowsTensor,
                        "mel_mask" to maskTensor,
                        "key_bias" to biasTensor
                    )
                    encSession.run(inputs).use { result ->
                        val outTensor = result[0] as OnnxTensor
                        val fb = outTensor.floatBuffer
                        val out = FloatArray(c.jointHidden * c.encFrames)
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

        var position = 0
        var label = blank
        var emitted = 0

        val hIn = FloatArray(hidden)
        val cIn = FloatArray(hidden)
        val embed = FloatArray(c.predHidden)
        val encStep = FloatArray(joint * width)

        val tokens = ArrayList<Int>(64)
        val frames = ArrayList<Int>(64)
        val ends = ArrayList<Int>(64)

        val embedShape = longArrayOf(1L, c.predHidden.toLong(), 1L, 1L)
        val stateShape = longArrayOf(1L, hidden.toLong(), 1L, 1L)
        val stepShape = longArrayOf(1L, joint.toLong(), 1L, width.toLong())

        while (position < limit) {
            // 1. Copy embedding row for `label`
            System.arraycopy(embeddingTable, label * c.predHidden, embed, 0, c.predHidden)

            // 2. Gather `span` encoder frames across all `joint` channels
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

            // 3. Run single-lane TDT decode step (`reducesInGraph = true`)
            var tok0 = blank
            var tok1 = blank
            var dur0 = 0
            var dur1 = 0
            val hOutBuf = FloatArray(hidden)
            val cOutBuf = FloatArray(hidden)

            OnnxTensor.createTensor(env, FloatBuffer.wrap(embed), embedShape).use { embedTensor ->
                OnnxTensor.createTensor(env, FloatBuffer.wrap(hIn), stateShape).use { hInTensor ->
                    OnnxTensor.createTensor(env, FloatBuffer.wrap(cIn), stateShape).use { cInTensor ->
                        OnnxTensor.createTensor(env, FloatBuffer.wrap(encStep), stepShape).use { stepTensor ->
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

                                hOutTensor.floatBuffer.get(hOutBuf)
                                cOutTensor.floatBuffer.get(cOutBuf)
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
                    // TDT may predict a zero duration; force progress after 10 emissions on one frame
                    if (step == 0 && emitted >= 10) {
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

    // =========================================================================
    // Exact Frontend Framing & Masking from `Desert-Ant-Labs/desert-ant-core`
    // =========================================================================

    data class StagedFrontend(
        val audioRows: FloatArray,
        val melMask: FloatArray,
        val keyBias: FloatArray
    )

    /**
     * Mel frames that hold audio. NeMo's centered STFT gives `samples / hop + 1`.
     */
    fun validMelFrames(sampleCount: Int, c: VozConfiguration): Int = Companion.validMelFrames(sampleCount, c)
}

