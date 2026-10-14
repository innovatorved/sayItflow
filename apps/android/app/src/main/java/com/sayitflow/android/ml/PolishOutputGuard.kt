package com.sayitflow.android.ml

/**
 * Ports macOS `PolishOutputGuard.swift` to Android:
 * Validates polished output so that conversational refusals, prompt echoes, or
 * runaway hallucinations are rejected and gracefully fall back to the clean transcript.
 */
object PolishOutputGuard {

    private val conversationalRefusalPrefixes = listOf(
        "i'm sorry",
        "i am sorry",
        "i cannot",
        "i can't",
        "as an ai",
        "sure, here",
        "here is the",
        "certainly!",
        "please provide"
    )

    fun sanitizeAndValidate(rawTranscript: String, candidateOutput: String): String {
        val rawTrimmed = rawTranscript.trim()
        if (rawTrimmed.isEmpty()) return ""

        var cleaned = candidateOutput
            .replace("<|im_end|>", "")
            .replace("<|im_start|>assistant", "")
            .replace("<|im_start|>", "")
            .trim()

        if (cleaned.isEmpty()) return rawTrimmed

        // Strip leaked control tags like [STYLE: casual]
        cleaned = cleaned.replace(Regex("^\\[(STYLE|STRUCTURE|CONTEXT):[^\\]]*\\]\\s*", RegexOption.IGNORE_CASE), "").trim()

        val lower = cleaned.lowercase()
        val rawLower = rawTrimmed.lowercase()

        for (prefix in conversationalRefusalPrefixes) {
            if (lower.startsWith(prefix) && !rawLower.startsWith(prefix)) {
                return rawTrimmed
            }
        }

        // Guard against runaway expansion (> 2.5x original character length + 60)
        if (cleaned.length > rawTrimmed.length * 2.5 + 60) {
            return rawTrimmed
        }

        return cleaned
    }
}
