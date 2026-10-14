package com.sayitflow.android

import android.content.Context
import android.content.SharedPreferences
import com.sayitflow.android.audio.AudioCaptureManager
import com.sayitflow.android.ml.FastStreamingAsrEngine
import com.sayitflow.android.ml.ModelDownloadManager
import com.sayitflow.android.ml.S1MiniEngine
import com.sayitflow.android.ml.VozEngine
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Shared singleton coordinator connecting `SayItFlowAccessibilityService` (hardware Volume Hold +
 * direct text injection) with `MainActivity` (Monochrome Studio Dashboard).
 */
class SayItFlowCoordinator private constructor(context: Context) {

    enum class AsrEngineMode(val id: String, val title: String, val subtitle: String, val badge: String) {
        INSTANT_STREAMING(
            "instant_streaming",
            "Instant Tensor Stream (Recommended)",
            "Streams speech live while holding button — responds in ~80–180 ms on release",
            "~120ms"
        ),
        VOZ_OFFLINE(
            "voz_offline",
            "Voz-0.6B Offline ONNX",
            "600M-param FastConformer-TDT (384 MB) — batch offline decoding (~3–4s)",
            "OFFLINE"
        )
    }

    enum class TriggerMode(val id: String, val title: String, val subtitle: String) {
        HOLD_VOLUME_DOWN(
            "hold_vol_down",
            "Hold Volume Down (Recommended)",
            "Short tap adjusts volume normally; holding ≥ 500ms dictates anywhere"
        ),
        VOLUME_CHORD(
            "vol_chord",
            "Volume Up + Volume Down Chord",
            "Hold both Volume Up and Volume Down together to dictate"
        ),
        HOLD_VOLUME_UP(
            "hold_vol_up",
            "Hold Volume Up",
            "Short tap raises volume; holding ≥ 500ms dictates anywhere"
        )
    }

    data class VozLanguage(val code: String, val name: String, val flag: String = "🌐")

    data class DictationRecord(
        val rawTranscript: String,
        val polishedTranscript: String,
        val targetPackage: String,
        val elapsedMs: Long,
        val timestampMs: Long = System.currentTimeMillis()
    )

