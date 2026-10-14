package com.sayitflow.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sayitflow.android.SayItFlowCoordinator
import com.sayitflow.android.ml.S1MiniEngine
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.sin

// ============================================================================
// Monitor YT (https://monitoryt.com/) Lo-Fi Paper & Ink Design Tokens
// --paper: #fbf3e4 | --paper-deep: #f3e4c6 | --ink: #1b1712 | --ink-soft: #5a5044
// --red: #ff3b2f   | --yellow: #ffce4a     | --teal: #36c2ad | --sky: #74a7ff
// --coral: #ff9e86 | --lilac: #c8a8ff
// ============================================================================
private val PaperBg = Color(0xFFFBF3E4)
private val PaperDeep = Color(0xFFF3E4C6)
private val CardWhite = Color(0xFFFFFFFF)
private val CardButter = Color(0xFFFFF7E0)
private val CardMint = Color(0xFFE6FBF6)
private val CardPeach = Color(0xFFFFF0EC)

private val Ink = Color(0xFF1B1712)
private val InkSoft = Color(0xFF5A5044)
private val InkMuted = Color(0xFF8A7E6E)

private val AccentRed = Color(0xFFFF3B2F)
private val AccentRedDeep = Color(0xFFD52817)
private val AccentYellow = Color(0xFFFFCE4A)
private val AccentTeal = Color(0xFF36C2AD)
private val AccentSky = Color(0xFF74A7FF)

/**
 * Draws the signature `monitoryt.com` hard offset neo-brutalist shadow (`4dp 4dp 0 var(--ink)`),
 * warm card fill, and crisp `2dp solid var(--ink)` border.
 */
private fun Modifier.lofiCard(
    backgroundColor: Color = CardWhite,
    cornerRadius: Dp = 16.dp,
    borderWidth: Dp = 2.dp,
    shadowOffset: Dp = 4.dp
): Modifier = this
    .drawBehind {
        val radiusPx = cornerRadius.toPx()
        val offsetPx = shadowOffset.toPx()
        drawRoundRect(
            color = Ink,
            topLeft = Offset(offsetPx, offsetPx),
            size = Size(size.width, size.height),
            cornerRadius = CornerRadius(radiusPx, radiusPx)
        )
    }
    .clip(RoundedCornerShape(cornerRadius))
    .background(backgroundColor)
    .border(borderWidth, Ink, RoundedCornerShape(cornerRadius))

/**
 * Draws the `monitoryt.com` pill button (`border-radius: 999px; border: 2px solid var(--ink); box-shadow: 3.5px 3.5px 0 var(--ink)`).
 */
private fun Modifier.lofiPill(
    backgroundColor: Color = AccentRed,
    borderWidth: Dp = 2.dp,
    shadowOffset: Dp = 3.5.dp
): Modifier = this
    .drawBehind {
        val radiusPx = size.height / 2f
        val offsetPx = shadowOffset.toPx()
        drawRoundRect(
            color = Ink,
            topLeft = Offset(offsetPx, offsetPx),
            size = Size(size.width, size.height),
            cornerRadius = CornerRadius(radiusPx, radiusPx)
        )
    }
    .clip(RoundedCornerShape(999.dp))
    .background(backgroundColor)
    .border(borderWidth, Ink, RoundedCornerShape(999.dp))

/**
 * Draws the subtle `monitoryt.com` radial paper dot-grid (`radial-gradient(circle at 1px 1px, rgba(27,23,18,0.08) 1px, transparent 0)`).
 */
private fun Modifier.paperDotGrid(): Modifier = this
    .background(PaperBg)
    .drawBehind {
        val stepPx = 22.dp.toPx()
        val dotRadius = 1.15.dp.toPx()
        val dotColor = Ink.copy(alpha = 0.085f)
        var y = stepPx / 2f
        while (y < size.height) {
            var x = stepPx / 2f
            while (x < size.width) {
                drawCircle(
                    color = dotColor,
                    radius = dotRadius,
                    center = Offset(x, y)
                )
                x += stepPx
            }
            y += stepPx
        }
    }

private enum class AppTab(val title: String, val icon: ImageVector) {
    DICTATE("Dictate", Icons.Rounded.Mic),
    SETTINGS("Settings", Icons.Rounded.Tune),
    HISTORY("History", Icons.Rounded.History)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DashboardScreen(
    coordinator: SayItFlowCoordinator,
    hasMicPermission: Boolean,
    onRequestMicPermission: () -> Unit,
    onOpenAccessibilitySettings: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val isBatchRecording by coordinator.audioCapture.isRecording.collectAsState()
    val isStreamListening by coordinator.fastStreamingEngine.isListening.collectAsState()
    val isRecording = isBatchRecording || isStreamListening

    val batchWaveform by coordinator.audioCapture.waveformLevels.collectAsState()
    val streamWaveform by coordinator.fastStreamingEngine.waveformLevels.collectAsState()
    val waveformLevels = if (isStreamListening) streamWaveform else batchWaveform

    val liveStreamTranscript by coordinator.fastStreamingEngine.liveTranscript.collectAsState()
    val liveWhisperPreview by coordinator.senseVoiceEngine.livePreviewText.collectAsState()
    val livePartialText = if (isStreamListening) liveStreamTranscript else liveWhisperPreview

    val asrEngineMode by coordinator.asrEngineMode.collectAsState()
    val isWhisperLoaded by coordinator.senseVoiceEngine.isLoaded.collectAsState()

    val isAccessibilityConnected by coordinator.accessibilityConnected.collectAsState()
    val activeForegroundPkg by coordinator.activeForegroundPackage.collectAsState()

    val selectedLanguage by coordinator.selectedLanguage.collectAsState()
    val triggerMode by coordinator.triggerMode.collectAsState()
    val holdThresholdMs by coordinator.holdThresholdMs.collectAsState()

    val isS1MiniEnabled by coordinator.s1MiniEnabled.collectAsState()
    val s1Style by coordinator.s1Style.collectAsState()
    val s1Structure by coordinator.s1Structure.collectAsState()
    val s1CustomContext by coordinator.s1CustomContext.collectAsState()
    val history by coordinator.history.collectAsState()

    var activeTab by remember { mutableStateOf(AppTab.DICTATE) }
    var isInAppTranscribing by remember { mutableStateOf(false) }
    var scratchpadText by remember { mutableStateOf("") }
    var baseScratchpadBeforeStream by remember { mutableStateOf("") }
    var statusBannerText by remember { mutableStateOf<String?>(null) }
    var copiedScratchpad by remember { mutableStateOf(false) }
    var recordingElapsedMs by remember { mutableLongStateOf(0L) }

    // Ensure bundled Whisper-Tiny INT8 files exist on disk (0 MB loaded in RAM while idle)
    LaunchedEffect(asrEngineMode) {
        coordinator.senseVoiceEngine.prepareAssetsOnDiskAsync()
    }

    // Track recording timer
    LaunchedEffect(isRecording) {
        if (isRecording) {
            val start = System.currentTimeMillis()
            while (true) {
                recordingElapsedMs = System.currentTimeMillis() - start
                delay(50L)
            }
        } else {
            recordingElapsedMs = 0L
        }
    }

    // Sync latest hardware-triggered dictation into scratchpad if empty or updated
    LaunchedEffect(history.firstOrNull()?.timestampMs) {
        val newest = history.firstOrNull() ?: return@LaunchedEffect
        if (scratchpadText.isBlank()) {
            scratchpadText = newest.polishedTranscript
        }
    }

    fun copyText(text: String) {
        if (text.isBlank()) return
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("SayItFlow Dictation", text))
        copiedScratchpad = true
        scope.launch {
            delay(1500L)
            copiedScratchpad = false
        }
    }

