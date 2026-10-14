package com.sayitflow.android

import com.sayitflow.android.ml.PolishOutputGuard
import com.sayitflow.android.ml.VozConfiguration
import com.sayitflow.android.ml.VozEngine
import com.sayitflow.android.ml.VozWords
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class VozPipelineTest {

    @Test
    fun parsesExactDesertAntVozMetaJson() {
        val metaJson = """
            {"sample_rate": 16000, "hop_length": 160, "n_samples": 240000, "n_rows": 1503,
             "n_mels": 128, "n_fft": 512, "preemph": 0.97, "n_padded_samples": 240480,
             "valid_frames": 1500, "enc_frames": 188, "joint_hidden": 640, "pred_hidden": 640,
             "pred_layers": 2, "vocab_size": 8192, "blank_idx": 8192,
             "durations": [0, 1, 2, 3, 4], "decode_width": 2, "fused_frontend": true,
             "encoder_external": "encoder.onnx.data"}
        """.trimIndent()

        val config = VozConfiguration.fromJson(metaJson)
        assertEquals(16000, config.sampleRate)
        assertEquals(160, config.hopLength)
        assertEquals(240000, config.nSamples)
        assertEquals(1503, config.nRows)
        assertEquals(188, config.encFrames)
        assertEquals(8192, config.vocabSize)
        assertEquals(8192, config.blankIdx)
        assertEquals(2, config.decodeWidth)
        assertTrue(config.fusedFrontend)
    }

    @Test
    fun stagesWindowWithExactCenterPadMasksAndGeometricTail() {
        val c = VozConfiguration()
        // 1 second clip = 16,000 samples
        val clip = FloatArray(16000) { idx -> if (idx == 0) 0.5f else 0.25f }
        val staged = VozEngine.stageWindow(clip, c)

        assertEquals(c.hopLength * c.nRows, staged.audioRows.size)
        // Left pad is nFFT / 2 = 256 samples, so i = 256 -> row = 256 % 160 = 96, col = 256 / 160 = 1
        assertEquals(0.5f, staged.audioRows[96 * c.nRows + 1], 1e-6f)

        // Valid mel frames for 16,000 samples = 16000 / 160 + 1 = 101
        assertEquals(101, VozEngine.validMelFrames(clip.size, c))
        assertEquals(1.0f, staged.melMask[100], 1e-6f)
        assertEquals(0.0f, staged.melMask[101], 1e-6f)

        // Attended encoder frames for 16,000 samples = (16000 + 1279) / 1280 = 13
        assertEquals(13, VozEngine.attendedEncoderFrames(clip.size, c))
        assertEquals(0.0f, staged.keyBias[12], 1e-6f)
        assertEquals(-40000.0f, staged.keyBias[13], 1e-3f)
    }

    @Test
    fun widensFloat16EmbeddingTableCorrectly() {
        // IEEE-754 float16: 0x3C00 = 1.0f, 0xC000 = -2.0f, 0x3800 = 0.5f, 0x0000 = 0.0f
        val buf = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
        buf.putShort(0x3C00.toShort())
        buf.putShort(0xC000.toShort())
        buf.putShort(0x3800.toShort())
        buf.putShort(0x0000.toShort())

        val floats = VozWords.decodeFloat16Embedding(buf.array(), 4)
        assertEquals(1.0f, floats[0], 1e-6f)
        assertEquals(-2.0f, floats[1], 1e-6f)
        assertEquals(0.5f, floats[2], 1e-6f)
        assertEquals(0.0f, floats[3], 1e-6f)
    }

    @Test
    fun assemblesSentencePieceWordsAndSplicesOverlaps() {
        val vocab = listOf("\u2581Hello", "\u2581world", "!", "<pad>", "\u2581from", "\u2581Pixel")
        val words1 = VozWords.assembleWords(
            tokens = intArrayOf(0, 1, 2, 3),
            frames = intArrayOf(1, 3, 4, 5),
            ends = intArrayOf(2, 4, 5, 6),
            windowStartSeconds = 0.0,
            secondsPerEncoderFrame = 0.08,
            vocabulary = vocab
        )
        assertEquals(listOf("Hello", "world!"), words1.map { it.text })

        val words2 = VozWords.assembleWords(
            tokens = intArrayOf(1, 2, 4, 5),
            frames = intArrayOf(0, 1, 3, 5),
            ends = intArrayOf(1, 2, 4, 7),
            windowStartSeconds = 0.24,
            secondsPerEncoderFrame = 0.08,
            vocabulary = vocab
        )
        val spliced = VozWords.spliceOverlap(words1, words2, overlapStart = 0.20, overlapEnd = 0.50)
        assertEquals("Hello world! from Pixel", spliced.joinToString(" ") { it.text })
    }

    @Test
    fun polishOutputGuardRejectsRefusalsAndLeakedTags() {
        val raw = "let us ship the pixel build today"
        val leaked = "[STYLE: casual] Let's ship the Pixel build today."
        assertEquals(
            "Let's ship the Pixel build today.",
            PolishOutputGuard.sanitizeAndValidate(raw, leaked)
        )

        val refusal = "I'm sorry, as an AI language model I cannot assist with that."
        assertEquals(
            raw,
            PolishOutputGuard.sanitizeAndValidate(raw, refusal)
        )
    }
}
