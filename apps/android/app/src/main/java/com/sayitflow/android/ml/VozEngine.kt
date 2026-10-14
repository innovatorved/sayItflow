package com.sayitflow.android.ml

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.os.Process
import android.util.Log
import com.sayitflow.android.audio.AudioCaptureManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
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
 * 100% On-Device `desert-ant-labs/voz` Speech-to-Text Engine for Android ("Voz-0.6B Live Turbo").
 *
 * Ports both `Pipeline.swift` and `Live.swift` from `Desert-Ant-Labs/desert-ant-core` to Kotlin + ONNX Runtime:
 * - Uses `web/encoder.onnx` + `web/encoder.onnx.data` (FP16 weights, fused mel frontend)
 * - Uses `web/decoder.onnx` (`reducesInGraph = true`, outputs `tok`, `dur`, `h_out`, `c_out`)
 * - Uses `web/embedding.f16` (`[8193, 640]` widened once to float32 on load)
 * - Separate `encoderOptions` (`NO_OPT`, 4 big-core threads, CPU arena + memory pattern enabled) and
 *   `decoderOptions` (`ALL_OPT`, 1 thread for zero barrier overhead on `[1, 640, 1, 1]` LSTM steps).
 * - While-holding speculative pre-transcription (`Live.swift` algorithm): encodes & commits speech while
 *   the user is holding the button so releasing the button returns almost immediately.
 */
class VozEngine(private val context: Context) {

