package com.sayitflow.android.ml

import org.json.JSONObject

/**
 * Geometry and model parameters decoded from `desert-ant-labs/voz/resolve/main/web/meta.json`.
 */
data class VozConfiguration(
    val sampleRate: Int = 16000,
    val hopLength: Int = 160,
    val nSamples: Int = 240000,
    val nRows: Int = 1503,
    val nMels: Int = 128,
    val nFFT: Int = 512,
    val preemph: Float = 0.97f,
    val nPaddedSamples: Int = 240480,
    val validFrames: Int = 1500,
    val encFrames: Int = 188,
    val jointHidden: Int = 640,
    val predHidden: Int = 640,
    val predLayers: Int = 2,
    val vocabSize: Int = 8192,
    val blankIdx: Int = 8192,
    val durations: IntArray = intArrayOf(0, 1, 2, 3, 4),
    val decodeWidth: Int = 2,
    val decodeLanes: Int = 16,
    val fusedFrontend: Boolean = true,
    val encoderExternal: String = "encoder.onnx.data"
) {
    fun validate() {
        require(sampleRate > 0 && hopLength > 0) { "sampleRate and hopLength must be positive" }
        require(nSamples > 0 && nRows > 0 && nMels > 0 && nFFT > 0) { "frontend dimensions must be positive" }
        require(nPaddedSamples >= nSamples + nFFT / 2) { "nPaddedSamples is smaller than left-padded window" }
        require(validFrames > 0 && encFrames > 0) { "frame counts must be positive" }
        require(jointHidden > 0 && predHidden > 0 && predLayers > 0) { "hidden dimensions must be positive" }
        require(vocabSize > 0 && blankIdx == vocabSize) { "blankIdx must equal vocabSize" }
        require(durations.isNotEmpty() && decodeWidth > 0) { "durations and decodeWidth must be non-empty" }
    }

    companion object {
        fun fromJson(jsonString: String): VozConfiguration {
            val obj = JSONObject(jsonString)
            val durArray = obj.optJSONArray("durations")
            val durations = if (durArray != null) {
                IntArray(durArray.length()) { i -> durArray.getInt(i) }
            } else {
                intArrayOf(0, 1, 2, 3, 4)
            }
            return VozConfiguration(
                sampleRate = obj.optInt("sample_rate", 16000),
                hopLength = obj.optInt("hop_length", 160),
                nSamples = obj.optInt("n_samples", 240000),
                nRows = obj.optInt("n_rows", 1503),
                nMels = obj.optInt("n_mels", 128),
                nFFT = obj.optInt("n_fft", 512),
                preemph = obj.optDouble("preemph", 0.97).toFloat(),
                nPaddedSamples = obj.optInt("n_padded_samples", 240480),
                validFrames = obj.optInt("valid_frames", 1500),
                encFrames = obj.optInt("enc_frames", 188),
                jointHidden = obj.optInt("joint_hidden", 640),
                predHidden = obj.optInt("pred_hidden", 640),
                predLayers = obj.optInt("pred_layers", 2),
                vocabSize = obj.optInt("vocab_size", 8192),
                blankIdx = obj.optInt("blank_idx", 8192),
                durations = durations,
                decodeWidth = obj.optInt("decode_width", 2),
                decodeLanes = obj.optInt("decode_lanes", 16),
                fusedFrontend = obj.optBoolean("fused_frontend", true),
                encoderExternal = obj.optString("encoder_external", "encoder.onnx.data")
            ).also { it.validate() }
        }
    }
}
