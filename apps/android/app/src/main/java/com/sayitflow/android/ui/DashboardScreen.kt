package com.sayitflow.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sayitflow.android.SayItFlowCoordinator
import com.sayitflow.android.ml.ModelDownloadManager
import com.sayitflow.android.ml.S1MiniEngine
import kotlinx.coroutines.launch
import kotlin.math.roundToLong

private val BgCanvas = Color(0xFF09090B)
private val BgCard = Color(0xFF121215)
private val BgSubtle = Color(0xFF18181C)
private val BorderColor = Color(0xFF27272A)
private val TextPrimary = Color(0xFFFAFAFA)
private val TextSecondary = Color(0xFFA1A1AA)
private val TextMuted = Color(0xFF71717A)

@Composable
fun DashboardScreen(
    coordinator: SayItFlowCoordinator,
    hasMicPermission: Boolean,
    onRequestMicPermission: () -> Unit,
    onOpenAccessibilitySettings: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    val accessibilityConnected by coordinator.accessibilityConnected.collectAsState()
    val vozStatus by coordinator.downloadManager.vozStatus.collectAsState()
    val s1Status by coordinator.downloadManager.s1Status.collectAsState()
    val vozLoaded by coordinator.vozEngine.isLoaded.collectAsState()
    val isRecording by coordinator.audioCapture.isRecording.collectAsState()
    val triggerMode by coordinator.triggerMode.collectAsState()
    val holdThresholdMs by coordinator.holdThresholdMs.collectAsState()
    val selectedLanguage by coordinator.selectedLanguage.collectAsState()
    val s1Enabled by coordinator.s1MiniEnabled.collectAsState()
    val s1Style by coordinator.s1Style.collectAsState()
    val s1Structure by coordinator.s1Structure.collectAsState()
    val history by coordinator.history.collectAsState()

    var testBenchText by remember { mutableStateOf("") }
    var testBenchStatus by remember { mutableStateOf("Hold the button below (or Volume Down) to test Desert Ant Voz") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BgCanvas)
            .verticalScroll(scrollState)
            .padding(horizontal = 18.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // 1. Studio Header
        HeaderSection(vozLoaded = vozLoaded, onUnloadNow = {
            scope.launch { coordinator.vozEngine.unloadModels() }
        })

        // 2. System Permissions & Push-to-Talk Setup Card
        SystemSetupCard(
            hasMicPermission = hasMicPermission,
            accessibilityConnected = accessibilityConnected,
            onRequestMicPermission = onRequestMicPermission,
            onOpenAccessibilitySettings = onOpenAccessibilitySettings
        )

        // 3. Desert Ant Voz (`desert-ant-labs/voz`) Model Card
        ModelCard(
            title = "Desert Ant Voz",
            badge = "desert-ant-labs/voz • 25 LANGS • 384 MB",
            description = "FastConformer-TDT 0.6B ONNX FP16 with fused mel frontend & in-graph argmax decoder. Auto-unloads after 2m idle.",
            status = vozStatus,
            onDownload = { coordinator.downloadManager.startVozDownload() },
            onCancel = { coordinator.downloadManager.cancelVozDownload() },
            onDelete = {
                scope.launch {
                    coordinator.vozEngine.unloadModels()
                    coordinator.downloadManager.deleteVozModel()
                }
            }
        )

        // 4. S1-mini by Superwhisper Model & Polish Card
        S1MiniCard(
            status = s1Status,
            enabled = s1Enabled,
            style = s1Style,
            structure = s1Structure,
            onToggleEnabled = { coordinator.setS1MiniEnabled(it) },
            onSelectStyle = { coordinator.setS1Style(it) },
            onSelectStructure = { coordinator.setS1Structure(it) },
            onDownload = { coordinator.downloadManager.startS1MiniDownload() },
            onCancel = { coordinator.downloadManager.cancelS1MiniDownload() },
            onDelete = { coordinator.downloadManager.deleteS1MiniModel() }
        )

        // 5. Hardware Button Trigger & Language Configuration
        HardwareTriggerCard(
            selectedMode = triggerMode,
            holdThresholdMs = holdThresholdMs,
            selectedLanguage = selectedLanguage,
            onSelectMode = { coordinator.setTriggerMode(it) },
            onChangeHoldThreshold = { coordinator.setHoldThresholdMs(it) },
            onSelectLanguage = { coordinator.setSelectedLanguage(it) }
        )

        // 6. Live In-App Dictation Test Bench
        TestBenchCard(
            isRecording = isRecording,
            statusLabel = testBenchStatus,
            textValue = testBenchText,
            onTextChange = { testBenchText = it },
            onPressStart = {
                if (!hasMicPermission) {
                    onRequestMicPermission()
                    return@TestBenchCard
                }
                if (!coordinator.vozEngine.areModelFilesInstalled()) {
                    testBenchStatus = "Download Desert Ant Voz above first"
                    return@TestBenchCard
                }
                coordinator.vozEngine.warmUpAsync()
                if (coordinator.audioCapture.startRecording()) {
                    testBenchStatus = "Listening (16 kHz PCM)..."
                }
            },
            onPressRelease = {
                if (!coordinator.audioCapture.isRecording.value) return@TestBenchCard
                val samples = coordinator.audioCapture.stopRecording()
                if (samples.size < 2880) {
                    testBenchStatus = "Hold longer to speak"
                    return@TestBenchCard
                }
                testBenchStatus = "Transcribing with desert-ant-labs/voz..."
                scope.launch {
                    val t0 = System.currentTimeMillis()
                    try {
                        val raw = coordinator.vozEngine.transcribe(samples)
                        val polished = if (s1Enabled && (selectedLanguage == "auto" || selectedLanguage == "en")) {
                            coordinator.s1MiniEngine.polish(
                                rawTranscript = raw,
                                foregroundPackage = "com.sayitflow.android",
                                style = s1Style,
                                structure = s1Structure
                            )
                        } else {
                            raw
                        }
                        val elapsed = System.currentTimeMillis() - t0
                        if (polished.isNotBlank()) {
                            testBenchText = if (testBenchText.isBlank()) polished else "$testBenchText $polished"
                            testBenchStatus = "Done in ${elapsed}ms • 2m idle timer active"
                            coordinator.recordDictation(
                                SayItFlowCoordinator.DictationRecord(
                                    rawTranscript = raw,
                                    polishedTranscript = polished,
                                    targetPackage = "Test Bench",
                                    elapsedMs = elapsed
                                )
                            )
                        } else {
                            testBenchStatus = "No speech detected"
                        }
                    } catch (e: Exception) {
                        testBenchStatus = "Error: ${e.localizedMessage ?: "Failed"}"
                    }
                }
            }
        )

        // 7. Recent Dictation History
        if (history.isNotEmpty()) {
            HistorySection(history = history)
        }

        Spacer(modifier = Modifier.height(24.dp))
    }
}