    fun startOrStopInAppDictation() {
        if (isInAppTranscribing) return

        if (!hasMicPermission) {
            statusBannerText = "Grant Microphone access first to dictate."
            onRequestMicPermission()
            return
        }

        val useInstantStreaming = coordinator.shouldUseZeroLossStreamingPipe()

        if (useInstantStreaming) {
            if (!isStreamListening) {
                statusBannerText = null
                baseScratchpadBeforeStream = scratchpadText.trim()
                val started = coordinator.fastStreamingEngine.startStreaming(selectedLanguage)
                if (!started) {
                    statusBannerText = "Could not start speech stream. Check microphone permission."
                }
            } else {
                isInAppTranscribing = true
                scope.launch {
                    val t0 = System.currentTimeMillis()
                    try {
                        val raw = coordinator.fastStreamingEngine.stopAndAwaitTranscript(maxWaitMs = 1500L)
                        if (raw.isBlank()) {
                            statusBannerText = "No speech detected — speak clearly near the microphone."
                        } else {
                            val shouldPolish = isS1MiniEnabled &&
                                (selectedLanguage == "auto" || selectedLanguage == "en" || selectedLanguage == "en-IN" || selectedLanguage == "hinglish")
                            val finalOut = if (shouldPolish) {
                                coordinator.s1MiniEngine.polish(
                                    rawTranscript = raw,
                                    foregroundPackage = activeForegroundPkg,
                                    style = s1Style,
                                    structure = s1Structure,
                                    customContext = s1CustomContext
                                )
                            } else {
                                raw
                            }
                            val elapsed = (System.currentTimeMillis() - t0).coerceAtLeast(1L)
                            scratchpadText = if (baseScratchpadBeforeStream.isBlank()) {
                                finalOut
                            } else {
                                "$baseScratchpadBeforeStream $finalOut"
                            }
                            copyText(finalOut)
                            statusBannerText = "⚡ ${elapsed}ms · Hybrid SODA+Whisper · Copied ✓"
                            coordinator.recordDictation(
                                SayItFlowCoordinator.DictationRecord(
                                    rawTranscript = raw,
                                    polishedTranscript = finalOut,
                                    targetPackage = context.packageName,
                                    elapsedMs = elapsed
                                )
                            )
                        }
                    } catch (e: Exception) {
                        statusBannerText = "Error: ${e.localizedMessage ?: "Transcription failed"}"
                    } finally {
                        isInAppTranscribing = false
                    }
                }
            }
            return
        }

        if (!isBatchRecording) {
            statusBannerText = null
            val started = coordinator.audioCapture.startRecording()
            if (started) {
                coordinator.senseVoiceEngine.startLiveSession(coordinator.audioCapture)
            } else {
                statusBannerText = "Could not open microphone. Check permission."
            }
        } else {
            val samples = coordinator.audioCapture.stopRecording()
            val rawMs = coordinator.audioCapture.lastRawDurationMs
            if (rawMs < 180L) {
                coordinator.senseVoiceEngine.cancelLiveSession()
                statusBannerText = "Recording too short — speak clearly near the microphone."
                return
            }
            if (samples.size < 1600) {
                coordinator.senseVoiceEngine.cancelLiveSession()
                statusBannerText = "No speech detected — speak clearly near the microphone."
                return
            }
            isInAppTranscribing = true
            statusBannerText = "Transcribing with Whisper-Tiny INT8 Turbo..."
            scope.launch {
                val t0 = System.currentTimeMillis()
                try {
                    val raw = coordinator.senseVoiceEngine.finishLiveSession(
                        finalNormalizedSamples = samples,
                        rawSampleCount = coordinator.audioCapture.lastRawSampleCount,
                        audioCaptureManager = coordinator.audioCapture,
                        language = selectedLanguage
                    ).text
                    if (raw.isBlank()) {
                        statusBannerText = "No speech detected. Speak clearly near the microphone."
                    } else {
                        val shouldPolish = isS1MiniEnabled &&
                            (selectedLanguage == "auto" || selectedLanguage == "en" || selectedLanguage == "en-IN" || selectedLanguage == "hinglish")
                        val finalOut = if (shouldPolish) {
                            coordinator.s1MiniEngine.polish(
                                rawTranscript = raw,
                                foregroundPackage = activeForegroundPkg,
                                style = s1Style,
                                structure = s1Structure,
                                customContext = s1CustomContext
                            )
                        } else {
                            raw
                        }
                        val elapsed = (System.currentTimeMillis() - t0).coerceAtLeast(1L)
                        scratchpadText = if (scratchpadText.isBlank()) {
                            finalOut
                        } else {
                            "$scratchpadText $finalOut"
                        }
                        copyText(finalOut)
                        statusBannerText = "⚡ ${elapsed}ms · Whisper INT8 · Copied ✓"
                        coordinator.recordDictation(
                            SayItFlowCoordinator.DictationRecord(
                                rawTranscript = raw,
                                polishedTranscript = finalOut,
                                targetPackage = context.packageName,
                                elapsedMs = elapsed
                            )
                        )
                    }
                } catch (e: Exception) {
                    statusBannerText = "Error: ${e.localizedMessage ?: "Transcription failed"}"
                } finally {
                    isInAppTranscribing = false
                }
            }
        }
    }

