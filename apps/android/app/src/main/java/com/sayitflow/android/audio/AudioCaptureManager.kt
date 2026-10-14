package com.sayitflow.android.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Low-latency 16 kHz mono PCM audio capture manager for Google Pixel.
 * Uses a pre-allocated 120-second ring buffer (`1,920,000` floats = 7.68 MB)
 * so zero heap allocations occur during real-time recording.
 */
class AudioCaptureManager {

    companion object {
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

        val recorder = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(minBufBytes * 2, 6400)
        )

        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return false
        }

        recordedSampleCount = 0
        audioRecord = recorder
        recorder.startRecording()
        _isRecording.value = true

        recordJob = scope.launch {
            val readShorts = ShortArray(1600) // 100 ms chunks at 16 kHz
            val rollingBars = FloatArray(WAVEFORM_BARS) { 0.12f }

            while (isActive && _isRecording.value) {
                val read = recorder.read(readShorts, 0, readShorts.size)
                if (read > 0) {
                    var sumSq = 0.0
                    val startWrite = recordedSampleCount
                    val limit = min(read, MAX_SAMPLES - startWrite)
                    for (i in 0 until limit) {
                        val normalized = readShorts[i] / 32768.0f
                        sampleBuffer[startWrite + i] = normalized
                        sumSq += normalized * normalized
                    }
                    recordedSampleCount = startWrite + limit

                    val rms = sqrt(sumSq / read).toFloat()
                    val level = (rms * 6.5f).coerceIn(0.10f, 1.0f)
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
     * Stops recording and returns a trimmed copy of the captured 16 kHz float32 samples.
     */
    fun stopRecording(): FloatArray {
        _isRecording.value = false
        recordJob?.cancel()
        recordJob = null

        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }
        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }
        audioRecord = null
        _waveformLevels.value = FloatArray(WAVEFORM_BARS) { 0.12f }

        val count = recordedSampleCount.coerceIn(0, MAX_SAMPLES)
        if (count == 0) return FloatArray(0)
        return sampleBuffer.copyOfRange(0, count)
    }
}
