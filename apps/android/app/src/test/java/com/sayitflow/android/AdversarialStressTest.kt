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
import kotlin.math.abs
import kotlin.math.sin

/**
 * Adversarial stress harness verifying edge conditions, boundary limits,
 * and failure modes for SenseVoiceAsrEngine, AudioCaptureManager, and HinglishNormalizer.
 */
class AdversarialStressTest {

    private fun generateSineSpeech(durationSec: Float, freqHz: Float = 220f, amplitude: Float = 0.5f): FloatArray {
        val totalSamples = (durationSec * SenseVoiceAsrEngine.SAMPLE_RATE).toInt()
        return FloatArray(totalSamples) { i ->
            val t = i.toDouble() / SenseVoiceAsrEngine.SAMPLE_RATE
            (amplitude * sin(2.0 * Math.PI * freqHz * t)).toFloat()
        }
    }

    private fun generateSpeechWithBursts(
        wordCount: Int,
        burstDurationMs: Int = 80,
        gapDurationMs: Int = 200,
        freqHz: Float = 240f,
        amplitude: Float = 0.6f
    ): FloatArray {
        val samplesPerBurst = (burstDurationMs * SenseVoiceAsrEngine.SAMPLE_RATE) / 1000
        val samplesPerGap = (gapDurationMs * SenseVoiceAsrEngine.SAMPLE_RATE) / 1000
        val totalSamples = wordCount * samplesPerBurst + (wordCount - 1) * samplesPerGap
        val audio = FloatArray(totalSamples)

        var offset = 0
        for (w in 0 until wordCount) {
            for (i in 0 until samplesPerBurst) {
                val t = i.toDouble() / SenseVoiceAsrEngine.SAMPLE_RATE
                val env = (0.5 - 0.5 * kotlin.math.cos(2.0 * Math.PI * i / (samplesPerBurst - 1))).toFloat()
                val s = (0.45 * sin(2.0 * Math.PI * freqHz * t) +
                        0.30 * sin(4.0 * Math.PI * freqHz * t) +
                        0.20 * sin(8.0 * Math.PI * freqHz * t)).toFloat()
                audio[offset + i] = (amplitude * s * env)
            }
            offset += samplesPerBurst
            if (w < wordCount - 1) {
                // Gap remains 0.0f
                offset += samplesPerGap
            }
        }
        return audio
    }

    @Test
    fun testDiagnosticEnergyAndBursts() = runBlocking {
        val engine = SenseVoiceAsrEngine()
        val audio = generateSpeechWithBursts(wordCount = 3, burstDurationMs = 80, gapDurationMs = 200)
        val mel = engine.computeMelSpectrogram(audio)
        val frameEnergies = FloatArray(mel.size) { f ->
            var sum = 0f
            for (m in mel[f]) sum += m
            sum / mel[f].size
        }
        var maxE = -100f
        var minE = 100f
        for (e in frameEnergies) {
            if (e > maxE) maxE = e
            if (e < minE) minE = e
        }
        val thresh = minE + (maxE - minE) * 0.28f
        println("DIAGNOSTIC: frames=${mel.size}, minE=$minE, maxE=$maxE, thresh=$thresh")
        var activeFrames = 0
        for (e in frameEnergies) {
            if (e >= thresh) activeFrames++
        }
        println("DIAGNOSTIC: activeFrames=$activeFrames out of ${mel.size}")
        val stream = javaClass.classLoader?.getResourceAsStream("fixtures/fast_short_burst.pcm")
        val bytes = stream!!.readBytes()
        val shorts = ShortArray(bytes.size / 2)
        java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shorts)
        val fixturePcm = FloatArray(shorts.size) { shorts[it] / 32768.0f }
        val fixtureMel = engine.computeMelSpectrogram(fixturePcm)
        val fixtureEnergies = FloatArray(fixtureMel.size) { f ->
            var sum = 0f
            for (m in fixtureMel[f]) sum += m
            sum / fixtureMel[f].size
        }
        var fMaxE = -100f
        var fMinE = 100f
        for (e in fixtureEnergies) {
            if (e > fMaxE) fMaxE = e
            if (e < fMinE) fMinE = e
        }
        val fThresh = fMinE + (fMaxE - fMinE) * 0.28f
        println("FIXTURE DIAGNOSTIC: frames=${fixtureMel.size}, minE=$fMinE, maxE=$fMaxE, thresh=$fThresh")
        val fixtureTranscript = engine.runOfflineAcousticDecoder(fixturePcm, "en")
        println("FIXTURE DIAGNOSTIC: fixtureTranscript='$fixtureTranscript'")
        // Check bursts in synthetic vs fixture
        // Print burst details for fixture
        val fMel = fixtureMel
        val fEnergies = fixtureEnergies
        val fThreshold = fThresh
        val fBursts = mutableListOf<SenseVoiceAsrEngine.AcousticBurst>()
        var fInBurst = false
        var fStart = 0
        var fSum = 0f
        for (f in fMel.indices) {
            if (fEnergies[f] >= fThreshold) {
                if (!fInBurst) { fInBurst = true; fStart = f; fSum = 0f }
                fSum += fEnergies[f]
            } else if (fInBurst) {
                fInBurst = false
                val len = f - fStart
                if (len >= 3) fBursts.add(SenseVoiceAsrEngine.AcousticBurst(fStart, f, len, fSum/len, 0f))
            }
        }
        println("FIXTURE BURSTS: count=${fBursts.size}, bursts=${fBursts.map { "(${it.startFrame}..${it.endFrame}, len=${it.durationFrames})" }}")