    val isSystemFullyReady = hasMicPermission && isAccessibilityConnected

    Column(
        modifier = Modifier
            .fillMaxSize()
            .paperDotGrid()
            .statusBarsPadding()
    ) {
        // 1. Monitor YT Lo-Fi Paper Header Bar + Ink Ticker Strip
        LofiHeaderBar(
            asrEngineMode = asrEngineMode,
            isWhisperLoaded = isWhisperLoaded,
            isSystemReady = isSystemFullyReady,
            triggerMode = triggerMode,
            isS1MiniEnabled = isS1MiniEnabled,
            onClickStatus = { activeTab = AppTab.SETTINGS },
            onClickTicker = {
                if (!hasMicPermission) {
                    onRequestMicPermission()
                } else {
                    onOpenAccessibilitySettings()
                }
            }
        )

        // 2. Main Scrollable Canvas
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Segmented Lo-Fi Navigation Pills
            LofiTabRow(
                activeTab = activeTab,
                historyCount = history.size,
                onSelectTab = { activeTab = it }
            )

            // Setup Checklist (only shown if any permission is missing)
            if (!isSystemFullyReady) {
                SetupChecklistCard(
                    hasMicPermission = hasMicPermission,
                    isAccessibilityConnected = isAccessibilityConnected,
                    asrEngineMode = asrEngineMode,
                    triggerMode = triggerMode,
                    onRequestMicPermission = onRequestMicPermission,
                    onOpenAccessibilitySettings = onOpenAccessibilitySettings
                )
            }

            when (activeTab) {
                AppTab.DICTATE -> {
                    // Main Voice Dictation Studio Card + Scratchpad
                    VoiceDictationCard(
                        isRecording = isRecording,
                        isTranscribing = isInAppTranscribing,
                        recordingElapsedMs = recordingElapsedMs,
                        waveformLevels = waveformLevels,
                        livePartialText = livePartialText,
                        scratchpadText = scratchpadText,
                        statusBannerText = statusBannerText,
                        copiedScratchpad = copiedScratchpad,
                        onScratchpadChange = { scratchpadText = it },
                        onToggleDictation = { startOrStopInAppDictation() },
                        onCopyScratchpad = { copyText(scratchpadText) },
                        onClearScratchpad = {
                            scratchpadText = ""
                            baseScratchpadBeforeStream = ""
                            statusBannerText = null
                        }
                    )

                    // Language Selector Card
                    LanguageSelectorCard(
                        selectedLanguage = selectedLanguage,
                        onSelectLanguage = { coordinator.setSelectedLanguage(it) }
                    )

                    // Recent Dictations Preview (Top 3)
                    if (history.isNotEmpty()) {
                        RecentHistoryPreviewCard(
                            records = history.take(3),
                            onCopyRecord = { copyText(it.polishedTranscript) },
                            onViewAll = { activeTab = AppTab.HISTORY }
                        )
                    }
                }

                AppTab.SETTINGS -> {
                    HardwareTriggerSettingsCard(
                        triggerMode = triggerMode,
                        holdThresholdMs = holdThresholdMs,
                        isAccessibilityConnected = isAccessibilityConnected,
                        onSelectTriggerMode = { coordinator.setTriggerMode(it) },
                        onSelectHoldThreshold = { coordinator.setHoldThresholdMs(it) },
                        onOpenAccessibilitySettings = onOpenAccessibilitySettings
                    )

                    S1MiniSettingsCard(
                        isEnabled = isS1MiniEnabled,
                        selectedStyle = s1Style,
                        selectedStructure = s1Structure,
                        activeForegroundPkg = activeForegroundPkg,
                        onToggleEnabled = { coordinator.setS1MiniEnabled(it) },
                        onSelectStyle = { coordinator.setS1Style(it) },
                        onSelectStructure = { coordinator.setS1Structure(it) }
                    )

                    ModelManagementCard(
                        asrEngineMode = asrEngineMode,
                        isWhisperLoaded = isWhisperLoaded,
                        onSelectEngineMode = { coordinator.setAsrEngineMode(it) }
                    )
                }

                AppTab.HISTORY -> {
                    FullHistoryCard(
                        records = history,
                        onCopyRecord = { copyText(it.polishedTranscript) },
                        onClearHistory = { coordinator.clearHistory() }
                    )
                }
            }

            Spacer(modifier = Modifier.height(28.dp))
        }
    }
}

// ============================================================================
// 1. Monitor YT Lo-Fi Header Bar + Ink Ticker Strip
// ============================================================================
@Composable
private fun LofiHeaderBar(
    asrEngineMode: SayItFlowCoordinator.AsrEngineMode,
    isWhisperLoaded: Boolean,
    isSystemReady: Boolean,
    triggerMode: SayItFlowCoordinator.TriggerMode,
    isS1MiniEnabled: Boolean,
    onClickStatus: () -> Unit,
    onClickTicker: () -> Unit = {}
) {
    val statusFill = if (isWhisperLoaded) AccentTeal else AccentYellow
    val statusLabel = when (asrEngineMode) {
        SayItFlowCoordinator.AsrEngineMode.SENSE_VOICE_OFFLINE ->
            if (isWhisperLoaded) "Whisper INT8" else "Warming INT8..."
        SayItFlowCoordinator.AsrEngineMode.INSTANT_STREAMING -> "SODA + Whisper"
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(PaperBg)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Left Brand Mark: Monitor YT playful boxed badge + bold grotesque title
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(34.dp)
                        .lofiCard(
                            backgroundColor = AccentYellow,
                            cornerRadius = 10.dp,
                            borderWidth = 2.dp,
                            shadowOffset = 2.5.dp
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(2.5.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .width(3.dp)
                                .height(9.dp)
                                .clip(RoundedCornerShape(1.5.dp))
                                .background(Ink)
                        )
                        Box(
                            modifier = Modifier
                                .width(3.dp)
                                .height(16.dp)
                                .clip(RoundedCornerShape(1.5.dp))
                                .background(Ink)
                        )
                        Box(
                            modifier = Modifier
                                .width(3.dp)
                                .height(11.dp)
                                .clip(RoundedCornerShape(1.5.dp))
                                .background(Ink)
                        )
                    }
                }

                Column {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = "SayItFlow",
                            color = Ink,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.ExtraBold,
                            letterSpacing = (-0.5).sp
                        )
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(PaperDeep)
                                .border(1.5.dp, Ink, RoundedCornerShape(6.dp))
                                .padding(horizontal = 6.dp, vertical = 1.dp)
                        ) {
                            Text(
                                text = "LO-FI VOICE",
                                color = Ink,
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = FontFamily.Monospace
                            )
                        }
                    }
                }
            }

            // Right Status Pill (Neo-brutalist pill with hard offset shadow)
            Row(
                modifier = Modifier
                    .lofiPill(
                        backgroundColor = statusFill,
                        borderWidth = 2.dp,
                        shadowOffset = 2.5.dp
                    )
                    .clickable { onClickStatus() }
                    .padding(horizontal = 11.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(7.dp)
                        .clip(CircleShape)
                        .background(Ink)
                )
                Text(
                    text = statusLabel,
                    color = Ink,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.ExtraBold,
                    fontFamily = FontFamily.Monospace
                )
            }
        }

        // Signature Monitor YT Ink Ticker Strip (--ink background, --paper text, --red & --yellow accents)
        HorizontalDivider(thickness = 2.dp, color = Ink)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Ink)
                .clickable { onClickTicker() }
                .padding(horizontal = 16.dp, vertical = 7.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(7.dp)
                        .clip(CircleShape)
                        .background(if (isSystemReady) AccentTeal else AccentRed)
                )
                Text(
                    text = if (isSystemReady) {
                        "READY · ${triggerMode.title.uppercase()} + A11Y SHORTCUT"
                    } else {
                        "SETUP NEEDED · TAP TO ENABLE PERMISSIONS"
                    },
                    color = PaperBg,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 0.3.sp
                )
            }
            Text(
                text = if (isS1MiniEnabled) "★ S1-MINI CLEANUP" else "DIRECT ASR",
                color = AccentYellow,
                fontSize = 10.5.sp,
                fontWeight = FontWeight.ExtraBold,
                fontFamily = FontFamily.Monospace
            )
        }
        HorizontalDivider(thickness = 2.dp, color = Ink)
    }
}