@Composable
private fun HeaderSection(vozLoaded: Boolean, onUnloadNow: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "SayItFlow",
                    color = TextPrimary,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.width(8.dp))
                Box(
                    modifier = Modifier
                        .border(1.dp, BorderColor, RoundedCornerShape(6.dp))
                        .background(BgSubtle, RoundedCornerShape(6.dp))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = "PIXEL • v1.5.0",
                        color = TextSecondary,
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "100% On-Device Push-to-Talk • Zero Cloud • No Keyboard Switch",
                color = TextSecondary,
                fontSize = 12.sp
            )
        }

        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(16.dp))
                .border(1.dp, BorderColor, RoundedCornerShape(16.dp))
                .background(BgCard)
                .clickable(enabled = vozLoaded) { onUnloadNow() }
                .padding(horizontal = 10.dp, vertical = 6.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(7.dp)
                        .background(
                            if (vozLoaded) TextPrimary else TextMuted,
                            CircleShape
                        )
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = if (vozLoaded) "RAM Active (2m)" else "0 MB Standby",
                    color = if (vozLoaded) TextPrimary else TextSecondary,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }
    }
}

@Composable
private fun SystemSetupCard(
    hasMicPermission: Boolean,
    accessibilityConnected: Boolean,
    onRequestMicPermission: () -> Unit,
    onOpenAccessibilitySettings: () -> Unit
) {
    StudioCard {
        Text(
            text = "PIXEL SYSTEM INTEGRATION",
            color = TextMuted,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(10.dp))

        // Row 1: Microphone
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("Microphone Capture (16 kHz)", color = TextPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                Text(
                    if (hasMicPermission) "Granted • Ready for voice capture" else "Required for push-to-talk dictation",
                    color = TextSecondary,
                    fontSize = 12.sp
                )
            }
            if (!hasMicPermission) {
                Button(
                    onClick = onRequestMicPermission,
                    colors = ButtonDefaults.buttonColors(containerColor = TextPrimary, contentColor = BgCanvas)
                ) {
                    Text("Grant", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            } else {
                StatusPill("READY")
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Row 2: Accessibility Service (Volume Hold + Direct Text Injection)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("Global Volume Hold & Direct Inject", color = TextPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                Text(
                    if (accessibilityConnected) {
                        "Active • Hold Volume Down in any app to dictate"
                    } else {
                        "Enable 'SayItFlow Push-to-Talk' in Accessibility Settings"
                    },
                    color = TextSecondary,
                    fontSize = 12.sp
                )
            }
            Spacer(modifier = Modifier.width(8.dp))
            if (!accessibilityConnected) {
                Button(
                    onClick = onOpenAccessibilitySettings,
                    colors = ButtonDefaults.buttonColors(containerColor = TextPrimary, contentColor = BgCanvas)
                ) {
                    Text("Enable", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            } else {
                StatusPill("ACTIVE")
            }
        }
    }
}

@Composable
private fun ModelCard(
    title: String,
    badge: String,
    description: String,
    status: ModelDownloadManager.ModelStatus,
    onDownload: () -> Unit,
    onCancel: () -> Unit,
    onDelete: () -> Unit
) {
    StudioCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, color = TextPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    badge,
                    color = TextMuted,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
            if (status.isInstalled) {
                StatusPill("INSTALLED")
            }
        }

        Spacer(modifier = Modifier.height(8.dp))
        Text(description, color = TextSecondary, fontSize = 12.sp)
        Spacer(modifier = Modifier.height(12.dp))

        if (status.isDownloading) {
            LinearProgressIndicator(
                progress = { status.progressFraction },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .clip(RoundedCornerShape(3.dp)),
                color = TextPrimary,
                trackColor = BorderColor
            )
            Spacer(modifier = Modifier.height(6.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                val mbDone = status.downloadedBytes / (1024 * 1024)
                val mbTotal = status.totalBytes / (1024 * 1024)
                Text(
                    "Downloading ${status.currentFile} ($mbDone / $mbTotal MB)",
                    color = TextSecondary,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace
                )
                OutlinedButton(onClick = onCancel) {
                    Text("Pause", color = TextPrimary, fontSize = 12.sp)
                }
            }
        } else {
            status.errorMessage?.let { err ->
                Text("Error: $err", color = Color(0xFFF87171), fontSize = 12.sp)
                Spacer(modifier = Modifier.height(6.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (!status.isInstalled) {
                    Button(
                        onClick = onDownload,
                        colors = ButtonDefaults.buttonColors(containerColor = TextPrimary, contentColor = BgCanvas)
                    ) {
                        val resumeText = if (status.downloadedBytes > 0L) "Resume Download" else "Download Model"
                        Text(resumeText, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                } else {
                    OutlinedButton(onClick = onDelete) {
                        Text("Remove Model Files", color = TextSecondary, fontSize = 12.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun S1MiniCard(
    status: ModelDownloadManager.ModelStatus,
    enabled: Boolean,
    style: S1MiniEngine.Style,
    structure: S1MiniEngine.Structure,
    onToggleEnabled: (Boolean) -> Unit,
    onSelectStyle: (S1MiniEngine.Style) -> Unit,
    onSelectStructure: (S1MiniEngine.Structure) -> Unit,
    onDownload: () -> Unit,
    onCancel: () -> Unit,
    onDelete: () -> Unit
) {
    StudioCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("S1-mini by Superwhisper", color = TextPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    "suprwhspr/s1-mini • APP-AWARE NORMALIZER",
                    color = TextMuted,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
            Switch(
                checked = enabled,
                onCheckedChange = onToggleEnabled,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = BgCanvas,
                    checkedTrackColor = TextPrimary,
                    uncheckedThumbColor = TextSecondary,
                    uncheckedTrackColor = BgSubtle
                )
            )
        }

        Spacer(modifier = Modifier.height(6.dp))
        Text(
            "Strips verbal fillers ('um', 'uh', 'you know'), fixes punctuation, and adapts tone automatically by app (Gmail → email, WhatsApp/Messages → casual, Slack/Docs → semi-formal).",
            color = TextSecondary,
            fontSize = 12.sp
        )

        Spacer(modifier = Modifier.height(12.dp))
        Text("STYLE", color = TextMuted, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
        Spacer(modifier = Modifier.height(6.dp))
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            S1MiniEngine.Style.entries.forEach { item ->
                SelectableChip(
                    label = item.label,
                    selected = style == item,
                    onClick = { onSelectStyle(item) }
                )
            }
        }

        Spacer(modifier = Modifier.height(10.dp))
        Text("STRUCTURE", color = TextMuted, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
        Spacer(modifier = Modifier.height(6.dp))
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            S1MiniEngine.Structure.entries.forEach { item ->
                SelectableChip(
                    label = item.label,
                    selected = structure == item,
                    onClick = { onSelectStructure(item) }
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))
        if (status.isDownloading) {
            LinearProgressIndicator(
                progress = { status.progressFraction },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .clip(RoundedCornerShape(3.dp)),
                color = TextPrimary,
                trackColor = BorderColor
            )
            Spacer(modifier = Modifier.height(6.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                val mbDone = status.downloadedBytes / (1024 * 1024)
                val mbTotal = status.totalBytes / (1024 * 1024)
                Text(
                    "Downloading s1-mini-q4_k_m.gguf ($mbDone / $mbTotal MB)",
                    color = TextSecondary,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace
                )
                OutlinedButton(onClick = onCancel) {
                    Text("Pause", color = TextPrimary, fontSize = 12.sp)
                }
            }
        } else if (!status.isInstalled) {
            OutlinedButton(onClick = onDownload) {
                Text("Download S1-mini GGUF Weights (247 MB)", color = TextPrimary, fontSize = 12.sp)
            }
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                StatusPill("S1-MINI GGUF INSTALLED")
                OutlinedButton(onClick = onDelete) {
                    Text("Delete Weights", color = TextSecondary, fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
private fun HardwareTriggerCard(
    selectedMode: SayItFlowCoordinator.TriggerMode,
    holdThresholdMs: Long,
    selectedLanguage: String,
    onSelectMode: (SayItFlowCoordinator.TriggerMode) -> Unit,
    onChangeHoldThreshold: (Long) -> Unit,
    onSelectLanguage: (String) -> Unit
) {
    StudioCard {
        Text(
            text = "HARDWARE TRIGGER & LANGUAGE",
            color = TextMuted,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(10.dp))

        SayItFlowCoordinator.TriggerMode.entries.forEach { mode ->
            val isSelected = mode == selectedMode
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .border(
                        width = 1.dp,
                        color = if (isSelected) TextPrimary else BorderColor,
                        shape = RoundedCornerShape(10.dp)
                    )
                    .background(if (isSelected) BgSubtle else BgCard)
                    .clickable { onSelectMode(mode) }
                    .padding(12.dp)
            ) {
                Column {
                    Text(mode.title, color = TextPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(mode.subtitle, color = TextSecondary, fontSize = 11.sp)
                }
            }
        }

        Spacer(modifier = Modifier.height(10.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Volume Hold Delay", color = TextSecondary, fontSize = 12.sp)
            Text(
                "${holdThresholdMs}ms",
                color = TextPrimary,
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace
            )
        }
        Slider(
            value = holdThresholdMs.toFloat(),
            onValueChange = { onChangeHoldThreshold(it.roundToLong()) },
            valueRange = 200f..500f,
            colors = SliderDefaults.colors(
                thumbColor = TextPrimary,
                activeTrackColor = TextPrimary,
                inactiveTrackColor = BorderColor
            )
        )

        Spacer(modifier = Modifier.height(8.dp))
        Text("VOZ LANGUAGE (25 EUROPEAN LANGUAGES)", color = TextMuted, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
        Spacer(modifier = Modifier.height(6.dp))
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            SayItFlowCoordinator.SUPPORTED_LANGUAGES.forEach { lang ->
                SelectableChip(
                    label = lang.name,
                    selected = selectedLanguage == lang.code,
                    onClick = { onSelectLanguage(lang.code) }
                )
            }
        }
    }
}

@Composable
private fun TestBenchCard(
    isRecording: Boolean,
    statusLabel: String,
    textValue: String,
    onTextChange: (String) -> Unit,
    onPressStart: () -> Unit,
    onPressRelease: () -> Unit
) {
    StudioCard {
        Text(
            text = "LIVE DICTATION TEST BENCH",
            color = TextMuted,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(statusLabel, color = TextSecondary, fontSize = 12.sp)
        Spacer(modifier = Modifier.height(12.dp))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .clip(RoundedCornerShape(12.dp))
                .border(1.dp, if (isRecording) TextPrimary else BorderColor, RoundedCornerShape(12.dp))
                .background(if (isRecording) TextPrimary else BgSubtle)
                .pointerInput(Unit) {
                    detectTapGestures(
                        onPress = {
                            onPressStart()
                            tryAwaitRelease()
                            onPressRelease()
                        }
                    )
                },
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = if (isRecording) "● LISTENING — RELEASE TO TRANSCRIBE" else "HOLD HERE TO SPEAK (OR HOLD VOLUME DOWN)",
                color = if (isRecording) BgCanvas else TextPrimary,
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.height(12.dp))
        OutlinedTextField(
            value = textValue,
            onValueChange = onTextChange,
            modifier = Modifier.fillMaxWidth(),
            minLines = 3,
            placeholder = {
                Text("Dictated text from desert-ant-labs/voz + S1-mini appears here...", color = TextMuted, fontSize = 13.sp)
            },
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = TextPrimary,
                unfocusedTextColor = TextPrimary,
                focusedBorderColor = TextPrimary,
                unfocusedBorderColor = BorderColor,
                cursorColor = TextPrimary
            )
        )
    }
}

@Composable
private fun HistorySection(history: List<SayItFlowCoordinator.DictationRecord>) {
    StudioCard {
        Text(
            text = "RECENT DICTATIONS",
            color = TextMuted,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(8.dp))
        history.take(5).forEach { item ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp)
                    .border(1.dp, BorderColor, RoundedCornerShape(8.dp))
                    .background(BgSubtle, RoundedCornerShape(8.dp))
                    .padding(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        item.targetPackage,
                        color = TextMuted,
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace
                    )
                    Text(
                        "${item.elapsedMs}ms",
                        color = TextMuted,
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(item.polishedTranscript, color = TextPrimary, fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun StudioCard(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .border(1.dp, BorderColor, RoundedCornerShape(14.dp))
            .background(BgCard)
            .padding(16.dp)
    ) {
        content()
    }
}

@Composable
private fun StatusPill(text: String) {
    Box(
        modifier = Modifier
            .border(1.dp, BorderColor, RoundedCornerShape(6.dp))
            .background(BgSubtle, RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Text(
            text = text,
            color = TextPrimary,
            fontSize = 10.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun SelectableChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .border(1.dp, if (selected) TextPrimary else BorderColor, RoundedCornerShape(8.dp))
            .background(if (selected) TextPrimary else BgSubtle)
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        Text(
            text = label,
            color = if (selected) BgCanvas else TextSecondary,
            fontSize = 12.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
        )
    }
}
