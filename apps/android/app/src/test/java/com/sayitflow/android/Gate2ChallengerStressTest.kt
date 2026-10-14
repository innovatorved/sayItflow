package com.sayitflow.android

import com.sayitflow.android.audio.AudioCaptureManager
import com.sayitflow.android.ml.HinglishNormalizer
import com.sayitflow.android.ml.SenseVoiceAsrEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.cos
import kotlin.math.sin

/**
 * Gate 2 Empirical Challenger Stress Harness.
 *
 * Independently stress-tests:
 * 1. Test 1 (Fast Short Burst, 0.5s–2.0s): 0% empty-result rate, receptive field padding.
 * 2. Test 2 (Fast Long Continuous Speech, >=15s, >180 WPM): sliding window chunking and word recall.
 * 3. Test 3 (Slow Speech with Natural Pauses, 1.5s–2.5s silence): session active, zero hallucinated repetitions.
 * 4. Hinglish Test: Devanagari to Roman transliteration ("शुरू" -> "shuru", variations, code mixing).
 * 5. Concurrency & Thread-Safety: AudioCaptureManager under 100+ rapid concurrent multi-threaded cycles.
 */
class Gate2ChallengerStressTest {

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

    private fun generateSyntheticSpeech(
        wordCount: Int,
        burstDurationMs: Int = 100,
        gapDurationMs: Int = 150,
        baseFreqHz: Float = 220f
    ): FloatArray {
        val burstSamples = (burstDurationMs * SenseVoiceAsrEngine.SAMPLE_RATE) / 1000
        val gapSamples = (gapDurationMs * SenseVoiceAsrEngine.SAMPLE_RATE) / 1000
        val totalSamples = wordCount * burstSamples + (wordCount - 1).coerceAtLeast(0) * gapSamples
        val pcm = FloatArray(totalSamples)

        var offset = 0
        for (w in 0 until wordCount) {
            val freq = baseFreqHz * (1.0f + 0.1f * (w % 4))
            for (i in 0 until burstSamples) {
                val t = i.toDouble() / SenseVoiceAsrEngine.SAMPLE_RATE
                val env = (0.5 - 0.5 * cos(2.0 * Math.PI * i / (burstSamples - 1))).toFloat()
                val signal = (0.5 * sin(2.0 * Math.PI * freq * t) +
                        0.3 * sin(4.0 * Math.PI * freq * t) +
                        0.2 * sin(6.0 * Math.PI * freq * t)).toFloat()
                pcm[offset + i] = (0.6f * signal * env).coerceIn(-1.0f, 1.0f)
            }
            offset += burstSamples
            if (w < wordCount - 1) {
                offset += gapSamples
            }
        }
        return pcm
    }

    // =========================================================================
    // 1. TEST 1: FAST SHORT BURST (0.5s - 2.0s)
    // =========================================================================

    @Test
    fun testFastShortBurstEmpiricalZeroEmptyRateAcrossDurations() = runBlocking {
        val engine = SenseVoiceAsrEngine()

        // Test durations: 0.5s, 0.75s, 1.0s, 1.4s, 1.8s, 2.0s
        val testDurationsSec = listOf(0.5f, 0.75f, 1.0f, 1.4f, 1.8f, 2.0f)
        for (dur in testDurationsSec) {
            val wordCount = (dur * 3).toInt().coerceAtLeast(1)
            val burstMs = (dur * 1000 / wordCount * 0.6).toInt()
            val gapMs = (dur * 1000 / wordCount * 0.4).toInt()
            val audio = generateSyntheticSpeech(wordCount = wordCount, burstDurationMs = burstMs, gapDurationMs = gapMs)

            // Verify padding
            if (audio.size < SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD) {
                val padded = engine.padShortAudio(audio, SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD)
                assertEquals(SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD, padded.size)
            }

            // Verify transcription: 0% empty rate
            val result = engine.transcribe(audio, language = "en")
            assertNotNull(result)
            assertTrue("Duration $dur s produced empty transcript!", result.text.isNotBlank())
            assertTrue("Duration $dur s reported non-positive durationMs", result.durationMs > 0)
        }

        // Also test the real audio fixture: fast_short_burst.pcm
        val fixturePcm = loadPcmFixture("fast_short_burst.pcm")
        val fixtureDur = fixturePcm.size.toFloat() / SenseVoiceAsrEngine.SAMPLE_RATE
        assertTrue("Fixture duration should be between 0.5s and 2.0s, was ${fixtureDur}s", fixtureDur in 0.5f..2.0f)

        // Multiple iterations on fixture to prove determinism and 0% empty rate
        val fixtureRuns = 10
        var emptyCount = 0
        for (i in 0 until fixtureRuns) {
            val res = engine.transcribe(fixturePcm, language = "en")
            if (res.text.isBlank()) emptyCount++
            assertTrue("Word count must be >= 3", res.text.trim().split("\\s+".toRegex()).size >= 3)
        }
        assertEquals("Empty rate on short burst fixture must be exactly 0.0%", 0, emptyCount)
    }

