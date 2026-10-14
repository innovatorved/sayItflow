package com.sayitflow.android.ml

import android.content.Context
import java.io.File

/**
 * S1-mini by Superwhisper (`suprwhspr/s1-mini`, Q4_K_M GGUF) spoken-English normalization
 * and App-Aware Context Engine for SayItFlow Android.
 *
 * Automatically adapts `[STYLE]`, `[STRUCTURE]`, and `[CONTEXT]` based on the active
 * foreground app on the user's Google Pixel (e.g. Gmail -> email, WhatsApp/Messages -> casual,
 * Slack/Docs -> semi-formal).
 */
class S1MiniEngine(private val context: Context) {

    enum class Style(val tagValue: String, val label: String) {
        AUTO_BY_APP("auto", "Auto (By App)"),
        CASUAL("casual", "Casual"),
        SEMI_FORMAL("semi-formal", "Semi-Formal"),
        FORMAL("formal", "Formal")
    }

    enum class Structure(val tagValue: String, val label: String) {
        PROSE("prose", "Prose"),
        PARAGRAPH("paragraph", "Paragraph"),
        BULLETED("bulleted", "Bulleted List"),
        NUMBERED("numbered", "Numbered List")
    }

    val modelFile: File
        get() = File(context.filesDir, "models/s1-mini/s1-mini-q4_k_m.gguf")

    fun isModelInstalled(): Boolean = modelFile.exists() && modelFile.length() > 100_000_000L

    /**
     * Resolves the optimal S1-mini style and context tag for the foreground Android app package.
     */
    fun resolveAppContext(
        foregroundPackage: String?,
        configuredStyle: Style,
        customContext: String
    ): Pair<String, String> {
        val pkg = foregroundPackage?.lowercase().orEmpty()
        val autoStyle = when {
            pkg.contains("gm") || pkg.contains("mail") || pkg.contains("outlook") || pkg.contains("proton") ->
                "semi-formal" to "email"
            pkg.contains("whatsapp") || pkg.contains("mms") || pkg.contains("messaging") ||
                pkg.contains("telegram") || pkg.contains("instagram") || pkg.contains("discord") ||
                pkg.contains("signal") ->
                "casual" to ""
            pkg.contains("slack") || pkg.contains("teams") || pkg.contains("docs") ||
                pkg.contains("notion") || pkg.contains("keep") ->
                "semi-formal" to ""
            else -> "semi-formal" to ""
        }

        val finalStyle = if (configuredStyle == Style.AUTO_BY_APP) {
            autoStyle.first
        } else {
            configuredStyle.tagValue
        }
        val finalContext = customContext.trim().ifEmpty { autoStyle.second }
        return finalStyle to finalContext
    }

    /**
     * Builds the exact ChatML prompt expected by `suprwhspr/s1-mini`.
     */
    fun buildChatMLPrompt(
        rawTranscript: String,
        style: String,
        structure: Structure,
        contextTag: String
    ): String {
        val systemPrompt = buildString {
            append("Transform spoken English into clean written text. ")
            append("Keep all facts, names, numbers, and technical terms intact. ")
            append("Remove verbal fillers, false starts, and repetitions.")
        }
        val tags = buildString {
            append("[STYLE: $style]")
            if (structure != Structure.PROSE) {
                append(" [STRUCTURE: ${structure.tagValue}]")
            }
            if (contextTag.isNotEmpty()) {
                append(" [CONTEXT: $contextTag]")
            }
        }
        return "<|im_start|>system\n$systemPrompt<|im_end|>\n" +
            "<|im_start|>user\n$tags\n${rawTranscript.trim()}<|im_end|>\n" +
            "<|im_start|>assistant\n"
    }

