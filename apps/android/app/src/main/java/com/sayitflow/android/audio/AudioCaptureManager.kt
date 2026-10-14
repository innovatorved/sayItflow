package com.sayitflow.android.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Zero-loss low-latency 16 kHz mono PCM audio capture manager.
 *
 * Implements a 3-phase zero-loss hold-to-talk pipeline:
 * 1. Immediate circular pre-roll buffering on `ACTION_DOWN` (at least 1.5s = 24,000 samples @ 16kHz)
 *    so 0ms of initial speech is lost while waiting for the button hold delay threshold.
 * 2. Smooth promotion to active recording at the hold threshold (e.g. 500ms) without clearing or dropping audio.
 * 3. 200ms post-release acoustic tail capture on `ACTION_UP` before stopping `AudioRecord` to prevent
 *    clipping word-final consonants.
 * 4. Soft dynamic gain normalization without destructive noise-gate drops (`peak < 0.006f`, `0.04f` cutoffs)
 *    so quiet or rapid short utterances are preserved.
 */
class AudioCaptureManager {

    companion object {
        private const val TAG = "AudioCaptureManager"
        const val SAMPLE_RATE = 16000
        const val MAX_SECONDS = 120
        const val MAX_SAMPLES = SAMPLE_RATE * MAX_SECONDS
        const val PRE_ROLL_SAMPLES = 24000 // 1.5 seconds circular pre-roll buffer
        const val TAIL_CAPTURE_SAMPLES = 3200 // 200ms post-release tail
        const val WAVEFORM_BARS = 7
    }

    enum class CaptureState {
        IDLE,
        PRE_ROLL,
        ACTIVE,
        STOPPING
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var recordJob: Job? = null
    private var audioRecord: AudioRecord? = null

    // Main 120-second PCM buffer ([-1.0f, 1.0f])
    private val sampleBuffer = FloatArray(MAX_SAMPLES)
    @Volatile
    private var recordedSampleCount = 0

    // Circular pre-roll ring buffer (at least 1.5s = 24,000 samples @ 16kHz)
    private val preRollRingBuffer = FloatArray(PRE_ROLL_SAMPLES)
    @Volatile
    private var preRollHead = 0
    @Volatile
    private var preRollCount = 0

    private val captureState = AtomicReference(CaptureState.IDLE)
    private val lock = Any()

    @Volatile
    var lastRawDurationMs: Long = 0L
        private set

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _waveformLevels = MutableStateFlow(FloatArray(WAVEFORM_BARS) { 0.12f })
    val waveformLevels: StateFlow<FloatArray> = _waveformLevels.asStateFlow()

    /**
     * Phase 1: Immediately starts circular pre-roll buffering on `ACTION_DOWN` (repeatCount == 0).
     * Buffers up to 1.5s of 16kHz audio in memory so speech during the hold delay (0–500ms) is never lost.
     */
    @SuppressLint("MissingPermission")
    fun startPreRoll(): Boolean {
        synchronized(lock) {
            val current = captureState.get()
            if (current == CaptureState.PRE_ROLL || current == CaptureState.ACTIVE) {
                return true
            }

            preRollHead = 0
            preRollCount = 0
            recordedSampleCount = 0
            captureState.set(CaptureState.PRE_ROLL)

            val initialized = initAndStartAudioRecord()
            if (!initialized) {
                captureState.set(CaptureState.IDLE)
                return false
            }
            return true
        }
    }

    /**
     * Phase 2: Called when the button hold delay (e.g. 500ms) elapses.
     * Smoothly promotes buffered pre-roll audio into the active recording buffer without clearing it.
     */
    fun promoteToActiveRecording(): Boolean {
        synchronized(lock) {
            val current = captureState.get()
            if (current == CaptureState.ACTIVE) return true
            if (current == CaptureState.IDLE) {
                return startRecording()
            }

            // Unroll circular pre-roll buffer in exact chronological order into sampleBuffer
            val count = preRollCount.coerceAtMost(PRE_ROLL_SAMPLES)
            val startIdx = if (preRollCount >= PRE_ROLL_SAMPLES) preRollHead else 0
            for (i in 0 until count) {
                val ringIdx = (startIdx + i) % PRE_ROLL_SAMPLES
                sampleBuffer[i] = preRollRingBuffer[ringIdx]
            }
            recordedSampleCount = count

            captureState.set(CaptureState.ACTIVE)
            _isRecording.value = true
            Log.i(TAG, "Promoted pre-roll to active: $count samples (${(count * 1000) / SAMPLE_RATE}ms) preserved")
            return true
        }
    }