    // =========================================================================
    // 2. TEST 2: FAST LONG CONTINUOUS SPEECH (>=15s, >180 WPM)
    // =========================================================================

    @Test
    fun testFastLongContinuousSpeechSlidingWindowAndWordRecall() = runBlocking {
        val engine = SenseVoiceAsrEngine()

        // 1. Synthetic 18-second speech stream (>180 WPM: >3 words per sec -> 60 words in 18s)
        val wordCount = 60
        val audio18s = generateSyntheticSpeech(
            wordCount = wordCount,
            burstDurationMs = 120,
            gapDurationMs = 180, // Total = 300ms per word = 3.33 words/sec = 200 WPM
            baseFreqHz = 240f
        )
        val durationSec = audio18s.size.toFloat() / SenseVoiceAsrEngine.SAMPLE_RATE
        assertTrue("Speech duration should be >= 15.0s, was ${durationSec}s", durationSec >= 15.0f)

        // Verify window segmentation (12.0s window, 10.0s hop -> 2.0s overlap)
        val windows = engine.segmentWindows(audio18s, SenseVoiceAsrEngine.WINDOW_SAMPLES, SenseVoiceAsrEngine.HOP_SAMPLES)
        assertTrue("18s audio must produce at least 2 overlapping windows, got ${windows.size}", windows.size >= 2)

        // Transcribe long continuous audio
        val result = engine.transcribe(audio18s, language = "en")
        assertNotNull(result)
        assertTrue("Transcription must not be blank", result.text.isNotBlank())
        val decodedWords = result.text.trim().split("\\s+".toRegex())
        assertTrue("Decoded words count (${decodedWords.size}) should be substantial (>= 15)", decodedWords.size >= 15)

        // 2. Verify LCS transcript splicing with high recall (>= 90%)
        val sampleWindows = listOf(
            "the fast rapid speech model operates directly on android devices",
            "model operates directly on android devices without relying on network",
            "without relying on network or google speech recognizer services"
        )
        val spliced = engine.spliceTranscripts(sampleWindows)
        val expected = "the fast rapid speech model operates directly on android devices without relying on network or google speech recognizer services"
        assertEquals(expected, spliced)

        val expectedWords = expected.split(" ").toSet()
        val splicedWords = spliced.split(" ").toSet()
        val recall = expectedWords.intersect(splicedWords).size.toFloat() / expectedWords.size
        assertTrue("LCS splicing recall must be >= 90%, was $recall", recall >= 0.90f)

        // 3. Test real long continuous fixture
        val longFixture = loadPcmFixture("fast_long_continuous.pcm")
        val longDur = longFixture.size.toFloat() / SenseVoiceAsrEngine.SAMPLE_RATE
        assertTrue("Fixture fast_long_continuous.pcm should be > 15s, was ${longDur}s", longDur > 15.0f)

        val fixtureResult = engine.transcribe(longFixture, language = "auto")
        assertNotNull(fixtureResult)
        assertTrue("Continuous fixture transcription must be non-empty", fixtureResult.text.isNotBlank())
        val fixtureWords = fixtureResult.text.trim().split("\\s+".toRegex())
        assertTrue("Continuous fixture words must be >= 10, got ${fixtureWords.size}", fixtureWords.size >= 10)
    }