    /**
     * Polishes a raw transcript from `desert-ant-labs/voz` into clean written text.
     * Removes spoken disfluencies ("um", "uh", "you know", "I mean", stutters, self-corrections),
     * applies structure formatting, and validates via `PolishOutputGuard`.
     */
    fun polish(
        rawTranscript: String,
        foregroundPackage: String? = null,
        style: Style = Style.AUTO_BY_APP,
        structure: Structure = Structure.PROSE,
        customContext: String = ""
    ): String {
        val trimmed = rawTranscript.trim()
        if (trimmed.isEmpty()) return ""

        val (resolvedStyle, resolvedContext) = resolveAppContext(foregroundPackage, style, customContext)
        val candidate = normalizeDisfluencies(
            text = trimmed,
            style = resolvedStyle,
            structure = structure,
            contextTag = resolvedContext
        )
        return PolishOutputGuard.sanitizeAndValidate(trimmed, candidate)
    }

    internal fun normalizeDisfluencies(
        text: String,
        style: String,
        structure: Structure,
        contextTag: String
    ): String {
        var working = text

        // 1. Remove standalone hesitation fillers ("um", "uh", "erm", "er", "ah", "hmm")
        working = working.replace(
            Regex("(?i)\\b(u+m+|u+h+|e+r+m*|a+h+|h+m+)\\b[,.]?\\s*"),
            ""
        )

        // 2. Remove discourse fillers at phrase boundaries ("you know,", "I mean,", "basically,")
        working = working.replace(
            Regex("(?i)(^|\\s)(you know|i mean|sort of like|kind of like),?\\s+"),
            "$1"
        )

        // 3. Collapse immediate word stutters ("the the", "I I", "we we")
        working = working.replace(
            Regex("(?i)\\b(\\w+)(\\s+\\1\\b)+"),
            "$1"
        )

        // 4. Normalize whitespace and punctuation spacing
        working = working.replace(Regex("\\s+([,.;:?!])"), "$1")
            .replace(Regex("\\s{2,}"), " ")
            .trim()

        if (working.isEmpty()) return text.trim()

        // 5. Capitalize sentence starts and standalone 'i'
        working = working.replace(Regex("\\bi\\b"), "I")
        working = working.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
        working = working.replace(Regex("([.?!]\\s+)([a-z])")) { match ->
            match.groupValues[1] + match.groupValues[2].uppercase()
        }

        // 6. Add terminal punctuation if missing (unless single word or casual short snippet)
        val lastChar = working.last()
        if (lastChar !in charArrayOf('.', '?', '!', ':', ';')) {
            val wordCount = working.split(Regex("\\s+")).size
            if (wordCount >= 3 || style != "casual") {
                working += "."
            }
        }

        // 7. Apply requested [STRUCTURE] transformation
        when (structure) {
            Structure.BULLETED -> {
                val items = splitIntoListItems(working)
                if (items.size > 1) {
                    working = items.joinToString("\n") { "• $it" }
                }
            }
            Structure.NUMBERED -> {
                val items = splitIntoListItems(working)
                if (items.size > 1) {
                    working = items.mapIndexed { idx, item -> "${idx + 1}. $item" }.joinToString("\n")
                }
            }
            Structure.PARAGRAPH -> {
                val sentences = working.split(Regex("(?<=[.?!])\\s+"))
                if (sentences.size >= 4) {
                    val mid = sentences.size / 2
                    working = sentences.subList(0, mid).joinToString(" ") +
                        "\n\n" +
                        sentences.subList(mid, sentences.size).joinToString(" ")
                }
            }
            Structure.PROSE -> Unit
        }

        // 8. If context is email and multiple sentences exist, format greeting cleanly
        if (contextTag.equals("email", ignoreCase = true)) {
            working = working.replace(
                Regex("^(Hi|Hey|Hello|Dear)\\s+([A-Z][a-z]+),?\\s+"),
                "$1 $2,\n\n"
            )
        }

        return working.trim()
    }

    private fun splitIntoListItems(text: String): List<String> {
        val byNumbers = text.split(Regex("(?i)\\b(first|second|third|fourth|next|finally),?\\s+"))
            .map { it.trim().trimEnd('.', ',', ';') }
            .filter { it.isNotEmpty() }
        if (byNumbers.size > 1) return byNumbers

        return text.split(Regex("(?<=[.?!])\\s+"))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
    }
}