    /**
     * Discards pre-roll capture if button was released before the hold threshold (short tap).
     */
    fun discardPreRoll() {
        synchronized(lock) {
            val current = captureState.get()
            if (current != CaptureState.IDLE) {
                captureState.set(CaptureState.IDLE)
                _isRecording.value = false
                stopAudioRecordInternal()
                preRollHead = 0
                preRollCount = 0
                recordedSampleCount = 0
                _waveformLevels.value = FloatArray(WAVEFORM_BARS) { 0.12f }
            }
        }
    }

    /**
     * Test-only helper to feed samples into circular pre-roll buffer without hardware AudioRecord.
     */
    fun testPushPreRollSamples(samples: FloatArray) {
        synchronized(lock) {
            captureState.set(CaptureState.PRE_ROLL)
            for (s in samples) {
                preRollRingBuffer[preRollHead] = s
                preRollHead = (preRollHead + 1) % PRE_ROLL_SAMPLES
                if (preRollCount < PRE_ROLL_SAMPLES) {
                    preRollCount++
                }
            }
        }
    }

    /**
     * Test-only helper to inspect unrolled recorded samples.
     */
    fun getRecordedSamplesForTesting(): FloatArray {
        synchronized(lock) {
            return sampleBuffer.copyOf(recordedSampleCount)
        }
    }

    /**
     * Direct recording entrypoint (for compatibility / in-app studio record button).
     */
    @SuppressLint("MissingPermission")
    fun startRecording(): Boolean {
        synchronized(lock) {
            if (captureState.get() == CaptureState.ACTIVE) return true

            recordedSampleCount = 0
            preRollHead = 0
            preRollCount = 0
            captureState.set(CaptureState.ACTIVE)
            _isRecording.value = true

            val initialized = initAndStartAudioRecord()
            if (!initialized) {
                captureState.set(CaptureState.IDLE)
                _isRecording.value = false
                return false
            }
            return true
        }
    }

    @SuppressLint("MissingPermission")
    private fun initAndStartAudioRecord(): Boolean {
        if (audioRecord != null && audioRecord?.state == AudioRecord.STATE_INITIALIZED) {
            return true
        }

        val minBufBytes = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBufBytes <= 0) return false