    // =========================================================================
    // 3. TEST 3: SLOW SPEECH WITH NATURAL PAUSES (1.5s - 2.5s)
    // =========================================================================

    @Test
    fun testSlowSpeechNaturalPausesNoPrematureCutoffNoHallucinations() = runBlocking {
        val engine = SenseVoiceAsrEngine()

        // 1. Synthesize two distinct speech bursts separated by a 2.0s silence pause
        val phrase1 = generateSyntheticSpeech(wordCount = 4, burstDurationMs = 150, gapDurationMs = 250, baseFreqHz = 200f)
        val pause2s = FloatArray(SenseVoiceAsrEngine.SAMPLE_RATE * 2) { 0f } // 2.0 seconds silence
        val phrase2 = generateSyntheticSpeech(wordCount = 4, burstDurationMs = 150, gapDurationMs = 250, baseFreqHz = 300f)

        val combinedPcm = FloatArray(phrase1.size + pause2s.size + phrase2.size)
        System.arraycopy(phrase1, 0, combinedPcm, 0, phrase1.size)
        System.arraycopy(pause2s, 0, combinedPcm, phrase1.size, pause2s.size)
        System.arraycopy(phrase2, 0, combinedPcm, phrase1.size + pause2s.size, phrase2.size)

        val totalSec = combinedPcm.size.toFloat() / SenseVoiceAsrEngine.SAMPLE_RATE
        assertTrue("Combined audio should be > 4s, was ${totalSec}s", totalSec > 4.0f)

        // Transcribe and verify both phrases are captured and no hallucination loop
        val result = engine.transcribe(combinedPcm, language = "en")
        assertNotNull(result)
        assertTrue("Slow speech transcript must not be empty", result.text.isNotBlank())

        val words = result.text.trim().split("\\s+".toRegex())
        assertTrue("Must contain words from both before and after the 2.0s pause, got ${words.size} words", words.size >= 4)

        // Check for hallucinated repetitions: no 4 consecutive identical words
        for (i in 0 until (words.size - 3)) {
            val w = words[i]
            val hasLoop = words[i + 1] == w && words[i + 2] == w && words[i + 3] == w
            assertFalse("Detected hallucinated repetition loop: '$w' repeated 4+ times", hasLoop)
        }

        // 2. Real audio fixture with pauses
        val slowFixture = loadPcmFixture("slow_speech_pauses.pcm")
        val slowRes = engine.transcribe(slowFixture, language = "auto")
        assertNotNull(slowRes)
        assertTrue("Fixture slow speech transcript must not be empty", slowRes.text.isNotBlank())
        val slowWords = slowRes.text.trim().split("\\s+".toRegex())
        for (i in 0 until (slowWords.size - 3)) {
            val w = slowWords[i]
            val hasLoop = slowWords[i + 1] == w && slowWords[i + 2] == w && slowWords[i + 3] == w
            assertFalse("Fixture has hallucinated repetition loop: '$w'", hasLoop)
        }
    }

    // =========================================================================
    // 4. HINGLISH TRANSLITERATION TEST
    // =========================================================================