// ============================================================================
// 2. Lo-Fi Neo-Brutalist Segmented Navigation
// ============================================================================
@Composable
private fun LofiTabRow(
    activeTab: AppTab,
    historyCount: Int,
    onSelectTab: (AppTab) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .lofiCard(
                backgroundColor = PaperDeep,
                cornerRadius = 14.dp,
                borderWidth = 2.dp,
                shadowOffset = 3.5.dp
            )
            .padding(5.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        AppTab.entries.forEach { tab ->
            val isSelected = tab == activeTab
            val label = if (tab == AppTab.HISTORY && historyCount > 0) {
                "${tab.title} ($historyCount)"
            } else {
                tab.title
            }
            Row(
                modifier = Modifier
                    .weight(1f)
                    .height(38.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (isSelected) AccentYellow else Color.Transparent)
                    .then(
                        if (isSelected) {
                            Modifier.border(2.dp, Ink, RoundedCornerShape(10.dp))
                        } else {
                            Modifier
                        }
                    )
                    .clickable { onSelectTab(tab) },
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = tab.icon,
                    contentDescription = null,
                    tint = if (isSelected) Ink else InkSoft,
                    modifier = Modifier.size(15.dp)
                )
                Spacer(modifier = Modifier.width(5.dp))
                Text(
                    text = label,
                    color = if (isSelected) Ink else InkSoft,
                    fontSize = 12.5.sp,
                    fontWeight = if (isSelected) FontWeight.ExtraBold else FontWeight.SemiBold
                )
            }
        }
    }
}

// ============================================================================
// 3. Setup Checklist Card (Warm Butter sticky-note card)
// ============================================================================
@Composable
private fun SetupChecklistCard(
    hasMicPermission: Boolean,
    isAccessibilityConnected: Boolean,
    asrEngineMode: SayItFlowCoordinator.AsrEngineMode,
    triggerMode: SayItFlowCoordinator.TriggerMode,
    onRequestMicPermission: () -> Unit,
    onOpenAccessibilitySettings: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .lofiCard(
                backgroundColor = CardButter,
                cornerRadius = 16.dp,
                borderWidth = 2.dp,
                shadowOffset = 4.dp
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(AccentYellow)
                        .border(1.5.dp, Ink, RoundedCornerShape(6.dp))
                        .padding(horizontal = 8.dp, vertical = 2.dp)
                ) {
                    Text(
                        text = "QUICK SETUP",
                        color = Ink,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.ExtraBold,
                        fontFamily = FontFamily.Monospace
                    )
                }
                Text(
                    text = "System Checklist",
                    color = Ink,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.ExtraBold
                )
            }
            Text(
                text = "${listOf(hasMicPermission, isAccessibilityConnected, true).count { it }}/3 DONE",
                color = InkSoft,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace
            )
        }

        HorizontalDivider(thickness = 1.5.dp, color = Ink.copy(alpha = 0.15f))

        ChecklistRow(
            stepNumber = "1",
            stepColor = AccentRed,
            title = "Microphone Permission",
            subtitle = if (hasMicPermission) "Granted (16 kHz PCM capture)" else "Required for voice capture",
            isDone = hasMicPermission,
            actionLabel = "Grant",
            onAction = onRequestMicPermission
        )

        ChecklistRow(
            stepNumber = "2",
            stepColor = AccentTeal,
            title = "Global Push-to-Talk Service",
            subtitle = if (isAccessibilityConnected) {
                "Active (${triggerMode.title} + Accessibility Shortcut)"
            } else {
                "Enable SayItFlow in Accessibility Settings"
            },
            isDone = isAccessibilityConnected,
            actionLabel = "Enable",
            onAction = onOpenAccessibilitySettings
        )

        val engineSub = when (asrEngineMode) {
            SayItFlowCoordinator.AsrEngineMode.SENSE_VOICE_OFFLINE ->
                "Bundled Whisper-Tiny INT8 (39 MB · Ready Out of the Box)"
            SayItFlowCoordinator.AsrEngineMode.INSTANT_STREAMING ->
                "Google SODA Live + Whisper-Tiny INT8 Hybrid Ready"
        }
        ChecklistRow(
            stepNumber = "3",
            stepColor = AccentSky,
            title = "Speech-to-Text Engine",
            subtitle = engineSub,
            isDone = true,
            actionLabel = "Ready",
            onAction = {}
        )
    }
}

