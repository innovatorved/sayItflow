package com.sayitflow.android.ml

/**
 * High-performance multilingual phonetic transliterator and normalizer for Hinglish (Hindi + English).
 *
 * Converts Devanagari Hindi text and mixed-script utterances into clean, conversational Romanized Hinglish
 * while preserving English words, numbers, and punctuation intact. Implements conversational schwa deletion,
 * nukta support, and a comprehensive high-frequency conversational dictionary.
 */
object HinglishNormalizer {

    private val commonWordMap: Map<String, String> = mapOf(
        // Pronouns
        "मैं" to "main", "मेरा" to "mera", "मेरी" to "meri", "मेरे" to "mere",
        "मुझे" to "mujhe", "मुझको" to "mujhko", "मुझसे" to "mujhse",
        "तुम" to "tum", "तुम्हारा" to "tumhara", "तुम्हारी" to "tumhari", "तुम्हारे" to "tumhare",
        "तुझे" to "tujhe", "तुझको" to "tujhko", "तुझसे" to "tujhse",
        "आप" to "aap", "आपका" to "aapka", "आपकी" to "aapki", "आपके" to "aapke",
        "आपको" to "aapko", "आपसे" to "aapse",
        "हम" to "hum", "हमारा" to "hamara", "हमारी" to "hamari", "हमारे" to "hamare",
        "हमें" to "humein", "हमको" to "humko", "हमसे" to "humse",
        "यह" to "yeh", "वह" to "woh", "ये" to "ye", "वो" to "wo",
        "इसे" to "ise", "इसको" to "isko", "इससे" to "isse",
        "उसे" to "use", "उसको" to "usko", "उससे" to "usse",
        "इन्हें" to "inhein", "उन्हें" to "unhein",
        "मेरेको" to "mereko", "तेरेको" to "tereko",

        // Question words
        "क्या" to "kya", "क्यों" to "kyun", "क्यूं" to "kyun", "क्यूँ" to "kyun",
        "कब" to "kab", "कहाँ" to "kahan", "कहां" to "kahan",
        "कैसे" to "kaise", "कैसा" to "kaisa", "कैसी" to "kaisi",
        "कौन" to "kaun", "किसे" to "kise", "किसको" to "kisko",
        "कितना" to "kitna", "कितनी" to "kitni", "कितने" to "kitne",

        // Auxiliaries & Copulas
        "है" to "hai", "हैं" to "hain", "था" to "tha", "थी" to "thi", "थे" to "the",
        "हो" to "ho", "हूँ" to "hoon", "हूं" to "hoon", "होगा" to "hoga", "होगी" to "hogi", "होंगे" to "honge",

        // Negation & Affirmation
        "नहीं" to "nahi", "नही" to "nahi", "ना" to "na", "मत" to "mat",
        "हाँ" to "haan", "हां" to "haan", "जी" to "ji",

        // Common Verbs
        "कर" to "kar", "करो" to "karo", "करना" to "karna", "किया" to "kiya", "की" to "ki",
        "करूंगा" to "karunga", "करूंगी" to "karungi", "करेंगे" to "karenge",
        "रहा" to "raha", "रही" to "rahi", "रहे" to "rahe",
        "गया" to "gaya", "गई" to "gayi", "गए" to "gaye",
        "जा" to "ja", "जाओ" to "jao", "जाना" to "jana", "जाऊंगा" to "jaunga",
        "आ" to "aa", "आओ" to "aao", "आया" to "aaya", "आना" to "aana", "आऊंगा" to "aaunga",
        "दे" to "de", "दो" to "do", "देना" to "dena", "दिया" to "diya",
        "ले" to "le", "लो" to "lo", "लेना" to "lena", "लिया" to "liya",
        "बोल" to "bol", "बोलो" to "bolo", "बोलना" to "bolna", "बोला" to "bola",
        "बता" to "bata", "बताओ" to "batao", "बताना" to "batana", "बताया" to "bataya",
        "देख" to "dekh", "देखो" to "dekho", "देखना" to "dekhna", "देखा" to "dekha",
        "सुन" to "sun", "सुनो" to "suno", "सुनना" to "sunna", "सुना" to "suna",
        "चल" to "chal", "चलो" to "chalo", "चलना" to "chalna", "चला" to "chala",
        "मिल" to "mil", "मिलो" to "milo", "मिलते" to "milte", "मिला" to "mila", "मिलना" to "milna",
        "समझ" to "samajh", "समझे" to "samjhe", "समझा" to "samjha",
        "लग" to "lag", "लगा" to "laga", "लगी" to "lagi", "लगे" to "lage",

        // Conjunctions & Prepositions
        "और" to "aur", "या" to "ya", "लेकिन" to "lekin", "मगर" to "magar",
        "अगर" to "agar", "क्योंकि" to "kyunki", "इसलिए" to "isliye",
        "तो" to "toh", "भी" to "bhi", "ही" to "hi",
        "से" to "se", "में" to "mein", "पर" to "par", "पे" to "pe",
        "को" to "ko", "का" to "ka", "के" to "ke", "तक" to "tak",

        // Adverbs & Qualifiers
        "ठीक" to "theek", "अच्छा" to "achha", "अच्छी" to "achhi", "अच्छे" to "achhe",
        "बहुत" to "bahut", "थोड़ा" to "thoda", "थोड़ी" to "thodi", "थोड़े" to "thode",
        "ज्यादा" to "zyada", "ज़्यादा" to "zyada", "कम" to "kam", "सब" to "sab",
        "कुछ" to "kuch", "कोई" to "koi", "बस" to "bas",

        // Time & Common Nouns
        "कल" to "kal", "आज" to "aaj", "परसों" to "parson", "अभी" to "abhi", "अब" to "ab",
        "फिर" to "phir", "बाद" to "baad", "पहले" to "pehle",
        "बजे" to "baje", "समय" to "samay", "टाइम" to "time",
        "भाई" to "bhai", "यार" to "yaar", "दोस्त" to "dost",
        "बात" to "baat", "काम" to "kaam", "घर" to "ghar", "पता" to "pata",
        "धन्यवाद" to "dhanyawad", "शुक्रिया" to "shukriya", "नमस्ते" to "namaste",
        "कृपया" to "kripya", "प्लीज" to "please", "प्लीज़" to "please",
        "फ़ाइल" to "file", "फाइल" to "file", "सेव" to "save", "गिटहब" to "github",
        "पुश" to "push", "खुश" to "khush", "सेंड" to "send", "जल्दी" to "jaldi",
        "खत्म" to "khatam", "जाएगा" to "jaega", "जाएगी" to "jaegi",
        "वहाँ" to "wahan", "वहां" to "wahan", "यहाँ" to "yahan", "यहां" to "yahan",
        "शुरू" to "shuru", "शुरु" to "shuru", "शुरुआत" to "shuruat", "शुरूआती" to "shuruati"
    )

