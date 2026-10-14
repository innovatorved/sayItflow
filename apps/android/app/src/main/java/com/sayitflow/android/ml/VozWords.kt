package com.sayitflow.android.ml

import org.json.JSONArray
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Word assembly, overlap splicing, and IEEE-754 float16 embedding table utilities
 * ported directly from `Desert-Ant-Labs/desert-ant-core/Sources/Voz/Words.swift` & `Assets.swift`.
 */
object VozWords {

    private const val WORD_BOUNDARY = '\u2581' // ▁

    data class TimedWord(
        val text: String,
        val start: Double,
        val end: Double,
        val beganNewWord: Boolean
    )

    /**
     * Parses `vocab.json` (array of 8192 SentencePiece subword tokens).
     */
    fun parseVocabulary(jsonString: String): List<String> {
        val arr = JSONArray(jsonString)
        return List(arr.length()) { i -> arr.getString(i) }
    }

    /**
     * Widens raw `embedding.f16` (`[vocabSize + 1, predHidden]` little-endian IEEE-754 float16)
     * into a contiguous FloatArray once on load.
     */
    fun decodeFloat16Embedding(bytes: ByteArray, expectedElements: Int): FloatArray {
        require(bytes.size == expectedElements * 2) {
            "embedding.f16 has ${bytes.size} bytes, expected ${expectedElements * 2}"
        }
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val out = FloatArray(expectedElements)
        for (i in 0 until expectedElements) {
            out[i] = float16ToFloat32(buf.get(i).toInt() and 0xFFFF)
        }
        return out
    }

    /**
     * IEEE-754 binary16 (half precision) to float32 conversion.
     */
    fun float16ToFloat32(halfBits: Int): Float {
        val sign = (halfBits and 0x8000) shl 16
        val exp = (halfBits ushr 10) and 0x1F
        val mant = halfBits and 0x03FF
        val bits = when (exp) {
            0 -> {
                if (mant == 0) {
                    sign
                } else {
                    var m = mant
                    var e = -14
                    while ((m and 0x0400) == 0) {
                        m = m shl 1
                        e -= 1
                    }
                    m = m and 0x03FF
                    sign or ((e + 127) shl 23) or (m shl 13)
                }
            }
            31 -> sign or 0x7F800000 or (mant shl 13)
            else -> sign or ((exp - 15 + 127) shl 23) or (mant shl 13)
        }
        return Float.fromBits(bits)
    }

    /**
     * Group subword tokens and frame indices into timed words.
     * Each encoder frame spans `hopLength * 8 / sampleRate` seconds (80 ms at 16 kHz).
     */
    fun assembleWords(
        tokens: IntArray,
        frames: IntArray,
        ends: IntArray,
        windowStartSeconds: Double,
        secondsPerEncoderFrame: Double,
        vocabulary: List<String>
    ): List<TimedWord> {
        val out = mutableListOf<TimedWord>()
        var current = StringBuilder()
        var wordStart = 0.0
        var wordEnd = 0.0
        var wordBeganClean = true

        for (idx in tokens.indices) {
            val id = tokens[idx]
            val frame = frames[idx]
            val end = ends[idx]
            if (id < 0 || id >= vocabulary.size) continue
            val piece = vocabulary[id]
            // Control tokens take the form `<...>` and carry no text.
            if (piece.startsWith("<") && piece.endsWith(">")) continue

            val t0 = windowStartSeconds + frame * secondsPerEncoderFrame
            val t1 = windowStartSeconds + max(frame + 1, end) * secondsPerEncoderFrame

            if (piece.isNotEmpty() && piece[0] == WORD_BOUNDARY) {
                if (current.isNotEmpty()) {
                    out.add(TimedWord(current.toString(), wordStart, wordEnd, wordBeganClean))
                }
                current = StringBuilder(piece.substring(1))
                wordStart = t0
                wordEnd = t1
                wordBeganClean = true
            } else if (current.isEmpty()) {
                current = StringBuilder(piece)
                wordStart = t0
                wordEnd = t1
                wordBeganClean = false
            } else {
                current.append(piece)
                wordEnd = t1
            }
        }
        if (current.isNotEmpty()) {
            out.add(TimedWord(current.toString(), wordStart, wordEnd, wordBeganClean))
        }
        return out
    }

    private fun normalisedWord(s: String): String {
        val sb = StringBuilder()
        for (c in s.lowercase()) {
            if (c.isLetterOrDigit() || c == '\'') sb.append(c)
        }
        return sb.toString()
    }

    /**
     * Rejoin a word that a hard window boundary split in two.
     */
    fun repairJoin(prefix: List<TimedWord>, suffix: List<TimedWord>): Pair<List<TimedWord>, List<TimedWord>> {
        val last = prefix.lastOrNull() ?: return prefix to suffix
        val first = suffix.firstOrNull() ?: return prefix to suffix
        if (!first.beganNewWord && first.start - last.end < 0.24) {
            val joined = TimedWord(
                text = last.text + first.text,
                start = last.start,
                end = first.end,
                beganNewWord = last.beganNewWord
            )
            return (prefix.dropLast(1) + joined) to suffix.drop(1)
        }
        return prefix to suffix
    }

    /**
     * Join two word lists whose audio overlapped in `[overlapStart, overlapEnd]`.
     */
    fun spliceOverlap(
        prefix: List<TimedWord>,
        suffix: List<TimedWord>,
        overlapStart: Double,
        overlapEnd: Double
    ): List<TimedWord> {
        if (prefix.isEmpty()) return suffix
        if (suffix.isEmpty()) return prefix

        val pIdx = prefix.indices.filter { prefix[it].end > overlapStart - 0.16 }
        val sIdx = suffix.indices.filter { suffix[it].start < overlapEnd + 0.16 }

        var bestRun = 0
        var bestDist = Double.MAX_VALUE
        var bestI = 0
        var bestJ = 0
        val maxRun = min(pIdx.size, sIdx.size)

        for (run in 1..maxRun) {
            for (a in 0..(pIdx.size - run)) {
                for (b in 0..(sIdx.size - run)) {
                    var matches = true
                    for (k in 0 until run) {
                        val pw = normalisedWord(prefix[pIdx[a + k]].text)
                        val sw = normalisedWord(suffix[sIdx[b + k]].text)
                        if (pw.isEmpty() || pw != sw) {
                            matches = false
                            break
                        }
                    }
                    if (!matches) continue
                    val dist = abs(prefix[pIdx[a]].start - suffix[sIdx[b]].start)
                    if (dist > 1.2) continue
                    if (run > bestRun || (run == bestRun && dist < bestDist)) {
                        bestRun = run
                        bestDist = dist
                        bestI = pIdx[a]
                        bestJ = sIdx[b]
                    }
                }
            }
        }

        if (bestRun > 0) {
            return prefix.subList(0, bestI + bestRun) + suffix.subList(bestJ + bestRun, suffix.size)
        }

        val mid = 0.5 * (overlapStart + overlapEnd)
        val cutPrefix = prefix.takeWhile { 0.5 * (it.start + it.end) <= mid }
        val cutSuffix = suffix.dropWhile { 0.5 * (it.start + it.end) <= mid }
        val (repairedP, repairedS) = repairJoin(cutPrefix, cutSuffix)
        return repairedP + repairedS
    }
}