@Composable
private fun ChecklistRow(
    stepNumber: String,
    stepColor: Color,
    title: String,
    subtitle: String,
    isDone: Boolean,
    actionLabel: String,
    onAction: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .clickable { onAction() }
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            modifier = Modifier.weight(1f),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(if (isDone) AccentTeal else stepColor)
                    .border(2.dp, Ink, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                if (isDone) {
                    Icon(
                        imageVector = Icons.Rounded.Check,
                        contentDescription = null,
                        tint = Ink,
                        modifier = Modifier.size(15.dp)
                    )
                } else {
                    Text(
                        text = stepNumber,
                        color = if (stepColor == AccentRed) CardWhite else Ink,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.ExtraBold
                    )
                }
            }
            Column {
                Text(
                    text = title,
                    color = Ink,
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = subtitle,
                    color = InkSoft,
                    fontSize = 11.5.sp
                )
            }
        }

        if (!isDone) {
            Box(
                modifier = Modifier
                    .lofiPill(
                        backgroundColor = AccentRed,
                        borderWidth = 2.dp,
                        shadowOffset = 2.dp
                    )
                    .clickable { onAction() }
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                Text(
                    text = actionLabel,
                    color = CardWhite,
                    fontSize = 11.5.sp,
                    fontWeight = FontWeight.ExtraBold
                )
            }
        }
    }
}