    companion object {
        private const val TAG = "VozEngine"
        const val IDLE_UNLOAD_DELAY_MS = 1_800_000L // Keep warm in RAM for 30 minutes of inactivity
        const val KEY_BIAS_MASK = -40000.0f // Float16-representable -infinity
        private const val LIVE_COMMIT_AFTER_SEC = 10.0 // Commit old words once uncommitted audio > 10s
        private const val LIVE_HOLDBACK_SEC = 3.0 // Keep last 3s uncommitted for right-context

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

        /**
         * Ports `Live.swift:agreedPrefix` — returns how many leading words two consecutive passes agree on
         * within 0.25s timestamp tolerance.
         */
        fun agreedPrefixCount(
            previous: List<VozWords.TimedWord>,
            current: List<VozWords.TimedWord>
        ): Int {
            val count = min(previous.size, current.size)
            for (i in 0 until count) {
                val a = previous[i]
                val b = current[i]
                if (a.text != b.text || abs(a.start - b.start) > 0.25 || abs(a.end - b.end) > 0.25) {
                    return i
                }
            }
            return count
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val engineMutex = Mutex()
    private var idleUnloadJob: Job? = null

    // Live while-holding pre-transcription state (`Live.swift` pattern)
    private var liveJob: Job? = null
    @Volatile
    private var liveBaseSampleOffset: Int = 0
    @Volatile
    private var liveCommittedWords: List<VozWords.TimedWord> = emptyList()
    @Volatile
    private var livePrevPassWords: List<VozWords.TimedWord> = emptyList()
    @Volatile
    private var liveLastDecodedSampleEnd: Int = 0
    @Volatile
    private var liveLastDecodedWords: List<VozWords.TimedWord> = emptyList()

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

                // 1. Encoder SessionOptions:
                // - NO_OPT avoids ONNX Runtime's slow naive Gemm fusion on FastConformer
                // - 4 intra-op threads use the 4 big cores (2x X1 + 2x A78 on Tensor G2)
                // - CPUArenaAllocator + MemoryPatternOptimization pre-allocate intermediate layer buffers once
                val encoderOptions = OrtSession.SessionOptions().apply {
                    setOptimizationLevel(OrtSession.SessionOptions.OptLevel.NO_OPT)
                    setIntraOpNumThreads(4)
                    setInterOpNumThreads(1)
                    setCPUArenaAllocator(true)
                    setMemoryPatternOptimization(true)
                    runCatching {
                        addConfigEntry("session.intra_op.allow_spinning", "1")
                        addConfigEntry("session.set_denormal_as_zero", "1")
                    }
                }

                // 2. Decoder SessionOptions:
                // - ALL_OPT optimizes the 2-layer LSTM + Joint projection graph
                // - 1 intra-op thread eliminates multi-thread barrier overhead across 45+ tiny [1, 640, 1, 1] steps!
                val decoderOptions = OrtSession.SessionOptions().apply {
                    setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                    setIntraOpNumThreads(1)
                    setInterOpNumThreads(1)
                    setCPUArenaAllocator(true)
                    setMemoryPatternOptimization(true)
                    runCatching {
                        addConfigEntry("session.set_denormal_as_zero", "1")
                    }
                }

                val encSession = env.createSession(File(dir, "encoder.onnx").absolutePath, encoderOptions)
                val decSession = env.createSession(File(dir, "decoder.onnx").absolutePath, decoderOptions)

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

                // Warm up both encoder & decoder memory arenas so the very first user utterance has 0 arena allocation overhead
                runCatching {
                    runEncoderWindow(env, encSession, FloatArray(1600), config)
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
     * Starts `Live.swift`-style while-holding speculative pre-transcription while the user holds the button.
     * - Commits and trims agreed words on long utterances (>10s) so release only decodes the tail.
     * - Immediately runs a speculative pass when the user pauses at the end of their sentence before lifting
     *   their finger, so `finishLiveSession` can return in 0ms–300ms on `ACTION_UP`!
     */
    fun startLiveSession(audioCapture: AudioCaptureManager) {
        if (!areModelFilesInstalled()) return
        liveJob?.cancel()
        liveBaseSampleOffset = 0
        liveCommittedWords = emptyList()
        livePrevPassWords = emptyList()
        liveLastDecodedSampleEnd = 0
        liveLastDecodedWords = emptyList()

        liveJob = scope.launch {
            runCatching { ensureLoaded() }
            while (isActive && audioCapture.isRecording.value) {
                delay(80L)
                if (!audioCapture.isRecording.value) break

                val rawEnd = audioCapture.getActiveRawSampleCount()
                val baseOffset = liveBaseSampleOffset
                val uncommittedSamples = rawEnd - baseOffset
                val newSamplesSinceLastPass = rawEnd - liveLastDecodedSampleEnd

                // Trigger A: User spoke >= 0.55s and just paused for >= 100ms (likely about to release button!)
                val pauseTriggered = uncommittedSamples >= 8800 &&
                    newSamplesSinceLastPass >= 3200 &&
                    audioCapture.isRecentTailQuiet(1600)

                // Trigger B: User is speaking continuously and has accumulated >= 2.2s of new uncommitted speech
                val streamTriggered = uncommittedSamples >= 35200 &&
                    newSamplesSinceLastPass >= 28800

                if (pauseTriggered || streamTriggered) {
                    val (snapEnd, slice) = audioCapture.getActiveSamplesSnapshot(baseOffset)
                    if (slice.size >= 6400 && audioCapture.isRecording.value) {
                        runCatching {
                            val passWords = engineMutex.withLock {
                                resetIdleUnloadTimerLocked()
                                decodeWordsLocked(
                                    samples = slice,
                                    baseTimeOffsetSec = baseOffset.toDouble() / configuration.sampleRate.toDouble()
                                )
                            }
                            liveLastDecodedSampleEnd = snapEnd
                            liveLastDecodedWords = combineCommittedAndActive(liveCommittedWords, passWords)

                            // Live.swift commit & trim logic for long continuous hold-to-talk
                            val c = configuration
                            val sliceDurationSec = slice.size.toDouble() / c.sampleRate.toDouble()
                            val agreed = agreedPrefixCount(livePrevPassWords, passWords)
                            var commitCount = if (agreed > 1) agreed - 1 else 0

                            if (sliceDurationSec > LIVE_COMMIT_AFTER_SEC) {
                                val cutoffSec = (snapEnd.toDouble() / c.sampleRate.toDouble()) - LIVE_HOLDBACK_SEC
                                val oldCount = passWords.takeWhile { it.end <= cutoffSec }.size
                                if (oldCount > commitCount) {
                                    commitCount = oldCount
                                }
                            }

                            if (commitCount > 0 && commitCount <= passWords.size) {
                                val newlyCommitted = passWords.subList(0, commitCount)
                                val lastWordEndSec = newlyCommitted.last().end
                                val nominalSampleInSlice = ((lastWordEndSec * c.sampleRate) - baseOffset).toInt()
                                    .coerceIn(0, slice.size)
                                val cutInSlice = quietestPoint(
                                    samples = slice,
                                    at = nominalSampleInSlice,
                                    lowest = c.sampleRate / 2,
                                    limit = slice.size,
                                    sampleRate = c.sampleRate
                                )
                                if (cutInSlice > c.sampleRate / 2) {
                                    liveCommittedWords = combineCommittedAndActive(liveCommittedWords, newlyCommitted)
                                    liveBaseSampleOffset = baseOffset + cutInSlice
                                    val newBaseSec = liveBaseSampleOffset.toDouble() / c.sampleRate.toDouble()
                                    livePrevPassWords = passWords.drop(commitCount).filter { it.end > newBaseSec }
                                    Log.i(
                                        TAG,
                                        "Live.swift committed $commitCount words (${liveCommittedWords.size} total), " +
                                            "advanced baseOffset to ${liveBaseSampleOffset / 16000.0}s"
                                    )
                                } else {
                                    livePrevPassWords = passWords
                                }
                            } else {
                                livePrevPassWords = passWords
                            }
                        }.onFailure { e ->
                            Log.w(TAG, "Live pre-transcribe pass aborted: ${e.message}")
                        }
                    }
                }
            }
        }
    }

    /**
     * Cancels any active while-holding live session (e.g., on short tap or interrupt).
     */
    fun cancelLiveSession() {
        liveJob?.cancel()
        liveJob = null
        liveBaseSampleOffset = 0
        liveCommittedWords = emptyList()
        livePrevPassWords = emptyList()
        liveLastDecodedSampleEnd = 0
        liveLastDecodedWords = emptyList()
    }

    /**
     * Finalizes transcription on button release (`ACTION_UP`):
     * 1. Waits for any in-flight speculative pass to complete.
     * 2. If the speculative pass already covered all speech up to `ACTION_UP` (no new speech energy after
     *    `liveLastDecodedSampleEnd`), returns the pre-computed transcript in 0ms!
     * 3. If earlier segments were committed during long speech (`liveBaseSampleOffset > 0`), only decodes
     *    the uncommitted tail and splices it with `liveCommittedWords`.
     * 4. Otherwise decodes `finalSamples` directly.
     */
    suspend fun finishLiveSession(
        finalSamples: FloatArray,
        audioCapture: AudioCaptureManager
    ): String {
        val tRelease0 = System.currentTimeMillis()
        val activeJob = liveJob
        liveJob = null
        if (activeJob != null && activeJob.isActive) {
            // Allow an in-flight pass inside engineMutex to finish so we can reuse its result!
            runCatching { activeJob.cancelAndJoin() }
        }

        // Case 1: Did the while-holding speculative pass already decode all speech before button release?
        val decodedEnd = liveLastDecodedSampleEnd
        val cachedWords = liveLastDecodedWords
        if (decodedEnd > 0 && cachedWords.isNotEmpty() && !audioCapture.hasSpeechAfter(decodedEnd)) {
            val cachedTranscript = cachedWords.joinToString(" ") { it.text }.trim()
            if (cachedTranscript.isNotBlank()) {
                val postReleaseMs = System.currentTimeMillis() - tRelease0
                Log.i(
                    TAG,
                    "Voz Live Turbo HIT! Reused speculative transcript in ${postReleaseMs}ms post-release: \"$cachedTranscript\""
                )
                cancelLiveSession()
                return cachedTranscript
            }
        }

        // Case 2: Did Live.swift commit earlier chunks during a long dictation?
        val committed = liveCommittedWords
        val baseOffset = liveBaseSampleOffset
        if (baseOffset > 0 && committed.isNotEmpty()) {
            val (_, tailSlice) = audioCapture.getActiveSamplesSnapshot(baseOffset)
            ensureLoaded()
            val tailWords = engineMutex.withLock {
                resetIdleUnloadTimerLocked()
                if (tailSlice.size >= 1600 && audioCapture.hasSpeechAfter(baseOffset)) {
                    decodeWordsLocked(
                        samples = tailSlice,
                        baseTimeOffsetSec = baseOffset.toDouble() / configuration.sampleRate.toDouble()
                    )
                } else {
                    emptyList()
                }
            }
            val allWords = combineCommittedAndActive(committed, tailWords)
            val finalTranscript = allWords.joinToString(" ") { it.text }.trim()
            val postReleaseMs = System.currentTimeMillis() - tRelease0
            Log.i(
                TAG,
                "Voz Live Turbo COMMITTED+TAIL finished in ${postReleaseMs}ms post-release: \"$finalTranscript\""
            )
            cancelLiveSession()
            if (finalTranscript.isNotBlank()) {
                return finalTranscript
            }
        }

        cancelLiveSession()
        return transcribe(finalSamples)
    }

    private fun combineCommittedAndActive(
        committed: List<VozWords.TimedWord>,
        active: List<VozWords.TimedWord>
    ): List<VozWords.TimedWord> {
        if (committed.isEmpty()) return active
        if (active.isEmpty()) return committed
        val (repairedP, repairedS) = VozWords.repairJoin(committed, active)
        return repairedP + repairedS
    }

    /**
     * Transcribes 16 kHz mono float32 PCM samples using `desert-ant-labs/voz`.
     */
    suspend fun transcribe(samples: FloatArray): String {
        if (samples.isEmpty()) return ""
        ensureLoaded()

        return engineMutex.withLock {
            resetIdleUnloadTimerLocked()
            val words = decodeWordsLocked(samples, baseTimeOffsetSec = 0.0)
            val finalTranscript = words.joinToString(" ") { it.text }.trim()
            Log.i(TAG, "Final transcript: \"$finalTranscript\"")
            finalTranscript
        }
    }

    private suspend fun decodeWordsLocked(
        samples: FloatArray,
        baseTimeOffsetSec: Double
    ): List<VozWords.TimedWord> = withContext(Dispatchers.Default) {
        if (samples.isEmpty()) return@withContext emptyList()
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
            var prevWindowEndSec = baseTimeOffsetSec

            for ((windowStartSample, windowSlice) in windows) {
                val windowStartSec = baseTimeOffsetSec + windowStartSample.toDouble() / c.sampleRate.toDouble()
                val windowEndSec = baseTimeOffsetSec + (windowStartSample + windowSlice.size).toDouble() / c.sampleRate.toDouble()

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

            mergedWords
        } finally {
            runCatching {
                Process.setThreadPriority(prevPriority)
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

        // Pre-create the 4 OnnxTensor wrappers ONCE outside the TDT decode loop!
        // Since they wrap Direct ByteBuffers, mutating embedDirect/hInDirect/cInDirect/encStepDirect in-place
        // updates the underlying native memory with zero JNI tensor allocation/deallocation per step.
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

                            // 3. Update zero-copy Direct FloatBuffers in-place
                            embedDirect.clear(); embedDirect.put(embed); embedDirect.rewind()
                            hInDirect.clear(); hInDirect.put(hIn); hInDirect.rewind()
                            cInDirect.clear(); cInDirect.put(cIn); cInDirect.rewind()
                            encStepDirect.clear(); encStepDirect.put(encStep); encStepDirect.rewind()

                            var tok0 = blank
                            var tok1 = blank
                            var dur0 = 0
                            var dur1 = 0

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
                    }
                }
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