        val bufferSizeBytes = maxOf(minBufBytes * 2, 6400)
        var recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSizeBytes
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            recorder = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSizeBytes
            )
        }

        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord failed to initialize")
            recorder.release()
            return false
        }

        audioRecord = recorder
        try {
            recorder.startRecording()
        } catch (e: Exception) {
            Log.e(TAG, "AudioRecord.startRecording failed", e)
            recorder.release()
            audioRecord = null
            return false
        }

        startCaptureLoop(recorder)
        return true
    }

    private fun startCaptureLoop(recorder: AudioRecord) {
        recordJob?.cancel()
        recordJob = scope.launch {
            val readShorts = ShortArray(800) // 50 ms chunks at 16 kHz
            val rollingBars = FloatArray(WAVEFORM_BARS) { 0.12f }

            while (isActive && captureState.get() != CaptureState.IDLE && captureState.get() != CaptureState.STOPPING) {
                val read = recorder.read(readShorts, 0, readShorts.size)
                if (read > 0) {
                    var chunkSumSq = 0.0
                    var chunkMaxPeak = 0f

                    synchronized(lock) {
                        for (i in 0 until read) {
                            val normalized = readShorts[i] / 32768.0f
                            chunkSumSq += normalized * normalized
                            val a = abs(normalized)
                            if (a > chunkMaxPeak) chunkMaxPeak = a

                            when (captureState.get()) {
                                CaptureState.PRE_ROLL -> {
                                    preRollRingBuffer[preRollHead] = normalized
                                    preRollHead = (preRollHead + 1) % PRE_ROLL_SAMPLES
                                    if (preRollCount < PRE_ROLL_SAMPLES) {
                                        preRollCount++
                                    }
                                }
                                CaptureState.ACTIVE -> {
                                    if (recordedSampleCount < MAX_SAMPLES) {
                                        sampleBuffer[recordedSampleCount] = normalized
                                        recordedSampleCount++
                                    }
                                }
                                else -> {}
                            }
                        }
                    }

                    // Update waveform level meter
                    val rms = sqrt(chunkSumSq / read).toFloat()
                    val level = max(rms * 8.0f, chunkMaxPeak * 2.2f).coerceIn(0.10f, 1.0f)
                    for (b in 0 until (WAVEFORM_BARS - 1)) {
                        rollingBars[b] = rollingBars[b + 1]
                    }
                    rollingBars[WAVEFORM_BARS - 1] = level
                    _waveformLevels.value = rollingBars.copyOf()
                }
            }
        }
    }

    /**
     * Returns the current raw sample count in `sampleBuffer` while recording is active.
     */
    fun getActiveRawSampleCount(): Int {
        synchronized(lock) {
            return recordedSampleCount.coerceIn(0, MAX_SAMPLES)
        }
    }

    /**
     * Returns `(rawEndSampleIndex, normalizedSamples)` from `fromSample` up to current `recordedSampleCount`
     * without stopping recording or altering indices, so `VozEngine` can pre-transcribe while the user holds the button.
     */
    fun getActiveSamplesSnapshot(fromSample: Int = 0): Pair<Int, FloatArray> {
        val rawSlice: FloatArray
        val endSample: Int
        synchronized(lock) {
            endSample = recordedSampleCount.coerceIn(0, MAX_SAMPLES)
            val start = fromSample.coerceIn(0, endSample)
            if (endSample - start <= 0) {
                return endSample to FloatArray(0)
            }
            rawSlice = sampleBuffer.copyOfRange(start, endSample)
        }
        return endSample to normalizeSlicePreserveTiming(rawSlice)
    }

    /**
     * Checks whether any speech energy occurred in `sampleBuffer` after `sampleIndex`.
     * Used on button release (`ACTION_UP`) to reuse an already-computed or in-flight speculative pass
     * if the user only had trailing silence before lifting their finger.
     */
    fun hasSpeechAfter(sampleIndex: Int): Boolean {
        synchronized(lock) {
            val end = recordedSampleCount.coerceIn(0, MAX_SAMPLES)
            val start = sampleIndex.coerceIn(0, end)
            val count = end - start
            if (count < 480) return false // < 30ms cannot contain a new syllable
            var sum = 0.0
            for (i in start until end) sum += sampleBuffer[i]
            val dc = (sum / count).toFloat()

            var peak = 0f
            var sumSq = 0.0
            var activeSamples = 0
            for (i in start until end) {
                val v = abs(sampleBuffer[i] - dc)
                if (v > peak) peak = v
                if (v > 0.038f) activeSamples++
                sumSq += v * v
            }
            val rms = sqrt(sumSq / count).toFloat()
            // Require meaningful speech energy (at least 25ms of activevoiced frames)
            return peak > 0.048f && rms > 0.015f && activeSamples >= 400
        }
    }

    /**
     * Checks whether the tail of the active buffer (last `windowSamples`) is currently quiet
     * (i.e. the user just paused at the end of a phrase while holding the button).
     */
    fun isRecentTailQuiet(windowSamples: Int = 1920): Boolean {
        synchronized(lock) {
            val end = recordedSampleCount.coerceIn(0, MAX_SAMPLES)
            if (end < windowSamples) return false
            val start = end - windowSamples
            var sumSq = 0.0
            var peak = 0f
            for (i in start until end) {
                val a = abs(sampleBuffer[i])
                if (a > peak) peak = a
                sumSq += a * a
            }
            val rms = sqrt(sumSq / windowSamples).toFloat()
            return peak < 0.042f && rms < 0.014f
        }
    }

    private fun normalizeSlicePreserveTiming(samples: FloatArray): FloatArray {
        if (samples.isEmpty()) return samples
        var mean = 0.0
        for (s in samples) mean += s
        mean /= samples.size
        val dc = mean.toFloat()

        var peak = 0f
        val out = FloatArray(samples.size)
        for (i in samples.indices) {
            val v = (samples[i] - dc).coerceIn(-1.0f, 1.0f)
            out[i] = v
            val a = abs(v)
            if (a > peak) peak = a
        }
        val gain = if (peak > 0.0001f && peak < 0.70f) {
            (0.78f / peak).coerceIn(1.0f, 8.0f)
        } else {
            1.0f
        }
        if (gain > 1.0f) {
            for (i in out.indices) {
                out[i] = (out[i] * gain).coerceIn(-1.0f, 1.0f)
            }
        }
        return out
    }

    /**
     * Non-blocking asynchronous stopRecording entry point.
     * Captures post-release acoustic tail on Dispatchers.IO so Main Looper is never blocked.
     */
    suspend fun stopRecordingAsync(): FloatArray = withContext(Dispatchers.IO) {
        stopRecording()
    }

    /**
     * Phase 3: Stops recording with adaptive post-release tail capture on `ACTION_UP`.
     * - If the last 100ms before `ACTION_UP` are already quiet (user finished speaking before releasing),
     *   captures only 40ms (640 samples) of tail, saving 160ms of latency.
     * - Otherwise captures 100ms (1,600 samples) to preserve final consonants.
     */
    fun stopRecording(): FloatArray {
        synchronized(lock) {
            val state = captureState.get()
            if (state == CaptureState.IDLE) return FloatArray(0)

            captureState.set(CaptureState.STOPPING)
            _isRecording.value = false

            // Check if the last 100ms (1,600 samples) before button release are already quiet
            var recentPeak = 0f
            val checkStart = max(0, recordedSampleCount - 1600)
            for (i in checkStart until recordedSampleCount) {
                val a = abs(sampleBuffer[i])
                if (a > recentPeak) recentPeak = a
            }
            val targetTailSamples = if (recordedSampleCount >= 1600 && recentPeak < 0.038f) {
                640 // 40ms fast tail when user already paused before releasing
            } else {
                1600 // 100ms tail when user released immediately at end of word
            }

            val recorder = audioRecord
            if (recorder != null && recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val tailShorts = ShortArray(640)
                var tailCaptured = 0
                while (tailCaptured < targetTailSamples && recordedSampleCount < MAX_SAMPLES) {
                    val toRead = min(tailShorts.size, targetTailSamples - tailCaptured)
                    val read = recorder.read(tailShorts, 0, toRead)
                    if (read <= 0) break
                    for (i in 0 until read) {
                        if (recordedSampleCount < MAX_SAMPLES) {
                            sampleBuffer[recordedSampleCount] = tailShorts[i] / 32768.0f
                            recordedSampleCount++
                            tailCaptured++
                        }
                    }
                }
            }

            stopAudioRecordInternal()
            captureState.set(CaptureState.IDLE)
            _waveformLevels.value = FloatArray(WAVEFORM_BARS) { 0.12f }

            val count = recordedSampleCount.coerceIn(0, MAX_SAMPLES)
            lastRawDurationMs = (count * 1000L) / SAMPLE_RATE
            if (count == 0) return FloatArray(0)

            val raw = sampleBuffer.copyOfRange(0, count)
            return normalizeAndPrepareSpeech(raw)
        }
    }

    private fun stopAudioRecordInternal() {
        val job = recordJob
        recordJob = null
        job?.cancel()

        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }
        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }
        audioRecord = null
    }

    /**
     * Soft dynamic gain normalization:
     * - Removes DC offset.
     * - Softly scales speech into optimal target amplitude (~0.78 peak) with up to 8x boost.
     * - CRITICAL: Completely eliminates destructive silence drop thresholds (e.g. `peak < 0.006f`
     *   or `0.04f` cutoffs) so rapid short bursts, soft voices, and pauses are never discarded.
     * - Preserves audio integrity without returning empty arrays on quiet inputs.
     */
    fun normalizeAndPrepareSpeech(samples: FloatArray): FloatArray {
        if (samples.isEmpty()) return samples

        // 1. Remove DC offset
        var mean = 0.0
        for (s in samples) mean += s
        mean /= samples.size
        val dc = mean.toFloat()

        var peak = 0f
        var sumSq = 0.0
        val centered = FloatArray(samples.size)
        for (i in samples.indices) {
            val v = (samples[i] - dc).coerceIn(-1.0f, 1.0f)
            centered[i] = v
            val a = abs(v)
            if (a > peak) peak = a
            sumSq += v * v
        }
        val rms = sqrt(sumSq / samples.size).toFloat()
        Log.i(TAG, "Captured ${samples.size} samples (${samples.size * 1000L / SAMPLE_RATE}ms) | peak=$peak | rms=$rms")

        // 2. Soft dynamic gain normalization: target peak ~0.78f (up to 8.0x boost for quiet captures)
        val gain = if (peak > 0.0001f && peak < 0.70f) {
            (0.78f / peak).coerceIn(1.0f, 8.0f)
        } else {
            1.0f
        }

        if (gain > 1.0f) {
            for (i in centered.indices) {
                centered[i] = (centered[i] * gain).coerceIn(-1.0f, 1.0f)
            }
        }

        // 3. Gentle lead/tail trim only if recording is sufficiently long (> 1.2 seconds)
        // Keeps at least 120ms lead-in and 200ms tail so no phonemes are ever cut off.
        // NEVER returns FloatArray(0) — always preserves the audio signal!
        if (centered.size > (SAMPLE_RATE * 1.2).toInt()) {
            val softThresh = max(0.015f, rms * gain * 0.4f)
            var firstActive = 0
            while (firstActive < centered.size && abs(centered[firstActive]) < softThresh) {
                firstActive++
            }
            var lastActive = centered.size - 1
            while (lastActive > firstActive && abs(centered[lastActive]) < softThresh) {
                lastActive--
            }

            if (firstActive < lastActive) {
                val leadPad = (SAMPLE_RATE * 0.12).toInt() // 120ms
                val tailPad = (SAMPLE_RATE * 0.20).toInt() // 200ms
                val trimStart = max(0, firstActive - leadPad)
                val trimEnd = min(centered.size, lastActive + tailPad + 1)
                if (trimStart > 0 || trimEnd < centered.size) {
                    return centered.copyOfRange(trimStart, trimEnd)
                }
            }
        }

        return centered
    }
}