// ============================================================================
// 4. Primary Voice Dictation Studio + Scratchpad (Monitor YT Stakeout Card)
// ============================================================================
@Composable
private fun VoiceDictationCard(
    isRecording: Boolean,
    isTranscribing: Boolean,
    recordingElapsedMs: Long,
    waveformLevels: FloatArray,
    livePartialText: String,
    scratchpadText: String,
    statusBannerText: String?,
    copiedScratchpad: Boolean,
    onScratchpadChange: (String) -> Unit,
    onToggleDictation: () -> Unit,
    onCopyScratchpad: () -> Unit,
    onClearScratchpad: () -> Unit
) {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.55f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseAlpha"
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .lofiCard(
                backgroundColor = CardWhite,
                cornerRadius = 18.dp,
                borderWidth = 2.5.dp,
                shadowOffset = 5.dp
            )
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // Card Header with Monitor YT Tag Pill
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(end = 10.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (isRecording) AccentRed else AccentYellow)
                            .border(1.5.dp, Ink, RoundedCornerShape(6.dp))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = if (isRecording) "● LIVE MIC" else "STUDIO",
                            color = if (isRecording) CardWhite else Ink,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.ExtraBold,
                            fontFamily = FontFamily.Monospace
                        )
                    }
                    Text(
                        text = "Voice Dictation",
                        color = Ink,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.ExtraBold,
                        letterSpacing = (-0.4).sp
                    )
                }
                Text(
                    text = "Tap button below or hold Volume Down (0.4s) in any app",
                    color = InkSoft,
                    fontSize = 12.sp
                )
            }

            // Elapsed timer / sample rate tag
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (isRecording) CardPeach else PaperBg)
                    .border(2.dp, Ink, RoundedCornerShape(8.dp))
                    .padding(horizontal = 9.dp, vertical = 4.dp)
            ) {
                val badgeText = when {
                    isRecording -> String.format(Locale.US, "REC %.1fs", recordingElapsedMs / 1000.0)
                    isTranscribing -> "DECODING"
                    else -> "16 kHz"
                }
                Text(
                    text = badgeText,
                    color = if (isRecording) AccentRedDeep else Ink,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.ExtraBold,
                    fontFamily = FontFamily.Monospace
                )
            }
        }

        // Lo-Fi Acoustic Waveform Monitor Box (--paper-deep with 2dp ink border)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(68.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(if (isRecording) CardButter else PaperBg)
                .border(2.dp, Ink, RoundedCornerShape(12.dp))
                .padding(horizontal = 14.dp, vertical = 10.dp),
            contentAlignment = Alignment.Center
        ) {
            LofiWaveformCanvas(
                isRecording = isRecording,
                isTranscribing = isTranscribing,
                levels = waveformLevels,
                pulseAlpha = pulseAlpha
            )
        }

        // Live streaming / Whisper incremental preview while speaking
        AnimatedVisibility(
            visible = isRecording && livePartialText.isNotBlank(),
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(CardMint)
                    .border(1.5.dp, Ink, RoundedCornerShape(10.dp))
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(7.dp)
                        .clip(CircleShape)
                        .background(AccentRed)
                )
                Text(
                    text = livePartialText,
                    color = Ink,
                    fontSize = 12.5.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        // Primary Monitor YT Coral-Red Pill CTA Button (.btn .btn-primary)
        val buttonBg = when {
            isRecording -> Ink
            isTranscribing -> AccentYellow
            else -> AccentRed
        }
        val buttonTextColor = when {
            isRecording -> PaperBg
            isTranscribing -> Ink
            else -> CardWhite
        }
        val buttonLabel = when {
            isRecording -> "Stop & Transcribe Now"
            isTranscribing -> "Transcribing Speech..."
            else -> "Start Voice Dictation"
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .lofiPill(
                    backgroundColor = buttonBg,
                    borderWidth = 2.5.dp,
                    shadowOffset = 4.dp
                )
                .clickable(enabled = !isTranscribing) { onToggleDictation() }
                .padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = when {
                    isRecording -> Icons.Rounded.Stop
                    isTranscribing -> Icons.Rounded.GraphicEq
                    else -> Icons.Rounded.Mic
                },
                contentDescription = null,
                tint = buttonTextColor,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = buttonLabel,
                color = buttonTextColor,
                fontSize = 15.5.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = (-0.2).sp
            )
        }

        // Status feedback pill banner
        AnimatedVisibility(
            visible = !statusBannerText.isNullOrBlank(),
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(CardMint)
                    .border(1.5.dp, Ink, RoundedCornerShape(10.dp))
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(7.dp)
                        .clip(CircleShape)
                        .background(Ink)
                )
                Text(
                    text = statusBannerText.orEmpty(),
                    color = Ink,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        HorizontalDivider(thickness = 2.dp, color = Ink.copy(alpha = 0.12f))

        // Live Dictation Note / Scratchpad
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(5.dp))
                        .background(AccentTeal)
                        .border(1.5.dp, Ink, RoundedCornerShape(5.dp))
                        .padding(horizontal = 6.dp, vertical = 1.dp)
                ) {
                    Text(
                        text = "NOTE",
                        color = Ink,
                        fontSize = 9.5.sp,
                        fontWeight = FontWeight.ExtraBold,
                        fontFamily = FontFamily.Monospace
                    )
                }
                Text(
                    text = "Dictation Output",
                    color = Ink,
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.ExtraBold
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // Copy Ghost Pill Button
                Row(
                    modifier = Modifier
                        .lofiPill(
                            backgroundColor = if (copiedScratchpad) AccentTeal else PaperBg,
                            borderWidth = 1.5.dp,
                            shadowOffset = 2.dp
                        )
                        .clickable { onCopyScratchpad() }
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = if (copiedScratchpad) Icons.Rounded.Check else Icons.Rounded.ContentCopy,
                        contentDescription = "Copy",
                        tint = Ink,
                        modifier = Modifier.size(13.dp)
                    )
                    Text(
                        text = if (copiedScratchpad) "Copied!" else "Copy",
                        color = Ink,
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.ExtraBold
                    )
                }

                if (scratchpadText.isNotBlank()) {
                    Row(
                        modifier = Modifier
                            .lofiPill(
                                backgroundColor = CardPeach,
                                borderWidth = 1.5.dp,
                                shadowOffset = 2.dp
                            )
                            .clickable { onClearScratchpad() }
                            .padding(horizontal = 10.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.DeleteOutline,
                            contentDescription = "Clear",
                            tint = Ink,
                            modifier = Modifier.size(13.dp)
                        )
                        Text(
                            text = "Clear",
                            color = Ink,
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.ExtraBold
                        )
                    }
                }
            }
        }

        // Editable Paper Note Pad
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(114.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(CardButter)
                .border(2.dp, Ink, RoundedCornerShape(12.dp))
                .padding(12.dp)
        ) {
            if (scratchpadText.isEmpty()) {
                Text(
                    text = "Tap 'Start Voice Dictation' above or hold Volume Down anywhere on your phone — your transcribed note lands right here...",
                    color = InkMuted,
                    fontSize = 13.sp,
                    lineHeight = 19.sp
                )
            }
            BasicTextField(
                value = scratchpadText,
                onValueChange = onScratchpadChange,
                textStyle = TextStyle(
                    color = Ink,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    lineHeight = 20.sp
                ),
                cursorBrush = SolidColor(AccentRed),
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}

@Composable
private fun LofiWaveformCanvas(
    isRecording: Boolean,
    isTranscribing: Boolean,
    levels: FloatArray,
    pulseAlpha: Float
) {
    val animTransition = rememberInfiniteTransition(label = "wave")
    val phase by animTransition.animateFloat(
        initialValue = 0f,
        targetValue = 6.28318f,
        animationSpec = infiniteRepeatable(
            animation = tween(1100, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "phase"
    )

    Canvas(modifier = Modifier.fillMaxSize()) {
        val barCount = 28
        val gap = 4.dp.toPx()
        val totalGaps = (barCount - 1) * gap
        val barWidth = ((size.width - totalGaps) / barCount).coerceAtLeast(3.dp.toPx())
        val centerY = size.height / 2f
        val maxBarH = size.height * 0.88f

        for (i in 0 until barCount) {
            val fraction = when {
                isRecording && levels.isNotEmpty() -> {
                    val idx = (i * levels.size) / barCount
                    val raw = levels[idx.coerceIn(0, levels.lastIndex)]
                    val waveMod = 0.08f * sin(phase + i * 0.4f)
                    (raw + waveMod).coerceIn(0.12f, 1.0f)
                }
                isTranscribing -> {
                    val wave = ((sin(phase * 2f - i * 0.35f) + 1f) * 0.5f)
                    (0.18f + 0.60f * wave).coerceIn(0.15f, 0.90f)
                }
                else -> 0.15f
            }

            val barH = max(5.dp.toPx(), fraction * maxBarH)
            val x = i * (barWidth + gap)
            val top = centerY - barH / 2f

            val color = when {
                isRecording -> if (fraction > 0.32f) AccentRed.copy(alpha = pulseAlpha) else Ink
                isTranscribing -> AccentTeal
                else -> Ink.copy(alpha = 0.28f)
            }

            drawRoundRect(
                color = color,
                topLeft = Offset(x, top),
                size = Size(barWidth, barH),
                cornerRadius = CornerRadius(barWidth / 2f, barWidth / 2f)
            )
        }
    }
}

// ============================================================================
// 5. Language Selector Card (Soft Mint Catch Card)
// ============================================================================
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LanguageSelectorCard(
    selectedLanguage: String,
    onSelectLanguage: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .lofiCard(
                backgroundColor = CardMint,
                cornerRadius = 16.dp,
                borderWidth = 2.dp,
                shadowOffset = 4.dp
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "Dictation Language",
                    color = Ink,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.ExtraBold
                )
                Text(
                    text = "OpenAI Whisper-Tiny INT8 multilingual + Roman Hinglish",
                    color = InkSoft,
                    fontSize = 12.sp
                )
            }
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(CardWhite)
                    .border(1.5.dp, Ink, RoundedCornerShape(6.dp))
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text(
                    text = selectedLanguage.uppercase(),
                    color = Ink,
                    fontSize = 10.5.sp,
                    fontWeight = FontWeight.ExtraBold,
                    fontFamily = FontFamily.Monospace
                )
            }
        }

        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            SayItFlowCoordinator.SUPPORTED_LANGUAGES.forEach { lang ->
                val isSelected = lang.code == selectedLanguage
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(if (isSelected) Ink else CardWhite)
                        .border(1.5.dp, Ink, RoundedCornerShape(999.dp))
                        .clickable { onSelectLanguage(lang.code) }
                        .padding(horizontal = 11.dp, vertical = 6.dp)
                ) {
                    Text(
                        text = "${lang.flag} ${lang.name}",
                        color = if (isSelected) PaperBg else Ink,
                        fontSize = 11.5.sp,
                        fontWeight = if (isSelected) FontWeight.ExtraBold else FontWeight.SemiBold
                    )
                }
            }
        }
    }
}