    private val vowels: Map<Char, String> = mapOf(
        'अ' to "a", 'आ' to "aa", 'इ' to "i", 'ई' to "ee", 'उ' to "u", 'ऊ' to "oo",
        'ए' to "e", 'ऐ' to "ai", 'ओ' to "o", 'औ' to "au", 'ऋ' to "ri"
    )

    private val matras: Map<Char, String> = mapOf(
        'ा' to "a", 'ि' to "i", 'ी' to "i", 'ु' to "u", 'ू' to "u",
        'े' to "e", 'ै' to "ai", 'ो' to "o", 'ौ' to "au", 'ृ' to "ri"
    )

    private val consonants: Map<Char, String> = mapOf(
        'क' to "k", 'ख' to "kh", 'ग' to "g", 'घ' to "gh", 'ङ' to "n",
        'च' to "ch", 'छ' to "chh", 'ज' to "j", 'झ' to "jh", 'ञ' to "n",
        'ट' to "t", 'ठ' to "th", 'ड' to "d", 'ढ' to "dh", 'ण' to "n",
        'त' to "t", 'थ' to "th", 'द' to "d", 'ध' to "dh", 'न' to "n",
        'प' to "p", 'फ' to "ph", 'ब' to "b", 'भ' to "bh", 'म' to "m",
        'य' to "y", 'र' to "r", 'ल' to "l", 'व' to "v",
        'श' to "sh", 'ष' to "sh", 'स' to "s", 'ह' to "h",
        '\u095C' to "r", '\u095D' to "rh", '\u0958' to "q",
        '\u0959' to "kh", '\u095A' to "gh", '\u095B' to "z", '\u095E' to "f"
    )

