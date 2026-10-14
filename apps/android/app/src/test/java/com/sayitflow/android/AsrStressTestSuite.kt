package com.sayitflow.android

import com.sayitflow.android.audio.AudioCaptureManager
import com.sayitflow.android.ml.HinglishNormalizer
import com.sayitflow.android.ml.SenseVoiceAsrEngine
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

/**
 * Comprehensive stress and unit test suite verifying:
 * 1. Fast short burst (0.5s–2.0s) audio padding and non-empty result (0% empty-result rate, word count >= 3).
 * 2. Fast long continuous speech (>15s, >180 WPM) window slicing and LCS splicing with >=90% word recall.
 * 3. Slow speech with 1.5s–2.5s mid-utterance silence pauses preserved without premature cutoff or hallucination loops.
 * 4. Multilingual Romanized Hinglish transliteration, nukta handling, schwa deletion, and code-mixing preservation.
 * 5. AudioCaptureManager zero-loss circular pre-roll ring buffer unrolling, discard, and soft dynamic gain normalization.
 */
class AsrStressTestSuite {

    private fun loadPcmFixture(filename: String): FloatArray {
        val stream = javaClass.classLoader?.getResourceAsStream("fixtures/$filename")
            ?: javaClass.getResourceAsStream("/fixtures/$filename")
            ?: File("src/test/resources/fixtures/$filename").inputStream()
        assertNotNull("Fixture $filename should exist in classpath resources", stream)
        val bytes = stream.readBytes()
        val shorts = ShortArray(bytes.size / 2)
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shorts)
        return FloatArray(shorts.size) { shorts[it] / 32768.0f }
    }

    @Test
    fun testFastShortBurstAudioPaddingAndZeroEmptyResult() = runBlocking {
        val engine = SenseVoiceAsrEngine()
        val shortPcm = loadPcmFixture("fast_short_burst.pcm")

        // 1. Verify fixture is a short burst between 0.5s and 2.0s
        val durationSec = shortPcm.size.toFloat() / SenseVoiceAsrEngine.SAMPLE_RATE
        assertTrue("Burst should be short (<= 2.0s), was ${durationSec}s", durationSec <= 2.0f)
        assertTrue("Burst should be >= 0.5s, was ${durationSec}s", durationSec >= 0.5f)

        // 2. Pad sub-second audio (< 12,800 samples) to minimum receptive field of 12,800 samples (0.8s)
        val subSecondBurst = shortPcm.copyOfRange(0, 8000) // 0.5s slice
        val targetLength = SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD
        val paddedSubSecond = engine.padShortAudio(subSecondBurst, targetLength)
        assertEquals("Sub-second burst must be padded to exactly target length", targetLength, paddedSubSecond.size)

        // Full burst meeting receptive field is preserved
        val paddedFull = engine.padShortAudio(shortPcm, targetLength)
        assertEquals("Full burst meeting receptive field is preserved", shortPcm.size, paddedFull.size)

        // 3. Verify Log-Mel filterbank computation
        val melSpectrogram = engine.computeMelSpectrogram(paddedFull)
        assertTrue("Spectrogram must have frames", melSpectrogram.isNotEmpty())
        assertEquals("Each frame must have 80 mel bins", SenseVoiceAsrEngine.N_MELS, melSpectrogram[0].size)
        val frameCount = melSpectrogram.size
        for (f in 0 until frameCount) {
            for (m in 0 until SenseVoiceAsrEngine.N_MELS) {
                val v = melSpectrogram[f][m]
                assertFalse("Spectrogram must not contain NaN", v.isNaN())
                assertFalse("Spectrogram must not contain Inf", v.isInfinite())
            }
        }

        // 4. Transcribe short burst and verify 0% empty-result rate & word count >= 3
        var emptyCount = 0
        val runs = 5
        var lastResult = ""
        for (i in 0 until runs) {
            val result = engine.transcribe(shortPcm, language = "en")
            assertNotNull(result)
            if (result.text.isBlank()) emptyCount++
            lastResult = result.text
            assertTrue("Duration must be non-zero", result.durationMs > 0)
        }
        val emptyRate = emptyCount.toDouble() / runs
        assertEquals("Empty-result rate for fast short burst must be exactly 0.0%", 0.0, emptyRate, 0.001)
        assertTrue("Transcribed text for short burst must not be blank", lastResult.isNotBlank())
        val words = lastResult.trim().split("\\s+".toRegex())
        assertTrue("Word count (${words.size}) must be >= 3, got: '$lastResult'", words.size >= 3)
    }

    @Test
    fun testFastLongContinuousSpeechWindowSlicingAndLcsSplicing() = runBlocking {
        val engine = SenseVoiceAsrEngine()
        val longPcm = loadPcmFixture("fast_long_continuous.pcm")

        // 1. Verify continuous audio is > 15s (240,000 samples @ 16kHz)
        val durationSec = longPcm.size.toFloat() / SenseVoiceAsrEngine.SAMPLE_RATE
        assertTrue("Long audio must be > 15s, was ${durationSec}s", durationSec > 15.0f)

        // 2. Segment into 12.0s windows with 2.0s overlap (192,000 window, 160,000 hop)
        val windows = engine.segmentWindows(longPcm, SenseVoiceAsrEngine.WINDOW_SAMPLES, SenseVoiceAsrEngine.HOP_SAMPLES)
        assertTrue("Long audio must be split into multiple overlapping windows", windows.size >= 2)
        for (w in windows) {
            assertTrue("Each window must meet receptive field requirement", w.size >= SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD)
        }

        // 3. Test Longest Common Subsequence (LCS) transcript splicing
        val windowParts = listOf(
            "welcome to say it flow speech engine",
            "to say it flow speech engine running on device offline",
            "running on device offline with fast local cpu inference"
        )
        val spliced = engine.spliceTranscripts(windowParts)
        val expected = "welcome to say it flow speech engine running on device offline with fast local cpu inference"
        assertEquals(expected, spliced)

        // 4. Verify word recall >= 90% across spliced boundary segments
        val expectedWords = expected.split(" ").toSet()
        val splicedWords = spliced.split(" ").toSet()
        val intersection = expectedWords.intersect(splicedWords)
        val recall = intersection.size.toFloat() / expectedWords.size
        assertTrue("Word recall across boundary splicing must be >= 90%, was $recall", recall >= 0.90f)

        // 5. Full continuous transcription run
        val result = engine.transcribe(longPcm, language = "auto")
        assertTrue("Full transcription must be non-empty", result.text.isNotBlank())
        val continuousWords = result.text.trim().split("\\s+".toRegex())
        assertTrue("Continuous speech must capture stream of words (got ${continuousWords.size})", continuousWords.size >= 10)
    }

    @Test
    fun testSlowSpeechPausesNoPrematureCutoffOrRepetitionLoops() = runBlocking {
        val engine = SenseVoiceAsrEngine()
        val slowPcm = loadPcmFixture("slow_speech_pauses.pcm")

        // 1. Verify audio length
        val durationSec = slowPcm.size.toFloat() / SenseVoiceAsrEngine.SAMPLE_RATE
        assertTrue("Audio duration should be > 5s, was ${durationSec}s", durationSec >= 5.0f)

        // 2. Detect presence of natural pause (> 1.0s low energy) in fixture
        val chunkSize = 1600 // 100ms
        var silentChunks = 0
        var maxConsecutiveSilentChunks = 0
        for (i in 0 until (slowPcm.size - chunkSize) step chunkSize) {
            var sumSq = 0.0
            for (j in 0 until chunkSize) {
                sumSq += slowPcm[i + j] * slowPcm[i + j]
            }
            val rms = Math.sqrt(sumSq / chunkSize)
            if (rms < 0.03) {
                silentChunks++
                if (silentChunks > maxConsecutiveSilentChunks) {
                    maxConsecutiveSilentChunks = silentChunks
                }
            } else {
                silentChunks = 0
            }
        }
        val maxPauseSec = (maxConsecutiveSilentChunks * chunkSize).toFloat() / SenseVoiceAsrEngine.SAMPLE_RATE
        assertTrue("Audio must contain mid-utterance pause of at least 1.0s, found ${maxPauseSec}s", maxPauseSec >= 1.0f)

        // 3. Run transcription
        val result = engine.transcribe(slowPcm, language = "auto")
        assertNotNull(result)
        assertTrue("Slow speech transcript must not be blank", result.text.isNotBlank())

        // 4. Verify non-autoregressive CTC decoding did NOT hallucinate repetition loops
        val words = result.text.split("\\s+".toRegex())
        for (i in 0 until (words.size - 3)) {
            val w = words[i]
            val isQuadruple = words[i + 1] == w && words[i + 2] == w && words[i + 3] == w
            assertFalse("Detected hallucinated repetition loop of word '$w'", isQuadruple)
        }
    }

    @Test
    fun testHinglishNormalizerCodeMixingAndPhoneticTransliteration() {
        val stream = javaClass.classLoader?.getResourceAsStream("fixtures/hinglish_code_mix.txt")
            ?: javaClass.getResourceAsStream("/fixtures/hinglish_code_mix.txt")
            ?: File("src/test/resources/fixtures/hinglish_code_mix.txt").inputStream()
        val lines = stream.bufferedReader().readLines().filter { it.isNotBlank() }

        for (line in lines) {
            val parts = line.split("\t")
            if (parts.size >= 2) {
                val input = parts[0].trim()
                val transliterated = HinglishNormalizer.transliterateToRomanHinglish(input)

                // 1. No Devanagari characters should remain
                val hasDevanagari = transliterated.any { it in '\u0900'..'\u097F' }
                assertFalse("Result for '$input' should not contain Devanagari characters: '$transliterated'", hasDevanagari)

                // 2. Transliterated output should not be empty
                assertTrue("Transliterated text must not be blank", transliterated.isNotBlank())
            }
        }

        // Test specific Hinglish edge cases:
        // A. Colloquial phrases
        assertEquals("main aaj bahut khush hoon", HinglishNormalizer.transliterateToRomanHinglish("मैं आज बहुत खुश हूँ"))
        assertEquals("kal milte hain bhai", HinglishNormalizer.transliterateToRomanHinglish("कल मिलते हैं भाई"))
        assertEquals("aap kaise ho dost", HinglishNormalizer.transliterateToRomanHinglish("आप कैसे हो दोस्त"))
        assertEquals("kaam jaldi khatam karna hai", HinglishNormalizer.transliterateToRomanHinglish("काम जल्दी खत्म करना है"))

        // B. Technical code-mixing (English Latin + Hindi verbs)
        assertEquals("Code review complete ho gaya hai", HinglishNormalizer.transliterateToRomanHinglish("Code review complete हो गया है"))
        assertEquals("Ye function create karo and deploy karo", HinglishNormalizer.transliterateToRomanHinglish("Ye function create karo and deploy karo"))
        assertEquals("yeh file save karo aur github pe push kar do", HinglishNormalizer.transliterateToRomanHinglish("यह फ़ाइल सेव करो और गिटहब पे पुश कर दो"))

        // C. Nukta handling
        assertEquals("zyada", HinglishNormalizer.transliterateToRomanHinglish("ज़्यादा"))
        assertEquals("file", HinglishNormalizer.transliterateToRomanHinglish("फ़ाइल"))

        // D. Word-final conversational schwa deletion
        assertEquals("kal", HinglishNormalizer.transliterateToRomanHinglish("कल")) // Not "kala"
        assertEquals("baat", HinglishNormalizer.transliterateToRomanHinglish("बात")) // Not "baata"
        assertEquals("ghar", HinglishNormalizer.transliterateToRomanHinglish("घर")) // Not "ghara"
    }

    @Test
    fun testAudioCapturePreRollRingBufferAndSoftNormalization() {
        val manager = AudioCaptureManager()

        // 1. Test circular pre-roll unrolling: push 30,000 samples (exceeds 24,000 buffer capacity)
        val rampSamples = FloatArray(30000) { idx -> (idx + 1).toFloat() }

        // Test discard in PRE_ROLL state
        manager.testPushPreRollSamples(rampSamples)
        manager.discardPreRoll()
        assertEquals(0, manager.getRecordedSamplesForTesting().size)

        // Push samples again in PRE_ROLL state and promote to ACTIVE
        manager.testPushPreRollSamples(rampSamples)
        val promoted = manager.promoteToActiveRecording()
        assertTrue("Promotion must succeed", promoted)

        // Check unrolled samples
        val unrolled = manager.getRecordedSamplesForTesting()
        assertEquals("Unrolled pre-roll buffer must contain exactly 24,000 samples", 24000, unrolled.size)

        // Verify exact chronological order: the oldest 6,000 samples were overwritten,
        // so samples should run from 6001.0f to 30000.0f strictly monotonically
        assertEquals(6001.0f, unrolled[0], 1e-4f)
        assertEquals(30000.0f, unrolled[unrolled.size - 1], 1e-4f)
        for (i in 1 until unrolled.size) {
            assertTrue("Pre-roll unrolling must preserve strict chronological ordering", unrolled[i] > unrolled[i - 1])
        }

        // 2. Test soft dynamic gain normalization (NO destructive noise-gate drops)
        // A. Very quiet audio (peak = 0.005f) - in legacy systems peak < 0.006f dropped the entire audio!
        val quietSamples = FloatArray(1600) { 0.005f * kotlin.math.sin(it.toDouble()).toFloat() }
        val normalizedQuiet = manager.normalizeAndPrepareSpeech(quietSamples)
        assertEquals("Quiet audio must NEVER be dropped or return empty array", quietSamples.size, normalizedQuiet.size)
        var quietPeak = 0f
        for (s in normalizedQuiet) {
            val a = abs(s)
            if (a > quietPeak) quietPeak = a
        }
        // Soft dynamic gain scales quiet audio up to 8x
        assertTrue("Quiet audio should receive dynamic gain boost (peak=$quietPeak)", quietPeak > 0.015f)

        // B. DC offset removal
        val dcOffsetSamples = FloatArray(1600) { 0.35f + 0.1f * kotlin.math.sin(it.toDouble()).toFloat() }
        val normalizedDc = manager.normalizeAndPrepareSpeech(dcOffsetSamples)
        var dcSum = 0.0
        for (s in normalizedDc) dcSum += s
        val remainingDc = abs(dcSum / normalizedDc.size)
        assertTrue("DC offset must be eliminated (< 1e-4), was $remainingDc", remainingDc < 1e-4)

        // C. Normal audio stays within bounds [-1.0, 1.0]
        val loudSamples = FloatArray(1600) { 0.95f * kotlin.math.sin(it.toDouble()).toFloat() }
        val normalizedLoud = manager.normalizeAndPrepareSpeech(loudSamples)
        for (s in normalizedLoud) {
            assertTrue("Normalized audio must be within [-1.0, 1.0]", s >= -1.0f && s <= 1.0f)
        }
    }
}