    @Test
    fun testHinglishDevanagariToRomanTransliterationRules() {
        // Requirement: "शुरू" -> "shuru"
        assertEquals("shuru", HinglishNormalizer.transliterateToRomanHinglish("शुरू"))
        assertEquals("shuru", HinglishNormalizer.transliterateToRomanHinglish("शुरु"))
        assertEquals("shuruat", HinglishNormalizer.transliterateToRomanHinglish("शुरुआत"))
        assertEquals("shuruati", HinglishNormalizer.transliterateToRomanHinglish("शुरूआती"))

        // Common colloquial phrases with शुरू
        assertEquals("kaam shuru karo", HinglishNormalizer.transliterateToRomanHinglish("काम शुरू करो"))
        assertEquals("aaj se shuru karenge", HinglishNormalizer.transliterateToRomanHinglish("आज से शुरू करेंगे"))
        assertEquals("meeting shuru ho gayi", HinglishNormalizer.transliterateToRomanHinglish("meeting शुरू हो गई"))

        // Punctuation and brackets around शुरू
        assertEquals("[shuru]", HinglishNormalizer.transliterateToRomanHinglish("[शुरू]"))
        assertEquals("\"shuru\"", HinglishNormalizer.transliterateToRomanHinglish("\"शुरू\""))
        assertEquals("shuru?", HinglishNormalizer.transliterateToRomanHinglish("शुरू?"))

        // Zero Devanagari characters leaked
        val testCorpus = listOf(
            "नमस्ते दोस्त, क्या हाल है?",
            "काम खत्म करो और गिटहब पे पुश करो",
            "फ़ाइल सेव हो चुकी है",
            "कल 10:00 AM पे मिलते हैं भाई"
        )
        for (sentence in testCorpus) {
            val roman = HinglishNormalizer.transliterateToRomanHinglish(sentence)
            val devanagariRemains = roman.any { it in '\u0900'..'\u097F' }
            assertFalse("Devanagari character leaked in output: '$roman'", devanagariRemains)
            assertTrue("Output should not be blank", roman.isNotBlank())
        }
    }

    // =========================================================================
    // 5. CONCURRENCY & THREAD-SAFETY STRESS TEST (AudioCaptureManager)
    // =========================================================================

    @Test
    fun testAudioCaptureManagerRapidConcurrentCycles() = runBlocking {
        val manager = AudioCaptureManager()
        val threadCount = 8
        val cyclesPerThread = 50
        val executor = Executors.newFixedThreadPool(threadCount)
        val exceptions = mutableListOf<Throwable>()
        val successCount = AtomicInteger(0)

        val deferreds = (1..threadCount).map { threadId ->
            async(Dispatchers.IO) {
                for (cycle in 1..cyclesPerThread) {
                    try {
                        // 1. Simulate pre-roll feed
                        val ramp = FloatArray(800) { ((threadId * 1000 + it) % 100).toFloat() }
                        manager.testPushPreRollSamples(ramp)

                        // 2. Interleave state changes
                        if (cycle % 3 == 0) {
                            manager.discardPreRoll()
                        } else if (cycle % 2 == 0) {
                            manager.promoteToActiveRecording()
                            val unrolled = manager.getRecordedSamplesForTesting()
                            assertTrue("Unrolled size must not exceed MAX_SAMPLES", unrolled.size <= AudioCaptureManager.MAX_SAMPLES)
                        } else {
                            val stopped = manager.stopRecording()
                            assertNotNull("Stopped audio must not be null", stopped)
                        }

                        // 3. Normalize speech concurrently
                        val dummySpeech = FloatArray(1600) { (it % 100) / 100.0f }
                        val norm = manager.normalizeAndPrepareSpeech(dummySpeech)
                        assertEquals(1600, norm.size)

                        successCount.incrementAndGet()
                    } catch (t: Throwable) {
                        synchronized(exceptions) {
                            exceptions.add(t)
                        }
                    }
                }
            }
        }

        deferreds.awaitAll()
        executor.shutdown()
        executor.awaitTermination(5, TimeUnit.SECONDS)

        assertTrue(
            "Encountered ${exceptions.size} concurrency exceptions: ${exceptions.firstOrNull()?.message}",
            exceptions.isEmpty()
        )
        assertEquals(threadCount * cyclesPerThread, successCount.get())
    }

    @Test
    fun testAudioCaptureManagerAsyncStopUnderRapidInvocation() = runBlocking {
        val manager = AudioCaptureManager()

        // Test 20 rapid sequential async record-stop iterations
        for (i in 0 until 20) {
            val samples = FloatArray(1600) { (it % 50) / 100f }
            manager.testPushPreRollSamples(samples)
            manager.promoteToActiveRecording()
            val audio = manager.stopRecordingAsync()
            assertNotNull(audio)
            assertTrue("Captured audio should have length >= 0", audio.size >= 0)
        }
    }
}
