package com.sayitflow.android

import android.content.Context
import android.content.SharedPreferences
import com.sayitflow.android.audio.AudioCaptureManager
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

    enum class TriggerMode(val id: String, val title: String, val subtitle: String) {
        HOLD_VOLUME_DOWN(
            "hold_vol_down",
            "Hold Volume Down (Recommended)",
            "Short tap adjusts volume normally; holding ≥ 280ms dictates anywhere"
        ),
        VOLUME_CHORD(
            "vol_chord",
            "Volume Up + Volume Down Chord",
            "Hold both Volume Up and Volume Down together to dictate"
        ),
        HOLD_VOLUME_UP(
            "hold_vol_up",
            "Hold Volume Up",
            "Short tap raises volume; holding ≥ 280ms dictates anywhere"
        )
    }

    data class VozLanguage(val code: String, val name: String)

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
            VozLanguage("auto", "Auto-Detect (25 Languages)"),
            VozLanguage("en", "English"),
            VozLanguage("de", "German (Deutsch)"),
            VozLanguage("fr", "French (Français)"),
            VozLanguage("es", "Spanish (Español)"),
            VozLanguage("it", "Italian (Italiano)"),
            VozLanguage("pt", "Portuguese (Português)"),
            VozLanguage("nl", "Dutch (Nederlands)"),
            VozLanguage("pl", "Polish (Polski)"),
            VozLanguage("ru", "Russian (Русский)"),
            VozLanguage("uk", "Ukrainian (Українська)"),
            VozLanguage("sv", "Swedish (Svenska)"),
            VozLanguage("da", "Danish (Dansk)"),
            VozLanguage("fi", "Finnish (Suomi)"),
            VozLanguage("no", "Norwegian (Norsk)"),
            VozLanguage("cs", "Czech (Čeština)"),
            VozLanguage("sk", "Slovak (Slovenčina)"),
            VozLanguage("ro", "Romanian (Română)"),
            VozLanguage("hu", "Hungarian (Magyar)"),
            VozLanguage("bg", "Bulgarian (Български)"),
            VozLanguage("el", "Greek (Ελληνικά)"),
            VozLanguage("hr", "Croatian (Hrvatski)"),
            VozLanguage("sl", "Slovenian (Slovenščina)"),
            VozLanguage("lt", "Lithuanian (Lietuvių)"),
            VozLanguage("lv", "Latvian (Latviešu)"),
            VozLanguage("et", "Estonian (Eesti)")
        )
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences("sayitflow_prefs", Context.MODE_PRIVATE)

    val vozEngine = VozEngine(context)
    val s1MiniEngine = S1MiniEngine(context)
    val downloadManager = ModelDownloadManager(context)
    val audioCapture = AudioCaptureManager()

    private val _triggerMode = MutableStateFlow(
        TriggerMode.entries.find { it.id == prefs.getString("trigger_mode", TriggerMode.HOLD_VOLUME_DOWN.id) }
            ?: TriggerMode.HOLD_VOLUME_DOWN
    )
    val triggerMode: StateFlow<TriggerMode> = _triggerMode.asStateFlow()

    private val _holdThresholdMs = MutableStateFlow(prefs.getLong("hold_threshold_ms", 280L))
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

    private val _history = MutableStateFlow<List<DictationRecord>>(emptyList())
    val history: StateFlow<List<DictationRecord>> = _history.asStateFlow()

    fun setAccessibilityConnected(connected: Boolean) {
        _accessibilityConnected.value = connected
    }

    fun setTriggerMode(mode: TriggerMode) {
        _triggerMode.value = mode
        prefs.edit().putString("trigger_mode", mode.id).apply()
    }

    fun setHoldThresholdMs(ms: Long) {
        val clamped = ms.coerceIn(180L, 600L)
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
}