// ============================================================================
// 6. Recent History Preview & Full History Cards
// ============================================================================
@Composable
private fun RecentHistoryPreviewCard(
    records: List<SayItFlowCoordinator.DictationRecord>,
    onCopyRecord: (SayItFlowCoordinator.DictationRecord) -> Unit,
    onViewAll: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .lofiCard(
                backgroundColor = PaperDeep,
                cornerRadius = 16.dp,
                borderWidth = 2.dp,
                shadowOffset = 4.dp
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Recent Dictations",
                color = Ink,
                fontSize = 15.sp,
                fontWeight = FontWeight.ExtraBold
            )
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(AccentYellow)
                    .border(1.5.dp, Ink, RoundedCornerShape(999.dp))
                    .clickable { onViewAll() }
                    .padding(horizontal = 10.dp, vertical = 4.dp)
            ) {
                Text(
                    text = "View All →",
                    color = Ink,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.ExtraBold
                )
            }
        }

        records.forEachIndexed { idx, record ->
            val noteTint = when (idx % 3) {
                0 -> CardButter
                1 -> CardMint
                else -> CardPeach
            }
            HistoryItemRow(
                record = record,
                backgroundColor = noteTint,
                onCopy = { onCopyRecord(record) }
            )
        }
    }
}

@Composable
private fun FullHistoryCard(
    records: List<SayItFlowCoordinator.DictationRecord>,
    onCopyRecord: (SayItFlowCoordinator.DictationRecord) -> Unit,
    onClearHistory: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .lofiCard(
                backgroundColor = CardWhite,
                cornerRadius = 16.dp,
                borderWidth = 2.dp,
                shadowOffset = 4.dp
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "Dictation History",
                    color = Ink,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.ExtraBold
                )
                Text(
                    text = "${records.size} transcripts persisted locally on your phone",
                    color = InkSoft,
                    fontSize = 12.sp
                )
            }
            if (records.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .lofiPill(
                            backgroundColor = CardPeach,
                            borderWidth = 1.5.dp,
                            shadowOffset = 2.dp
                        )
                        .clickable { onClearHistory() }
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.DeleteOutline,
                        contentDescription = null,
                        tint = Ink,
                        modifier = Modifier.size(13.dp)
                    )
                    Text(
                        text = "Clear All",
                        color = Ink,
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.ExtraBold
                    )
                }
            }
        }

        if (records.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(PaperBg)
                    .border(2.dp, Ink, RoundedCornerShape(12.dp))
                    .padding(vertical = 28.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "No dictations recorded yet.",
                    color = InkSoft,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        } else {
            records.forEachIndexed { idx, record ->
                val noteTint = when (idx % 3) {
                    0 -> CardButter
                    1 -> CardMint
                    else -> CardPeach
                }
                HistoryItemRow(
                    record = record,
                    backgroundColor = noteTint,
                    onCopy = { onCopyRecord(record) }
                )
            }
        }
    }
}

@Composable
private fun HistoryItemRow(
    record: SayItFlowCoordinator.DictationRecord,
    backgroundColor: Color,
    onCopy: () -> Unit
) {
    val timeFmt = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val appName = SayItFlowCoordinator.friendlyAppName(record.targetPackage)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .lofiCard(
                backgroundColor = backgroundColor,
                cornerRadius = 12.dp,
                borderWidth = 2.dp,
                shadowOffset = 3.dp
            )
            .clickable { onCopy() }
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(5.dp))
                        .background(PaperBg)
                        .border(1.5.dp, Ink, RoundedCornerShape(5.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text(
                        text = appName.uppercase(),
                        color = Ink,
                        fontSize = 9.5.sp,
                        fontWeight = FontWeight.ExtraBold,
                        fontFamily = FontFamily.Monospace
                    )
                }
                Text(
                    text = "⚡ ${record.elapsedMs}ms · ${timeFmt.format(Date(record.timestampMs))}",
                    color = InkSoft,
                    fontSize = 10.5.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace
                )
            }
            Icon(
                imageVector = Icons.Rounded.ContentCopy,
                contentDescription = "Copy",
                tint = Ink,
                modifier = Modifier.size(14.dp)
            )
        }

        Text(
            text = record.polishedTranscript,
            color = Ink,
            fontSize = 13.5.sp,
            fontWeight = FontWeight.SemiBold,
            lineHeight = 19.sp
        )
    }
}

