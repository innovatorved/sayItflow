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
import com.sayitflow.android.ml.HinglishNormalizer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * System-wide Accessibility Service for Google Pixel:
 * 1. Intercepts hardware Volume button holds (`Volume Down`, `Volume Up`, or `Volume Up + Down` chord)
 * 2. Keeps SenseVoice/Voz warm in RAM on service connection and button press
 * 3. Captures 16 kHz mono PCM with zero-loss circular pre-roll & displays waveform pill
 * 4. Transcribes with 100% on-device offline SenseVoice + Roman Hinglish normalizer + S1-mini
 * 5. Injects text directly into the active text input without switching away from Gboard!
 */
class SayItFlowAccessibilityService : AccessibilityService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var coordinator: SayItFlowCoordinator
    private lateinit var overlayPill: OverlayPillController
    private var waveformCollectorJob: Job? = null
    private var streamingWaveformJob: Job? = null

    private var volDownPressed = false
    private var volUpPressed = false
    private var holdTriggered = false
    private var activeSessionStreaming = false
    private var holdRunnable: Runnable? = null
    private var currentForegroundPackage: String = ""

    override fun onServiceConnected() {
        super.onServiceConnected()
        coordinator = SayItFlowCoordinator.getInstance(this)
        overlayPill = OverlayPillController(this)
        coordinator.setAccessibilityConnected(true)

        if (coordinator.asrEngineMode.value == SayItFlowCoordinator.AsrEngineMode.SENSE_VOICE_OFFLINE) {
            coordinator.senseVoiceEngine.warmUpAsync()
        } else if (coordinator.asrEngineMode.value == SayItFlowCoordinator.AsrEngineMode.VOZ_OFFLINE &&
            coordinator.vozEngine.areModelFilesInstalled()
        ) {
            coordinator.vozEngine.warmUpAsync()
        }

        waveformCollectorJob = serviceScope.launch {
            coordinator.audioCapture.waveformLevels.collect { levels ->
                if (coordinator.audioCapture.isRecording.value) {
                    overlayPill.updateWaveform(levels)
                }
            }
        }
        streamingWaveformJob = serviceScope.launch {
            coordinator.fastStreamingEngine.waveformLevels.collect { levels ->
                if (coordinator.fastStreamingEngine.isListening.value) {
                    overlayPill.updateWaveform(levels)
                }
            }
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString()
        if (!pkg.isNullOrBlank() && !pkg.contains("systemui", ignoreCase = true)) {
            currentForegroundPackage = pkg
            if (::coordinator.isInitialized) {
                coordinator.setActiveForegroundPackage(pkg)
            }
        }
    }

    override fun onInterrupt() {
        stopDictationAndCancel()
    }

    override fun onDestroy() {
        if (::coordinator.isInitialized) {
            coordinator.setAccessibilityConnected(false)
        }
        if (::overlayPill.isInitialized) {
            overlayPill.hide()
        }
        waveformCollectorJob?.cancel()
        streamingWaveformJob?.cancel()
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

        return when (mode) {
            SayItFlowCoordinator.TriggerMode.HOLD_VOLUME_DOWN -> {
                if (keyCode != KeyEvent.KEYCODE_VOLUME_DOWN) false
                else handleSingleButtonHold(
                    event = event,
                    adjustDirection = AudioManager.ADJUST_LOWER,
                    holdDelayMs = holdDelayMs
                )
            }
            SayItFlowCoordinator.TriggerMode.HOLD_VOLUME_UP -> {
                if (keyCode != KeyEvent.KEYCODE_VOLUME_UP) false
                else handleSingleButtonHold(
                    event = event,
                    adjustDirection = AudioManager.ADJUST_RAISE,
                    holdDelayMs = holdDelayMs
                )
            }
            SayItFlowCoordinator.TriggerMode.VOLUME_CHORD -> {
                handleVolumeChord(event)
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
                    val asrMode = coordinator.asrEngineMode.value
                    if (asrMode == SayItFlowCoordinator.AsrEngineMode.SENSE_VOICE_OFFLINE) {
                        // Start 1.5s circular pre-roll on key down without dropping initial speech
                        coordinator.audioCapture.startPreRoll()
                        coordinator.senseVoiceEngine.warmUpAsync()
                    } else if (asrMode == SayItFlowCoordinator.AsrEngineMode.INSTANT_STREAMING &&
                        coordinator.fastStreamingEngine.isAvailable()
                    ) {
                        // Start pre-roll microphone capture at millisecond 0 so speech during the hold delay is never cut off
                        coordinator.fastStreamingEngine.startPreRollOnKeyDown()
                    } else if (asrMode == SayItFlowCoordinator.AsrEngineMode.VOZ_OFFLINE) {
                        coordinator.audioCapture.startPreRoll()
                        if (coordinator.vozEngine.areModelFilesInstalled()) {
                            coordinator.vozEngine.warmUpAsync()
                        }
                    }
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
                    // Short tap (< threshold): discard pre-roll and forward normal volume adjustment
                    coordinator.audioCapture.discardPreRoll()
                    coordinator.fastStreamingEngine.discardPreRoll()
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
                    val asrMode = coordinator.asrEngineMode.value
                    if (asrMode == SayItFlowCoordinator.AsrEngineMode.SENSE_VOICE_OFFLINE) {
                        coordinator.senseVoiceEngine.warmUpAsync()
                    } else if (asrMode == SayItFlowCoordinator.AsrEngineMode.VOZ_OFFLINE &&
                        coordinator.vozEngine.areModelFilesInstalled()
                    ) {
                        coordinator.vozEngine.warmUpAsync()
                    }
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
        val asrMode = coordinator.asrEngineMode.value
        val useStreaming = coordinator.shouldUseZeroLossStreamingPipe()

        if (useStreaming) {
            activeSessionStreaming = true
            overlayPill.showListening(currentForegroundPackage)
            val started = coordinator.fastStreamingEngine.startStreaming(
                languageCode = coordinator.selectedLanguage.value
            )
            if (started) {
                triggerHaptic(isStart = true)
            } else {
                overlayPill.hide()
            }
            return
        }

        activeSessionStreaming = false
        if (asrMode == SayItFlowCoordinator.AsrEngineMode.VOZ_OFFLINE && !coordinator.vozEngine.areModelFilesInstalled()) {
            triggerHaptic(isStart = false)
            overlayPill.hide()
            return
        }

        // Attach overlay first so Android 14+ AudioFlinger sees an active Accessibility Overlay window
        overlayPill.showListening(currentForegroundPackage)
        val promoted = coordinator.audioCapture.promoteToActiveRecording()
        val started = if (promoted) true else coordinator.audioCapture.startRecording()
        if (started) {
            triggerHaptic(isStart = true)
        } else {
            overlayPill.hide()
        }
    }

    private fun finishDictationSession(ignoreShortTap: Boolean = true) {
        if (activeSessionStreaming) {
            activeSessionStreaming = false
            triggerHaptic(isStart = false)
            val targetPkg = currentForegroundPackage

            serviceScope.launch {
                val t0 = System.currentTimeMillis()
                try {
                    val streamResult = coordinator.fastStreamingEngine.stopAndAwaitTranscript(maxWaitMs = 1800L)
                    overlayPill.hide()

                    val rawText = HinglishNormalizer.transliterateToRomanHinglish(streamResult).trim()
                    if (rawText.isBlank()) {
                        return@launch
                    }

                    val selectedLang = coordinator.selectedLanguage.value
                    val shouldPolish = coordinator.s1MiniEnabled.value &&
                        (selectedLang == "auto" || selectedLang == "en" || selectedLang == "en-IN" || selectedLang == "hinglish")

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

                    val elapsed = (System.currentTimeMillis() - t0).coerceAtLeast(1L)
                    coordinator.recordDictation(
                        SayItFlowCoordinator.DictationRecord(
                            rawTranscript = rawText,
                            polishedTranscript = finalText,
                            targetPackage = targetPkg.ifBlank { "System" },
                            elapsedMs = elapsed
                        )
                    )

                    val injected = injectTextIntoActiveField(finalText)
                    if (!injected) {
                        copyToClipboard(finalText)
                    }
                } catch (e: Exception) {
                    android.util.Log.e("SayItFlowService", "Streaming dictation failed", e)
                    overlayPill.hide()
                }
            }
            return
        }

        if (!coordinator.audioCapture.isRecording.value) {
            coordinator.audioCapture.discardPreRoll()
            return
        }

        // Immediately trigger release haptic and show transcribing state on Main Looper
        // Main Looper returns in <1ms without blocking on the 200ms post-release acoustic tail capture!
        triggerHaptic(isStart = false)

        val asrMode = coordinator.asrEngineMode.value
        val isCold = if (asrMode == SayItFlowCoordinator.AsrEngineMode.SENSE_VOICE_OFFLINE) {
            !coordinator.senseVoiceEngine.isLoaded.value
        } else {
            !coordinator.vozEngine.isLoaded.value
        }
        overlayPill.showTranscribing(isColdWarmUp = isCold)
        val targetPkg = currentForegroundPackage

        serviceScope.launch(Dispatchers.IO) {
            val t0 = System.currentTimeMillis()
            try {
                // Post-release acoustic tail is captured asynchronously on Dispatchers.IO
                val samples = coordinator.audioCapture.stopRecordingAsync()
                val rawMs = coordinator.audioCapture.lastRawDurationMs

                // Ignore ultra-short accidental releases (< 200 ms after hold threshold)
                if ((ignoreShortTap && rawMs < 200L) || samples.size < 1600) {
                    withContext(Dispatchers.Main) {
                        overlayPill.hide()
                    }
                    return@launch
                }

                val selectedLang = coordinator.selectedLanguage.value
                val rawTranscribed: String = if (asrMode == SayItFlowCoordinator.AsrEngineMode.SENSE_VOICE_OFFLINE) {
                    coordinator.senseVoiceEngine.transcribe(samples, language = selectedLang).text
                } else {
                    coordinator.vozEngine.transcribe(samples)
                }

                val rawText = HinglishNormalizer.transliterateToRomanHinglish(rawTranscribed).trim()
                if (rawText.isBlank()) {
                    withContext(Dispatchers.Main) {
                        overlayPill.hide()
                    }
                    return@launch
                }

                val shouldPolish = coordinator.s1MiniEnabled.value &&
                    (selectedLang == "auto" || selectedLang == "en" || selectedLang == "en-IN" || selectedLang == "hinglish")

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

                val elapsed = (System.currentTimeMillis() - t0).coerceAtLeast(1L)
                coordinator.recordDictation(
                    SayItFlowCoordinator.DictationRecord(
                        rawTranscript = rawText,
                        polishedTranscript = finalText,
                        targetPackage = targetPkg.ifBlank { "System" },
                        elapsedMs = elapsed
                    )
                )

                withContext(Dispatchers.Main) {
                    overlayPill.hide()
                    val injected = injectTextIntoActiveField(finalText)
                    if (!injected) {
                        copyToClipboard(finalText)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("SayItFlowService", "Dictation failed", e)
                withContext(Dispatchers.Main) {
                    overlayPill.hide()
                }
            }
        }
    }

    private fun stopDictationAndCancel() {
        holdRunnable?.let { mainHandler.removeCallbacks(it) }
        holdRunnable = null
        holdTriggered = false
        activeSessionStreaming = false
        if (::coordinator.isInitialized) {
            coordinator.audioCapture.discardPreRoll()
            if (coordinator.audioCapture.isRecording.value) {
                coordinator.audioCapture.stopRecording()
            }
            if (coordinator.fastStreamingEngine.isListening.value) {
                coordinator.fastStreamingEngine.cancel()
            }
        }
        if (::overlayPill.isInitialized) {
            overlayPill.hide()
        }
    }

    /**
     * Known chat/input placeholder strings exposed by WhatsApp, Messages, Telegram, Instagram,
     * Slack, Discord, and Gboard when an input box is actually empty.
     */
    private fun isPlaceholderText(targetNode: AccessibilityNodeInfo, existing: String): Boolean {
        if (existing.isEmpty()) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (targetNode.isShowingHintText) return true
            val hint = targetNode.hintText?.toString().orEmpty()
            if (hint.isNotEmpty() && existing.equals(hint, ignoreCase = true)) return true
        }
        // In WhatsApp, Google Messages, Telegram, etc., an empty input often reports selection < 0
        // or 0 while exposing "Message" or "Type a message" as node.text without setting hintText.
        val normalized = existing.trim().lowercase()
        val isKnownPlaceholder = normalized == "message" ||
            normalized == "message..." ||
            normalized == "type a message" ||
            normalized == "type a message..." ||
            normalized == "write a message" ||
            normalized == "write a message..." ||
            normalized == "send a message" ||
            normalized == "text message" ||
            normalized == "rcs message" ||
            normalized == "reply" ||
            normalized == "add a comment..." ||
            normalized == "search" ||
            normalized == "search or type url" ||
            normalized == "ask anything"

        return isKnownPlaceholder && targetNode.textSelectionStart <= 0
    }

    /**
     * Injects dictated text directly into the currently focused editable `AccessibilityNodeInfo`
     * at the cursor position without switching keyboards, and ensures placeholder hints like
     * "Message" are never prepended.
     */
    private fun injectTextIntoActiveField(textToInsert: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val targetNode = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: findFirstEditableNode(root)
            ?: return false

        if (!targetNode.isEditable) {
            return pasteViaClipboard(targetNode, textToInsert)
        }

        val existing = targetNode.text?.toString().orEmpty()
        val actualExisting = if (isPlaceholderText(targetNode, existing)) "" else existing

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
