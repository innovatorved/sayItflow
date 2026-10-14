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
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Low-latency 16 kHz mono PCM audio capture manager for Google Pixel.
 * Uses a pre-allocated 120-second ring buffer (`1,920,000` floats = 7.68 MB)
 * and automatic speech peak normalization so `desert-ant-labs/voz` always receives
 * clean, well-scaled audio regardless of microphone distance.
 */
class AudioCaptureManager {

    companion object {
        private const val TAG = "AudioCaptureManager"
        const val SAMPLE_RATE = 16000
        const val MAX_SECONDS = 120
        const val MAX_SAMPLES = SAMPLE_RATE * MAX_SECONDS
        const val WAVEFORM_BARS = 7
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var recordJob: Job? = null
    private var audioRecord: AudioRecord? = null

    // Pre-allocated 120-second PCM buffer ([-1.0f, 1.0f])
    private val sampleBuffer = FloatArray(MAX_SAMPLES)
    @Volatile
    private var recordedSampleCount = 0
    @Volatile
    var lastRawDurationMs: Long = 0L
        private set

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _waveformLevels = MutableStateFlow(FloatArray(WAVEFORM_BARS) { 0.12f })
    val waveformLevels: StateFlow<FloatArray> = _waveformLevels.asStateFlow()

    @SuppressLint("MissingPermission")
    fun startRecording(): Boolean {
        if (_isRecording.value) return true

        val minBufBytes = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBufBytes <= 0) return false

        val bufferSizeBytes = maxOf(minBufBytes * 2, 6400)
        // Prefer MIC on Pixel so hardware AGC / speech microphone routing gives strong signal;
        // fallback to VOICE_RECOGNITION if MIC fails to initialize.
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

        recordedSampleCount = 0
        audioRecord = recorder
        try {
            recorder.startRecording()
        } catch (e: Exception) {
            Log.e(TAG, "AudioRecord.startRecording failed", e)
            recorder.release()
            audioRecord = null
            return false
        }
        _isRecording.value = true

        recordJob = scope.launch {
            val readShorts = ShortArray(1600) // 100 ms chunks at 16 kHz
            val rollingBars = FloatArray(WAVEFORM_BARS) { 0.12f }

            while (isActive && _isRecording.value) {
                val read = recorder.read(readShorts, 0, readShorts.size)
                if (read > 0) {
                    var sumSq = 0.0
                    var chunkPeak = 0f
                    val startWrite = recordedSampleCount
                    val limit = min(read, MAX_SAMPLES - startWrite)
                    for (i in 0 until limit) {
                        val normalized = readShorts[i] / 32768.0f
                        sampleBuffer[startWrite + i] = normalized
                        sumSq += normalized * normalized
                        val a = abs(normalized)
                        if (a > chunkPeak) chunkPeak = a
                    }
                    recordedSampleCount = startWrite + limit

                    val rms = sqrt(sumSq / read).toFloat()
                    val level = max(rms * 8.0f, chunkPeak * 2.2f).coerceIn(0.10f, 1.0f)
                    for (b in 0 until (WAVEFORM_BARS - 1)) {
                        rollingBars[b] = rollingBars[b + 1]
                    }
                    rollingBars[WAVEFORM_BARS - 1] = level
                    _waveformLevels.value = rollingBars.copyOf()
                }
            }
        }
        return true
    }

    /**
     * Stops recording and returns normalized 16 kHz float32 samples ready for `VozEngine`.
     */
    fun stopRecording(): FloatArray {
        _isRecording.value = false
        val jobToJoin = recordJob
        recordJob = null

        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }
        jobToJoin?.cancel()
        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }
        audioRecord = null
        _waveformLevels.value = FloatArray(WAVEFORM_BARS) { 0.12f }

        val count = recordedSampleCount.coerceIn(0, MAX_SAMPLES)
        lastRawDurationMs = (count * 1000L) / SAMPLE_RATE
        if (count == 0) return FloatArray(0)

        val raw = sampleBuffer.copyOfRange(0, count)
        return normalizeAndPrepareSpeech(raw)
    }

    /**
     * Removes DC offset and normalizes quiet microphone captures so `desert-ant-labs/voz`
     * receives optimal signal amplitude (`~0.80` peak).
     */
    private fun normalizeAndPrepareSpeech(samples: FloatArray): FloatArray {
        if (samples.isEmpty()) return samples

        // 1. Compute mean (DC offset)
        var mean = 0.0
        for (s in samples) mean += s
        mean /= samples.size
        val dc = mean.toFloat()

        // 2. Remove DC offset and measure peak & RMS
        var peak = 0f
        var sumSq = 0.0
        for (i in samples.indices) {
            val v = (samples[i] - dc).coerceIn(-1.0f, 1.0f)
            samples[i] = v
            val a = abs(v)
            if (a > peak) peak = a
            sumSq += v * v
        }
        val rms = sqrt(sumSq / samples.size).toFloat()
        Log.i(
            TAG,
            "Captured ${samples.size} samples (${String.format("%.2f", samples.size / 16000.0)}s) | peak=$peak | rms=$rms"
        )

        // If pure hardware silence or quiet room hiss without speech, return empty immediately
        // so Voz-0.6B does not waste time running encoder over silent audio.
        if (peak < 0.006f || rms < 0.0012f) {
            return FloatArray(0)
        }

        // 3. Peak-normalize speech into target peak ~0.78f (up to 8x boost for quiet mic captures)
        val gain = if (peak < 0.70f) (0.78f / peak).coerceIn(1.0f, 8.0f) else 1.0f
        if (gain > 1.0f) {
            for (i in samples.indices) {
                samples[i] = (samples[i] * gain).coerceIn(-1.0f, 1.0f)
            }
        }
        val normRms = (rms * gain).coerceAtMost(0.5f)

        // 4. Trim excess leading/trailing silence (keeping 80ms lead-in and 160ms tail)
        // so VozEngine's validEncoderFrames only decodes active speech frames.
        val thresh = max(0.04f, normRms * 0.65f)
        var firstActive = 0
        while (firstActive < samples.size && abs(samples[firstActive]) < thresh) {
            firstActive++
        }
        if (firstActive >= samples.size) {
            return FloatArray(0)
        }
        var lastActive = samples.size - 1
        while (lastActive > firstActive && abs(samples[lastActive]) < thresh) {
            lastActive--
        }

        val leadPad = (SAMPLE_RATE * 0.08).toInt() // 80ms
        val tailPad = (SAMPLE_RATE * 0.16).toInt() // 160ms
        val trimStart = max(0, firstActive - leadPad)
        val trimEnd = min(samples.size, lastActive + tailPad + 1)

        return if (trimStart > 0 || trimEnd < samples.size) {
            samples.copyOfRange(trimStart, trimEnd)
        } else {
            samples
        }
    }
}