    /**
     * Transliterates a Devanagari or mixed-script string to Romanized Hinglish.
     * Preserves Latin words, numbers, and punctuation.
     */
    fun transliterateToRomanHinglish(input: String): String {
        if (input.isBlank()) return input
        if (!input.any { it in '\u0900'..'\u097F' }) return input

        return input.split(" ").joinToString(" ") { token ->
            transliterateToken(token)
        }
    }

    private fun transliterateToken(token: String): String {
        if (!token.any { it in '\u0900'..'\u097F' }) {
            return token
        }

        // Separate leading and trailing punctuation
        var startIdx = 0
        while (startIdx < token.length && isPunctuation(token[startIdx])) {
            startIdx++
        }
        var endIdx = token.length
        while (endIdx > startIdx && isPunctuation(token[endIdx - 1])) {
            endIdx--
        }

        val prefix = token.substring(0, startIdx)
        val core = token.substring(startIdx, endIdx)
        val suffix = token.substring(endIdx)

        if (core.isEmpty()) {
            return token
        }

        // Check common word dictionary first
        val mapped = commonWordMap[core]
        val romanizedCore = mapped ?: phoneticDevanagariToRoman(core)

        // Map Hindi full stop (purnavirama) in suffix if present
        val cleanSuffix = suffix.replace('।', '.')

        return prefix + romanizedCore + cleanSuffix
    }

    private fun isPunctuation(ch: Char): Boolean {
        return ch in listOf(',', '.', '?', '!', ';', ':', '"', '\'', '(', ')', '[', ']', '{', '}', '-', '_', '/', '।')
    }

    /**
     * Converts a single Devanagari word to Roman phonetic representation with conversational schwa deletion.
     */
    fun phoneticDevanagariToRoman(word: String): String {
        val sb = StringBuilder()
        var i = 0
        while (i < word.length) {
            val ch = word[i]
            when {
                vowels.containsKey(ch) -> {
                    sb.append(vowels[ch])
                }
                consonants.containsKey(ch) -> {
                    var step = 0
                    val hasNukta = (i + 1 < word.length && word[i + 1] == '\u093C')
                    val base = if (hasNukta) {
                        step = 1
                        when (ch) {
                            'ड' -> "r"
                            'ढ' -> "rh"
                            'क' -> "q"
                            'ख' -> "kh"
                            'ग' -> "gh"
                            'ज' -> "z"
                            'फ' -> "f"
                            else -> consonants[ch] ?: ""
                        }
                    } else {
                        consonants[ch] ?: ""
                    }
                    sb.append(base)
                    i += step

                    val next = if (i + 1 < word.length) word[i + 1] else null
                    when {
                        next == '्' -> {
                            // Halant suppresses inherent 'a'
                            i++
                        }
                        next != null && matras.containsKey(next) -> {
                            sb.append(matras[next])
                            i++
                        }
                        next == null -> {
                            // Word-final schwa deletion in conversational Hindi (e.g. कल -> kal, not kala)
                        }
                        else -> {
                            // Inherent 'a' between consonants
                            sb.append("a")
                        }
                    }
                }
                matras.containsKey(ch) -> {
                    sb.append(matras[ch])
                }
                ch == 'ं' || ch == 'ँ' -> {
                    sb.append("n")
                }
                ch == 'ः' -> {
                    sb.append("h")
                }
                ch == '।' -> {
                    sb.append(".")
                }
                ch != '्' && ch != '\u093C' -> {
                    sb.append(ch)
                }
            }
            i++
        }
        return sb.toString()
    }
}