    companion object {
        @Volatile
        private var instance: SayItFlowCoordinator? = null

        fun getInstance(context: Context): SayItFlowCoordinator {
            return instance ?: synchronized(this) {
                instance ?: SayItFlowCoordinator(context.applicationContext).also { instance = it }
            }
        }

        val SUPPORTED_LANGUAGES = listOf(
            VozLanguage("hinglish", "Hinglish (EN+HI)", "IN"),
            VozLanguage("auto", "Auto (25+ Langs)", "✦"),
            VozLanguage("en-IN", "English (India)", "IN"),
            VozLanguage("hi", "हिन्दी (Hindi)", "HI"),
            VozLanguage("en", "English (US)", "EN"),
            VozLanguage("de", "Deutsch", "DE"),
            VozLanguage("fr", "Français", "FR"),
            VozLanguage("es", "Español", "ES"),
            VozLanguage("it", "Italiano", "IT"),
            VozLanguage("pt", "Português", "PT"),
            VozLanguage("nl", "Nederlands", "NL"),
            VozLanguage("pl", "Polski", "PL"),
            VozLanguage("ru", "Русский", "RU"),
            VozLanguage("uk", "Українська", "UK"),
            VozLanguage("sv", "Svenska", "SV"),
            VozLanguage("da", "Dansk", "DA"),
            VozLanguage("fi", "Suomi", "FI"),
            VozLanguage("no", "Norsk", "NO"),
            VozLanguage("cs", "Čeština", "CS"),
            VozLanguage("sk", "Slovenčina", "SK"),
            VozLanguage("ro", "Română", "RO"),
            VozLanguage("hu", "Magyar", "HU"),
            VozLanguage("bg", "Български", "BG"),
            VozLanguage("el", "Ελληνικά", "EL"),
            VozLanguage("hr", "Hrvatski", "HR"),
            VozLanguage("sl", "Slovenščina", "SL"),
            VozLanguage("lt", "Lietuvių", "LT"),
            VozLanguage("lv", "Latviešu", "LV"),
            VozLanguage("et", "Eesti", "ET")
        )
        fun friendlyAppName(packageName: String): String {
            val lower = packageName.lowercase()
            return when {
                lower.isBlank() || lower == "system" -> "System Input"
                lower.contains("sayitflow") -> "SayItFlow Cockpit"
                lower.contains("whatsapp") -> "WhatsApp"
                lower.contains("google.android.gm") || lower.contains("gmail") -> "Gmail"
                lower.contains("apps.messaging") || lower.contains("mms") -> "Messages"
                lower.contains("telegram") -> "Telegram"
                lower.contains("instagram") -> "Instagram"
                lower.contains("slack") -> "Slack"
                lower.contains("discord") -> "Discord"
                lower.contains("notion") -> "Notion"
                lower.contains("docs") -> "Google Docs"
                lower.contains("keep") -> "Google Keep"
                lower.contains("chrome") -> "Chrome"
                lower.contains("twitter") || lower.contains("x.android") -> "X"
                lower.contains("linkedin") -> "LinkedIn"
                else -> packageName.substringAfterLast('.').replaceFirstChar { it.uppercase() }
            }
        }

        fun contextBadgeForPackage(packageName: String): String {
            val app = friendlyAppName(packageName).uppercase()
            val lower = packageName.lowercase()
            val mode = when {
                lower.contains("gm") || lower.contains("mail") || lower.contains("outlook") -> "EMAIL"
                lower.contains("whatsapp") || lower.contains("mms") || lower.contains("messaging") ||
                    lower.contains("telegram") || lower.contains("instagram") || lower.contains("discord") -> "CASUAL"
                else -> "PROSE"
            }
            return "$app · $mode"
        }
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences("sayitflow_prefs", Context.MODE_PRIVATE)

    val fastStreamingEngine = FastStreamingAsrEngine(context)
    val vozEngine = VozEngine(context)
    val s1MiniEngine = S1MiniEngine(context)
    val downloadManager = ModelDownloadManager(context)
    val audioCapture = AudioCaptureManager()

    private val _asrEngineMode = MutableStateFlow(
        AsrEngineMode.entries.find {
            it.id == prefs.getString("asr_engine_mode", AsrEngineMode.INSTANT_STREAMING.id)
        } ?: AsrEngineMode.INSTANT_STREAMING
    )
    val asrEngineMode: StateFlow<AsrEngineMode> = _asrEngineMode.asStateFlow()

    init {
        if (_asrEngineMode.value == AsrEngineMode.VOZ_OFFLINE && vozEngine.areModelFilesInstalled()) {
            vozEngine.warmUpAsync()
        }
    }

    private val _triggerMode = MutableStateFlow(
        TriggerMode.entries.find { it.id == prefs.getString("trigger_mode", TriggerMode.HOLD_VOLUME_DOWN.id) }
            ?: TriggerMode.HOLD_VOLUME_DOWN
    )
    val triggerMode: StateFlow<TriggerMode> = _triggerMode.asStateFlow()

    private val _holdThresholdMs = MutableStateFlow(
        prefs.getLong("hold_threshold_ms", 500L).let { saved ->
            if (saved < 400L) {
                prefs.edit().putLong("hold_threshold_ms", 500L).apply()
                500L
            } else {
                saved
            }
        }
    )
    val holdThresholdMs: StateFlow<Long> = _holdThresholdMs.asStateFlow()

    private val _selectedLanguage = MutableStateFlow(
        prefs.getString("selected_language", "auto") ?: "auto"
    )
    val selectedLanguage: StateFlow<String> = _selectedLanguage.asStateFlow()

    private val _s1MiniEnabled = MutableStateFlow(prefs.getBoolean("s1_mini_enabled", true))
    val s1MiniEnabled: StateFlow<Boolean> = _s1MiniEnabled.asStateFlow()

    private val _s1Style = MutableStateFlow(
        S1MiniEngine.Style.entries.find {
            it.tagValue == prefs.getString("s1_style", S1MiniEngine.Style.AUTO_BY_APP.tagValue)
        } ?: S1MiniEngine.Style.AUTO_BY_APP
    )
    val s1Style: StateFlow<S1MiniEngine.Style> = _s1Style.asStateFlow()

    private val _s1Structure = MutableStateFlow(
        S1MiniEngine.Structure.entries.find {
            it.tagValue == prefs.getString("s1_structure", S1MiniEngine.Structure.PROSE.tagValue)
        } ?: S1MiniEngine.Structure.PROSE
    )
    val s1Structure: StateFlow<S1MiniEngine.Structure> = _s1Structure.asStateFlow()

    private val _s1CustomContext = MutableStateFlow(prefs.getString("s1_context", "") ?: "")
    val s1CustomContext: StateFlow<String> = _s1CustomContext.asStateFlow()

    private val _accessibilityConnected = MutableStateFlow(false)
    val accessibilityConnected: StateFlow<Boolean> = _accessibilityConnected.asStateFlow()

    private val _activeForegroundPackage = MutableStateFlow("com.sayitflow.android")
    val activeForegroundPackage: StateFlow<String> = _activeForegroundPackage.asStateFlow()

    private val _history = MutableStateFlow<List<DictationRecord>>(emptyList())
    val history: StateFlow<List<DictationRecord>> = _history.asStateFlow()

    fun setAccessibilityConnected(connected: Boolean) {
        _accessibilityConnected.value = connected
    }

    fun setActiveForegroundPackage(pkg: String) {
        if (pkg.isNotBlank()) {
            _activeForegroundPackage.value = pkg
        }
    }

    fun setTriggerMode(mode: TriggerMode) {
        _triggerMode.value = mode
        prefs.edit().putString("trigger_mode", mode.id).apply()
    }

    fun setAsrEngineMode(mode: AsrEngineMode) {
        _asrEngineMode.value = mode
        prefs.edit().putString("asr_engine_mode", mode.id).apply()
        if (mode == AsrEngineMode.VOZ_OFFLINE && vozEngine.areModelFilesInstalled()) {
            vozEngine.warmUpAsync()
        }
    }

    fun setHoldThresholdMs(ms: Long) {
        val clamped = ms.coerceIn(350L, 900L)
        _holdThresholdMs.value = clamped
        prefs.edit().putLong("hold_threshold_ms", clamped).apply()
    }

    fun setSelectedLanguage(code: String) {
        _selectedLanguage.value = code
        prefs.edit().putString("selected_language", code).apply()
    }

    fun setS1MiniEnabled(enabled: Boolean) {
        _s1MiniEnabled.value = enabled
        prefs.edit().putBoolean("s1_mini_enabled", enabled).apply()
    }

    fun setS1Style(style: S1MiniEngine.Style) {
        _s1Style.value = style
        prefs.edit().putString("s1_style", style.tagValue).apply()
    }

    fun setS1Structure(structure: S1MiniEngine.Structure) {
        _s1Structure.value = structure
        prefs.edit().putString("s1_structure", structure.tagValue).apply()
    }

    fun setS1CustomContext(ctx: String) {
        _s1CustomContext.value = ctx
        prefs.edit().putString("s1_context", ctx).apply()
    }

    fun recordDictation(record: DictationRecord) {
        _history.value = (listOf(record) + _history.value).take(25)
    }

    fun clearHistory() {
        _history.value = emptyList()
    }
}
