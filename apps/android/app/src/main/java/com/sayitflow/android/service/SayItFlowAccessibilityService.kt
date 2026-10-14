package com.sayitflow.android.service

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.sayitflow.android.SayItFlowCoordinator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * System-wide Accessibility Service for Google Pixel:
 * 1. Intercepts hardware Volume button holds (`Volume Down`, `Volume Up`, or `Volume Up + Down` chord)
 * 2. Pre-warms `desert-ant-labs/voz` as soon as the button is pressed
 * 3. Captures 16 kHz mono PCM while held & displays the Monochrome Studio waveform pill
 * 4. Transcribes with `desert-ant-labs/voz` + polishes with `S1-mini` (App-Aware Context)
 * 5. Injects text directly into the active text input without switching away from Gboard!
 */
class SayItFlowAccessibilityService : AccessibilityService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var coordinator: SayItFlowCoordinator
    private lateinit var overlayPill: OverlayPillController
    private var waveformCollectorJob: Job? = null

    private var volDownPressed = false
    private var volUpPressed = false
    private var holdTriggered = false
    private var holdRunnable: Runnable? = null
    private var currentForegroundPackage: String = ""

    override fun onServiceConnected() {
        super.onServiceConnected()
        coordinator = SayItFlowCoordinator.getInstance(this)
        overlayPill = OverlayPillController(this)
        coordinator.setAccessibilityConnected(true)

        waveformCollectorJob = serviceScope.launch {
            coordinator.audioCapture.waveformLevels.collect { levels ->
                if (coordinator.audioCapture.isRecording.value) {
                    overlayPill.updateWaveform(levels)
                }
            }
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString()
        if (!pkg.isNullOrBlank() && pkg != packageName) {
            currentForegroundPackage = pkg
        }
    }

    override fun onInterrupt() {
        stopDictationAndCancel()
    }

    override fun onDestroy() {
        coordinator.setAccessibilityConnected(false)
        overlayPill.hide()
        waveformCollectorJob?.cancel()
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (keyCode != KeyEvent.KEYCODE_VOLUME_DOWN && keyCode != KeyEvent.KEYCODE_VOLUME_UP) {
            return false
        }

        val mode = coordinator.triggerMode.value
        val holdDelayMs = coordinator.holdThresholdMs.value

        when (mode) {
            SayItFlowCoordinator.TriggerMode.HOLD_VOLUME_DOWN -> {
                if (keyCode != KeyEvent.KEYCODE_VOLUME_DOWN) return false
                return handleSingleButtonHold(
                    event = event,
                    adjustDirection = AudioManager.ADJUST_LOWER,
                    holdDelayMs = holdDelayMs
                )
            }
            SayItFlowCoordinator.TriggerMode.HOLD_VOLUME_UP -> {
                if (keyCode != KeyEvent.KEYCODE_VOLUME_UP) return false
                return handleSingleButtonHold(
                    event = event,
                    adjustDirection = AudioManager.ADJUST_RAISE,
                    holdDelayMs = holdDelayMs
                )
            }
            SayItFlowCoordinator.TriggerMode.VOLUME_CHORD -> {
                return handleVolumeChord(event)
            }
        }
    }

    private fun handleSingleButtonHold(
        event: KeyEvent,
        adjustDirection: Int,
        holdDelayMs: Long
    ): Boolean {
        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                if (event.repeatCount == 0) {
                    holdTriggered = false
                    // Pre-warm desert-ant-labs/voz immediately while the user's finger is pressing
                    coordinator.vozEngine.warmUpAsync()
                    val runnable = Runnable {
                        holdTriggered = true
                        startDictationSession()
                    }
                    holdRunnable = runnable
                    mainHandler.postDelayed(runnable, holdDelayMs)
                }
                return true
            }
            KeyEvent.ACTION_UP -> {
                holdRunnable?.let { mainHandler.removeCallbacks(it) }
                holdRunnable = null
                if (holdTriggered) {
                    holdTriggered = false
                    finishDictationSession()
                } else {
                    // Short tap (< 280ms): forward normal volume adjustment
                    val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    audioManager.adjustStreamVolume(
                        AudioManager.STREAM_MUSIC,
                        adjustDirection,
                        AudioManager.FLAG_SHOW_UI
                    )
                }
                return true
            }
        }
        return false
    }

    private fun handleVolumeChord(event: KeyEvent): Boolean {
        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                if (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) volDownPressed = true
                if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) volUpPressed = true
                if (volDownPressed && volUpPressed && !holdTriggered) {
                    holdTriggered = true
                    coordinator.vozEngine.warmUpAsync()
                    startDictationSession()
                    return true
                }
                return holdTriggered
            }
            KeyEvent.ACTION_UP -> {
                if (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) volDownPressed = false
                if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) volUpPressed = false
                if (holdTriggered && (!volDownPressed || !volUpPressed)) {
                    holdTriggered = false
                    finishDictationSession()
                    return true
                }
                return false
            }
        }
        return false
    }

    private fun startDictationSession() {
        if (!coordinator.vozEngine.areModelFilesInstalled()) {
            triggerHaptic(isStart = false)
            overlayPill.showMessageAndAutoDismiss("Download Desert Ant Voz in SayItFlow first", 2000L)
            return
        }
        val started = coordinator.audioCapture.startRecording()
        if (started) {
            triggerHaptic(isStart = true)
            overlayPill.showListening()
        } else {
            overlayPill.showMessageAndAutoDismiss("Grant Microphone permission in SayItFlow", 2000L)
        }
    }

    private fun finishDictationSession() {
        if (!coordinator.audioCapture.isRecording.value) return
        val samples = coordinator.audioCapture.stopRecording()
        triggerHaptic(isStart = false)

        // Ignore ultra-short accidental taps (< 180 ms = 2,880 samples at 16 kHz)
        if (samples.size < 2880) {
            overlayPill.hide()
            return
        }

        overlayPill.showTranscribing()
        val targetPkg = currentForegroundPackage

        serviceScope.launch {
            val t0 = System.currentTimeMillis()
            try {
                val rawText = coordinator.vozEngine.transcribe(samples)
                if (rawText.isBlank()) {
                    overlayPill.hide()
                    return@launch
                }

                val selectedLang = coordinator.selectedLanguage.value
                val shouldPolish = coordinator.s1MiniEnabled.value &&
                    (selectedLang == "auto" || selectedLang == "en")

                val finalText = if (shouldPolish) {
                    coordinator.s1MiniEngine.polish(
                        rawTranscript = rawText,
                        foregroundPackage = targetPkg,
                        style = coordinator.s1Style.value,
                        structure = coordinator.s1Structure.value,
                        customContext = coordinator.s1CustomContext.value
                    )
                } else {
                    rawText
                }

                val elapsed = System.currentTimeMillis() - t0
                coordinator.recordDictation(
                    SayItFlowCoordinator.DictationRecord(
                        rawTranscript = rawText,
                        polishedTranscript = finalText,
                        targetPackage = targetPkg.ifBlank { "System" },
                        elapsedMs = elapsed
                    )
                )

                val injected = injectTextIntoActiveField(finalText)
                if (injected) {
                    overlayPill.showMessageAndAutoDismiss("Injected ✓", 850L)
                } else {
                    copyToClipboard(finalText)
                    overlayPill.showMessageAndAutoDismiss("Copied to clipboard ✓", 1200L)
                }
            } catch (e: Exception) {
                overlayPill.showMessageAndAutoDismiss("Error: ${e.localizedMessage ?: "Failed"}", 1800L)
            }
        }
    }

    private fun stopDictationAndCancel() {
        holdRunnable?.let { mainHandler.removeCallbacks(it) }
        holdRunnable = null
        holdTriggered = false
        if (coordinator.audioCapture.isRecording.value) {
            coordinator.audioCapture.stopRecording()
        }
        overlayPill.hide()
    }

    /**
     * Injects dictated text directly into the currently focused editable `AccessibilityNodeInfo`
     * at the cursor position without switching keyboards.
     */
    private fun injectTextIntoActiveField(textToInsert: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val targetNode = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: findFirstEditableNode(root)
            ?: return false

        if (!targetNode.isEditable) {
            return pasteViaClipboard(targetNode, textToInsert)
        }

        val existingCharSeq = targetNode.text
        val existing = existingCharSeq?.toString().orEmpty()
        // Note: When `existingCharSeq` is equal to the field's hint text on Android, treat existing as empty
        val hint = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            targetNode.hintText?.toString().orEmpty()
        } else {
            ""
        }
        val actualExisting = if (existing.isNotEmpty() && existing == hint) "" else existing

        val selStart = targetNode.textSelectionStart.takeIf { it in 0..actualExisting.length }
            ?: actualExisting.length
        val selEnd = targetNode.textSelectionEnd.takeIf { it in selStart..actualExisting.length }
            ?: selStart

        val prefix = actualExisting.substring(0, selStart)
        val suffix = actualExisting.substring(selEnd)
        val needsLeadingSpace = prefix.isNotEmpty() && !prefix.last().isWhitespace()
        val insertedPiece = if (needsLeadingSpace) " $textToInsert" else textToInsert
        val updatedText = prefix + insertedPiece + suffix

        val args = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                updatedText
            )
        }
        val setOk = targetNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        if (setOk) {
            val newCursor = (prefix.length + insertedPiece.length).coerceAtMost(updatedText.length)
            val selArgs = Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, newCursor)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, newCursor)
            }
            targetNode.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selArgs)
            return true
        }

        return pasteViaClipboard(targetNode, insertedPiece)
    }

    private fun pasteViaClipboard(node: AccessibilityNodeInfo, text: String): Boolean {
        copyToClipboard(text)
        return node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
    }

    private fun copyToClipboard(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("SayItFlow Dictation", text))
    }

    private fun findFirstEditableNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable && node.isFocused) return node
        for (i in 0 until node.childCount) {
            val found = findFirstEditableNode(node.getChild(i))
            if (found != null) return found
        }
        return null
    }

    private fun triggerHaptic(isStart: Boolean) {
        try {
            val vibrator = getSystemService(Vibrator::class.java) ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val effect = if (isStart) {
                    VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                } else {
                    VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK)
                }
                vibrator.vibrate(effect)
            } else {
                vibrator.vibrate(VibrationEffect.createOneShot(if (isStart) 24L else 12L, 180))
            }
        } catch (_: Exception) {
        }
    }
}