        // Print burst details for synthetic
        val sBursts = mutableListOf<SenseVoiceAsrEngine.AcousticBurst>()
        var sInBurst = false
        var sStart = 0
        var sSum = 0f
        for (f in mel.indices) {
            if (frameEnergies[f] >= thresh) {
                if (!sInBurst) { sInBurst = true; sStart = f; sSum = 0f }
                sSum += frameEnergies[f]
            } else if (sInBurst) {
                sInBurst = false
                val len = f - sStart
                if (len >= 3) sBursts.add(SenseVoiceAsrEngine.AcousticBurst(sStart, f, len, sSum/len, 0f))
            }
        }
        println("SYNTHETIC BURSTS: count=${sBursts.size}, bursts=${sBursts.map { "(${it.startFrame}..${it.endFrame}, len=${it.durationFrames})" }}")
    }

    @Test
    fun testUltraShortBurstsUnder500ms() = runBlocking {
        val engine = SenseVoiceAsrEngine()

        // 0.3s burst (4,800 samples)
        val audio300ms = generateSpeechWithBursts(wordCount = 1, burstDurationMs = 80, gapDurationMs = 0)
        val padded300ms = engine.padShortAudio(audio300ms, SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD)
        assertEquals(SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD, padded300ms.size)

        val result300ms = engine.transcribe(audio300ms)
        assertNotNull(result300ms)
        assertTrue(result300ms.durationMs > 0)

        // 0.1s burst (1,600 samples)
        val audio100ms = generateSineSpeech(0.1f)
        val padded100ms = engine.padShortAudio(audio100ms, SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD)
        assertEquals(SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD, padded100ms.size)

        // Single sample (1/16000s)
        val singleSample = floatArrayOf(0.42f)
        val paddedSingle = engine.padShortAudio(singleSample, SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD)
        assertEquals(SenseVoiceAsrEngine.MIN_SAMPLES_RECEPTIVE_FIELD, paddedSingle.size)

        val resultSingle = engine.transcribe(singleSample)
        assertNotNull(resultSingle)

        // Empty array: should safely return empty result without crashing
        val emptyResult = engine.transcribe(FloatArray(0))
        assertEquals("", emptyResult.text)
        assertEquals(0L, emptyResult.durationMs)
    }

    // ==========================================
    // 2. CORNER CASE: LONG CONTINUOUS SPEECH (30s & 60s)
    // ==========================================

    @Test
    fun testLongContinuousAudioSlicingAndMemoryStability() = runBlocking {
        val engine = SenseVoiceAsrEngine()

        // 30 seconds continuous speech (>180 WPM: ~90 words)
        val audio30s = generateSpeechWithBursts(wordCount = 90, burstDurationMs = 80, gapDurationMs = 220)
        val durationSec = audio30s.size.toFloat() / SenseVoiceAsrEngine.SAMPLE_RATE
        assertTrue("Audio should be >= 25s, was $durationSec", durationSec >= 25.0f)

        // Verify window segmentation
        val windows = engine.segmentWindows(audio30s, SenseVoiceAsrEngine.WINDOW_SAMPLES, SenseVoiceAsrEngine.HOP_SAMPLES)
        assertTrue("30s audio should generate at least 3 windows", windows.size >= 3)

        // Inspect window 0 decoding
        val win0Text = engine.runOfflineAcousticDecoder(windows[0], "auto")
        println("DEBUG win0Text: '$win0Text'")

        // Verify full transcription runs without out-of-memory or frame-index overflow
        val result30s = engine.transcribe(audio30s)
        println("DEBUG result30s: '${result30s.text}', duration=${result30s.durationMs}")
        assertNotNull(result30s)

        // Test extreme LCS splicing scenarios:
        // Scenario A: Completely identical adjacent segments (e.g. repeat window)
        val dupSegments = listOf(
            "hello world test",
            "hello world test"
        )
        val splicedDup = engine.spliceTranscripts(dupSegments)
        assertEquals("hello world test", splicedDup)

        // Scenario B: Zero overlap between windows
        val disjointSegments = listOf(
            "first distinct phrase",
            "second completely different text"
        )
        val splicedDisjoint = engine.spliceTranscripts(disjointSegments)
        assertEquals("first distinct phrase second completely different text", splicedDisjoint)

        // Scenario C: 5 sequential overlapping windows
        val chainSegments = listOf(
            "alpha beta gamma",
            "beta gamma delta",
            "gamma delta epsilon",
            "delta epsilon zeta",
            "epsilon zeta eta"
        )
        val splicedChain = engine.spliceTranscripts(chainSegments)
        assertEquals("alpha beta gamma delta epsilon zeta eta", splicedChain)
    }

    @Test
    fun testMultiWindowConcatenatedRealAudioTranscription() = runBlocking {
        val engine = SenseVoiceAsrEngine()
        val stream = javaClass.classLoader?.getResourceAsStream("fixtures/fast_short_burst.pcm")
        assertNotNull("Fixture fast_short_burst.pcm must exist", stream)
        val bytes = stream!!.readBytes()
        val shorts = ShortArray(bytes.size / 2)
        java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shorts)
        val unitSpeech = FloatArray(shorts.size) { shorts[it] / 32768.0f }

        // Build a 16-second audio stream (~256,000 samples) by repeating unitSpeech (15,680 samples)
        // with 1.0s (16,000 samples) silence intervals.
        // Total repeats: 8 -> triggers multiple 10s windows with 2s overlap.
        val silence1s = FloatArray(16000) { 0f }
        val longPcmList = mutableListOf<Float>()
        for (i in 0 until 8) {
            for (s in unitSpeech) longPcmList.add(s)
            if (i < 7) {
                for (s in silence1s) longPcmList.add(s)
            }
        }
        val longPcm = longPcmList.toFloatArray()
        assertTrue("PCM length should exceed WINDOW_SAMPLES (160000)", longPcm.size > SenseVoiceAsrEngine.WINDOW_SAMPLES)

        val result = engine.transcribe(longPcm)
        assertNotNull(result)
        println("CONCATENATED RESULT: '${result.text}', duration=${result.durationMs}ms")
        assertTrue("Transcription should detect stream of words from concatenated fixture", result.text.isNotBlank() && result.text.split("\\s+".toRegex()).size >= 10)
    }

    // ==========================================
    // 3. CORNER CASE: EXTREME SILENCE & PAUSES
    // ==========================================

    @Test
    fun testExtremeSilenceAndProlongedMidUtterancePauses() = runBlocking {
        val engine = SenseVoiceAsrEngine()

        // Pure digital silence (all 0f) for 3 seconds
        val pureSilence = FloatArray(48000) { 0f }
        val mel = engine.computeMelSpectrogram(pureSilence)
        assertTrue("Mel spectrogram should compute without crashing on silence", mel.isNotEmpty())
        for (frame in mel) {
            for (bin in frame) {
                assertFalse("Mel energy should not be NaN", bin.isNaN())
                assertFalse("Mel energy should not be Inf", bin.isInfinite())
            }
        }

        // Sub-noise floor audio (amplitude 1e-7f)
        val nearSilence = FloatArray(32000) { 1e-7f }
        val nearSilenceMel = engine.computeMelSpectrogram(nearSilence)
        assertTrue(nearSilenceMel.isNotEmpty())

        // Extended 4.0s pause between two active speech phrases
        // Phrase 1 (3 words) + 4.0s silence + Phrase 2 (3 words)
        val phrase1 = generateSpeechWithBursts(wordCount = 3, burstDurationMs = 80, gapDurationMs = 200)
        val silence4s = FloatArray(SenseVoiceAsrEngine.SAMPLE_RATE * 4) { 0f }
        val phrase2 = generateSpeechWithBursts(wordCount = 3, burstDurationMs = 80, gapDurationMs = 200)

        val combinedWithLongPause = FloatArray(phrase1.size + silence4s.size + phrase2.size)
        System.arraycopy(phrase1, 0, combinedWithLongPause, 0, phrase1.size)
        System.arraycopy(silence4s, 0, combinedWithLongPause, phrase1.size, silence4s.size)
        System.arraycopy(phrase2, 0, combinedWithLongPause, phrase1.size + silence4s.size, phrase2.size)

        val resultPause = engine.transcribe(combinedWithLongPause)
        println("DEBUG resultPause: '${resultPause.text}', duration=${resultPause.durationMs}")
        assertNotNull(resultPause)
    }

    // ==========================================
    // 4. CORNER CASE: AUDIOCAPTUREMANAGER BUFFER STRESS
    // ==========================================

    @Test
    fun testAudioCaptureManagerStressAndStateTransitions() {
        val manager = AudioCaptureManager()

        // 1. Extreme Pre-Roll Overflow: Push 120,000 samples (5x buffer capacity of 24,000)
        val heavyRamp = FloatArray(120000) { idx -> (idx + 1).toFloat() }
        manager.testPushPreRollSamples(heavyRamp)
        val promoted = manager.promoteToActiveRecording()
        assertTrue(promoted)

        val unrolled = manager.getRecordedSamplesForTesting()
        assertEquals(24000, unrolled.size)
        // Chronological monotonic order preserved after 5 full ring buffer wraps
        assertEquals(96001.0f, unrolled[0], 1e-3f)
        assertEquals(120000.0f, unrolled[unrolled.size - 1], 1e-3f)
        for (i in 1 until unrolled.size) {
            assertTrue("Strict monotonic order failed at index $i", unrolled[i] > unrolled[i - 1])
        }

        // 2. Normalize extreme DC offset (+1.8f)
        val severeDcSamples = FloatArray(3200) { 1.8f + 0.05f * sin(it.toDouble()).toFloat() }
        val normalizedDc = manager.normalizeAndPrepareSpeech(severeDcSamples)
        var dcSum = 0.0
        for (s in normalizedDc) dcSum += s
        val meanDc = abs(dcSum / normalizedDc.size)
        assertTrue("Severe DC bias was not removed: mean=$meanDc", meanDc < 1e-3)

        // 3. Dynamic gain clamping on extreme loud bursts (peak = 5.0f clipping)
        val severeClipping = FloatArray(3200) { 5.0f * sin(it.toDouble()).toFloat() }
        val normalizedClipped = manager.normalizeAndPrepareSpeech(severeClipping)
        for (s in normalizedClipped) {
            assertTrue("Sample exceeded [-1.0, 1.0]: $s", s >= -1.0f && s <= 1.0f)
        }
    }

    // ==========================================
    // 5. CORNER CASE: HINGLISH NORMALIZER ADVERSARIAL CASES
    // ==========================================

    @Test
    fun testHinglishNormalizerAdversarialEdgeCases() {
        // 1. Empty and pure whitespace
        assertEquals("", HinglishNormalizer.transliterateToRomanHinglish(""))
        assertEquals("   ", HinglishNormalizer.transliterateToRomanHinglish("   "))

        // 2. Pure English (should remain intact without corruption)
        val pureEnglish = "The quick brown fox jumps over the lazy dog."
        assertEquals(pureEnglish, HinglishNormalizer.transliterateToRomanHinglish(pureEnglish))

        // 3. Complex Devanagari ligatures / conjuncts:
        // क्ष (ksha), त्र (tra), ज्ञ (gya / jna), श्र (shra)
        val conjunct1 = HinglishNormalizer.transliterateToRomanHinglish("क्षेत्र")
        assertFalse("Devanagari remains in $conjunct1", conjunct1.any { it in '\u0900'..'\u097F' })

        val conjunct2 = HinglishNormalizer.transliterateToRomanHinglish("ज्ञान")
        assertFalse("Devanagari remains in $conjunct2", conjunct2.any { it in '\u0900'..'\u097F' })

        val conjunct3 = HinglishNormalizer.transliterateToRomanHinglish("श्रीमान")
        assertFalse("Devanagari remains in $conjunct3", conjunct3.any { it in '\u0900'..'\u097F' })

        // 4. Emojis interleaved with Hindi
        val emojiMixed = "नमस्ते 🙏 भाई, meeting 10:00 AM pe hai! 🚀"
        val transliteratedEmoji = HinglishNormalizer.transliterateToRomanHinglish(emojiMixed)
        assertFalse("Devanagari leaked in emoji string", transliteratedEmoji.any { it in '\u0900'..'\u097F' })
        assertTrue("Emoji should be preserved", transliteratedEmoji.contains("🙏") && transliteratedEmoji.contains("🚀"))
        assertTrue("English and time preserved", transliteratedEmoji.contains("meeting 10:00 AM"))

        // 5. Punctuation brackets and quotes around Hindi words
        val bracketed = "(काम) [शुरू] {करो}!"
        val transliteratedBracketed = HinglishNormalizer.transliterateToRomanHinglish(bracketed)
        println("DEBUG transliteratedBracketed: '$transliteratedBracketed'")
        assertTrue(transliteratedBracketed == "(kaam) [shuru] {karo}!" || transliteratedBracketed == "(kaam) [shuroo] {karo}!")

        // 6. Devanagari numerals
        val devNumerals = "१२३"
        val transliteratedNumerals = HinglishNormalizer.transliterateToRomanHinglish(devNumerals)
        assertTrue(transliteratedNumerals.isNotBlank())
    }
}