// ============================================================================
// 7. Settings Tab Cards (Hardware Trigger, S1-Mini Cleanup, Model Status)
// ============================================================================
@Composable
private fun HardwareTriggerSettingsCard(
    triggerMode: SayItFlowCoordinator.TriggerMode,
    holdThresholdMs: Long,
    isAccessibilityConnected: Boolean,
    onSelectTriggerMode: (SayItFlowCoordinator.TriggerMode) -> Unit,
    onSelectHoldThreshold: (Long) -> Unit,
    onOpenAccessibilitySettings: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .lofiCard(
                backgroundColor = CardButter,
                cornerRadius = 16.dp,
                borderWidth = 2.dp,
                shadowOffset = 4.dp
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .clickable { onOpenAccessibilitySettings() }
                .padding(vertical = 2.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Hardware & Accessibility Trigger",
                    color = Ink,
                    fontSize = 15.5.sp,
                    fontWeight = FontWeight.ExtraBold
                )
                Text(
                    text = "Hold physical Volume button or tap the Android Accessibility button in any app",
                    color = InkSoft,
                    fontSize = 12.sp
                )
            }
            Spacer(modifier = Modifier.width(8.dp))
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(if (isAccessibilityConnected) AccentTeal else AccentRed)
                    .border(1.5.dp, Ink, RoundedCornerShape(999.dp))
                    .clickable { onOpenAccessibilitySettings() }
                    .padding(horizontal = 10.dp, vertical = 4.dp)
            ) {
                Text(
                    text = if (isAccessibilityConnected) "ACTIVE" else "ENABLE",
                    color = if (isAccessibilityConnected) Ink else CardWhite,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.ExtraBold,
                    fontFamily = FontFamily.Monospace
                )
            }
        }

        SayItFlowCoordinator.TriggerMode.entries.forEach { mode ->
            val selected = mode == triggerMode
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (selected) CardWhite else PaperBg)
                    .border(
                        width = if (selected) 2.dp else 1.5.dp,
                        color = Ink,
                        shape = RoundedCornerShape(10.dp)
                    )
                    .clickable { onSelectTriggerMode(mode) }
                    .padding(12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = mode.title,
                        color = Ink,
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.ExtraBold
                    )
                    Text(
                        text = mode.subtitle,
                        color = InkSoft,
                        fontSize = 11.5.sp
                    )
                }
                Box(
                    modifier = Modifier
                        .size(22.dp)
                        .clip(CircleShape)
                        .background(if (selected) AccentYellow else PaperDeep)
                        .border(1.5.dp, Ink, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    if (selected) {
                        Icon(
                            imageVector = Icons.Rounded.Check,
                            contentDescription = null,
                            tint = Ink,
                            modifier = Modifier.size(14.dp)
                        )
                    }
                }
            }
        }

        Text(
            text = "Hold Duration Threshold",
            color = Ink,
            fontSize = 12.5.sp,
            fontWeight = FontWeight.ExtraBold
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            listOf(400L to "400ms (Fast)", 500L to "500ms", 650L to "650ms").forEach { (ms, label) ->
                val isSelected = holdThresholdMs == ms
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(999.dp))
                        .background(if (isSelected) Ink else CardWhite)
                        .border(1.5.dp, Ink, RoundedCornerShape(999.dp))
                        .clickable { onSelectHoldThreshold(ms) }
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = label,
                        color = if (isSelected) PaperBg else Ink,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.ExtraBold
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun S1MiniSettingsCard(
    isEnabled: Boolean,
    selectedStyle: S1MiniEngine.Style,
    selectedStructure: S1MiniEngine.Structure,
    activeForegroundPkg: String,
    onToggleEnabled: (Boolean) -> Unit,
    onSelectStyle: (S1MiniEngine.Style) -> Unit,
    onSelectStructure: (S1MiniEngine.Structure) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .lofiCard(
                backgroundColor = CardMint,
                cornerRadius = 16.dp,
                borderWidth = 2.dp,
                shadowOffset = 4.dp
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = "S1-mini Spoken Cleanup",
                        color = Ink,
                        fontSize = 15.5.sp,
                        fontWeight = FontWeight.ExtraBold
                    )
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(5.dp))
                            .background(AccentYellow)
                            .border(1.5.dp, Ink, RoundedCornerShape(5.dp))
                            .padding(horizontal = 6.dp, vertical = 1.dp)
                    ) {
                        Text(
                            text = "INSTANT <2ms",
                            color = Ink,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.ExtraBold,
                            fontFamily = FontFamily.Monospace
                        )
                    }
                }
                Text(
                    text = "Strips 'um/uh' fillers, stutters & formats by active app (zero extra download)",
                    color = InkSoft,
                    fontSize = 11.5.sp
                )
            }

            Switch(
                checked = isEnabled,
                onCheckedChange = onToggleEnabled,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Ink,
                    checkedTrackColor = AccentYellow,
                    checkedBorderColor = Ink,
                    uncheckedThumbColor = InkSoft,
                    uncheckedTrackColor = PaperBg,
                    uncheckedBorderColor = Ink
                )
            )
        }

        if (isEnabled) {
            HorizontalDivider(thickness = 1.5.dp, color = Ink.copy(alpha = 0.15f))

            Text(
                text = "Tone Style · Active: ${SayItFlowCoordinator.contextBadgeForPackage(activeForegroundPkg)}",
                color = Ink,
                fontSize = 12.sp,
                fontWeight = FontWeight.ExtraBold
            )

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                S1MiniEngine.Style.entries.forEach { style ->
                    val selected = style == selectedStyle
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .background(if (selected) Ink else CardWhite)
                            .border(1.5.dp, Ink, RoundedCornerShape(999.dp))
                            .clickable { onSelectStyle(style) }
                            .padding(horizontal = 11.dp, vertical = 6.dp)
                    ) {
                        Text(
                            text = style.label,
                            color = if (selected) PaperBg else Ink,
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.ExtraBold
                        )
                    }
                }
            }

            Text(
                text = "Output Structure",
                color = Ink,
                fontSize = 12.sp,
                fontWeight = FontWeight.ExtraBold
            )

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                S1MiniEngine.Structure.entries.forEach { structure ->
                    val selected = structure == selectedStructure
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .background(if (selected) Ink else CardWhite)
                            .border(1.5.dp, Ink, RoundedCornerShape(999.dp))
                            .clickable { onSelectStructure(structure) }
                            .padding(horizontal = 11.dp, vertical = 6.dp)
                    ) {
                        Text(
                            text = structure.label,
                            color = if (selected) PaperBg else Ink,
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.ExtraBold
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ModelManagementCard(
    asrEngineMode: SayItFlowCoordinator.AsrEngineMode,
    isWhisperLoaded: Boolean,
    onSelectEngineMode: (SayItFlowCoordinator.AsrEngineMode) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .lofiCard(
                backgroundColor = CardPeach,
                cornerRadius = 16.dp,
                borderWidth = 2.dp,
                shadowOffset = 4.dp
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Speech-to-Text Engine",
                color = Ink,
                fontSize = 15.5.sp,
                fontWeight = FontWeight.ExtraBold
            )
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(if (isWhisperLoaded) AccentTeal else AccentYellow)
                    .border(1.5.dp, Ink, RoundedCornerShape(6.dp))
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text(
                    text = if (isWhisperLoaded) "WHISPER IN RAM" else "WARMING UP",
                    color = Ink,
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.ExtraBold,
                    fontFamily = FontFamily.Monospace
                )
            }
        }

        SayItFlowCoordinator.AsrEngineMode.entries.forEach { mode ->
            val selected = mode == asrEngineMode
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (selected) CardWhite else PaperBg)
                    .border(
                        width = if (selected) 2.dp else 1.5.dp,
                        color = Ink,
                        shape = RoundedCornerShape(10.dp)
                    )
                    .clickable { onSelectEngineMode(mode) }
                    .padding(12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = mode.title,
                            color = Ink,
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.ExtraBold
                        )
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(5.dp))
                                .background(if (selected) AccentTeal else AccentYellow)
                                .border(1.5.dp, Ink, RoundedCornerShape(5.dp))
                                .padding(horizontal = 6.dp, vertical = 1.dp)
                        ) {
                            Text(
                                text = mode.badge,
                                color = Ink,
                                fontSize = 9.sp,
                                fontWeight = FontWeight.ExtraBold,
                                fontFamily = FontFamily.Monospace
                            )
                        }
                    }
                    Text(
                        text = mode.subtitle,
                        color = InkSoft,
                        fontSize = 11.5.sp
                    )
                }
                Box(
                    modifier = Modifier
                        .size(22.dp)
                        .clip(CircleShape)
                        .background(if (selected) AccentYellow else PaperDeep)
                        .border(1.5.dp, Ink, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    if (selected) {
                        Icon(
                            imageVector = Icons.Rounded.Check,
                            contentDescription = null,
                            tint = Ink,
                            modifier = Modifier.size(14.dp)
                        )
                    }
                }
            }
        }
    }
}
