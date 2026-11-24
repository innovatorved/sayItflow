import AppKit
import AVFoundation
import Foundation
import KeyboardShortcuts

@MainActor
final class DictationCoordinator {
    private weak var appState: AppState?
    private let audioInput = AudioInput()
    private let collector = AudioSampleCollector()
    private let startSound = NSSound(named: NSSound.Name("Tink"))
    private let doneSound = NSSound(named: NSSound.Name("Pop"))
    private var levelTask: Task<Void, Never>?
    private var sessionGeneration: UInt64 = 0
    private var activeSession = false
    private var isProcessingRelease = false
    private var sessionStartedAt: Date?
    private var pinnedPID: pid_t?
    private var pinnedAppName: String?
    private var pinnedBundleID: String?

    var onboardingInjectionHandler: ((String) -> Void)?

    var isSessionActive: Bool { activeSession || isProcessingRelease }

    init(appState: AppState) {
        self.appState = appState
        let collector = self.collector
        audioInput.onBuffer = { buffer in
            collector.append(buffer: buffer)
        }
        audioInput.onConfigurationChange = { [weak self] in
            Task { @MainActor in
                self?.handleAudioConfigurationLost()
            }
        }
    }

    func handleHotkey(_ event: HotkeyEvent) {
        guard Permissions.allGranted() else {
            appState?.lastError = .permissionsIncomplete
            appState?.openOnboarding()
            return
        }

        if AppSettings.shared.hotkeyMode == .custom,
           KeyboardShortcuts.getShortcut(for: .pushToTalk) == nil {
            appState?.lastError = .hotkeyCustomShortcutMissing
            return
        }

        switch event {
        case .pressStarted:
            guard !activeSession, !isProcessingRelease else { return }
            appState?.lastError = nil
            startSession()
        case .pressEnded:
            guard activeSession else { return }
            finishSession()
        }
    }

    private func handleAudioConfigurationLost() {
        guard activeSession else { return }
        cancel(reason: "microphone disconnected")
    }

    private func startSession() {
        // Check if Voz model is downloaded
        if !VozEngine.shared.isDownloaded {
            RecordingHUDController.shared.show(
                state: .error("Voz model not downloaded"),
                displayMode: .full
            )
            appState?.openDashboard()
            return
        }

        sessionGeneration &+= 1
        let generation = sessionGeneration
        activeSession = true
        sessionStartedAt = Date()
        collector.clear()
        let frontApp = NSWorkspace.shared.frontmostApplication
        pinnedPID = frontApp?.processIdentifier
        pinnedAppName = frontApp?.localizedName
        pinnedBundleID = frontApp?.bundleIdentifier
        let targetIcon = frontApp?.icon ?? NSApp.applicationIconImage

        // In hold-space mode, if the initial Space keyDown passed through before the 0.25s hold
        // threshold elapsed, remove that trailing space in focused text fields or Electron editors.
        // When Carbon RegisterEventHotKey is active, WindowServer swallows the initial Space press.
        if AppSettings.shared.hotkeyMode == .holdSpace,
           appState?.didPassThroughInitialSpace == true {
            let preferPaste = InjectionTargetPolicy.prefersPaste(
                bundleID: frontApp?.bundleIdentifier,
                pid: pinnedPID
            )
            if preferPaste || AXFocusResolver.focusedTextElement(forPID: pinnedPID) != nil {
                _ = KeystrokeEmitter.deleteSelection()
            }
        }

        if AppSettings.shared.soundFeedbackEnabled {
            startSound?.stop()
            startSound?.play()
        }

        appState?.phase = .recording
        appState?.partialTranscript = ""
        appState?.hudMessage = "Listening…"

        RecordingHUDController.shared.show(
            state: .listening,
            hotkeyLabel: AppSettings.shared.hotkeyMode.label,
            displayMode: .minimal,
            targetAppIcon: targetIcon
        )

        // Pre-warm Voz on Neural Engine and S1-mini server while the user is speaking
        // so release-to-inject latency is near-zero even after idle unload.
        Task {
            try? await VozEngine.shared.warmUp()
        }
        if S1MiniEngine.shared.isEnabled && EngineSettings.shared.selectedLanguage == "en" {
            Task {
                _ = await S1MiniEngine.shared.ensureServerRunning()
            }
        }

        startLevelMonitor(generation: generation)
    }

    private func finishSession() {
        let generation = sessionGeneration
        activeSession = false
        isProcessingRelease = true
        stopLevelMonitor()
        audioInput.stop()

        let (samplesToTranscribe, sampleRate) = collector.drain()

        guard !samplesToTranscribe.isEmpty else {
            AppLogger.dictation.warning("finishSession: No audio samples collected")
            finishIdle()
            return
        }

        let audioDurationSeconds = Double(samplesToTranscribe.count) / sampleRate
        AppLogger.dictation.notice("finishSession: Transcribing \(samplesToTranscribe.count) samples (\(String(format: "%.2f", audioDurationSeconds))s) at \(sampleRate) Hz")

        appState?.phase = .transcribing
        appState?.hudMessage = "Transcribing with Voz…"
        RecordingHUDController.shared.show(
            state: .transcribing,
            displayMode: .minimal
        )

        let startedAt = sessionStartedAt ?? Date()
        let pinnedApp = pinnedPID
        let capturedAppName = pinnedAppName
        let capturedBundleID = pinnedBundleID

        Task {
            var hudDwellNanoseconds: UInt64 = 350_000_000

            do {
                let result = try await VozEngine.shared.transcribe(
                    samples: samplesToTranscribe,
                    sampleRate: sampleRate
                )

                guard generation == self.sessionGeneration else { return }

                let rawTranscript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                var transcript = rawTranscript
                AppLogger.dictation.notice("Voz raw output: '\(transcript)'")

                if !transcript.isEmpty {
                    let currentLang = EngineSettings.shared.selectedLanguage
                    let isEnglish = (currentLang == "en")
                    let targetBundle = capturedBundleID
                        ?? (pinnedApp != nil ? NSRunningApplication(processIdentifier: pinnedApp!)?.bundleIdentifier : nil)
                        ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    let targetAppName = capturedAppName
                        ?? (pinnedApp != nil ? NSRunningApplication(processIdentifier: pinnedApp!)?.localizedName : nil)
                        ?? NSWorkspace.shared.frontmostApplication?.localizedName

                    // Apply on-device speech text normalization if enabled and language is English
                    if S1MiniEngine.shared.isEnabled && isEnglish {
                        let normalizerName = S1MiniEngine.shared.selectedModel.shortName
                        self.appState?.phase = .polishing
                        self.appState?.hudMessage = "Polishing with \(normalizerName)…"
                        RecordingHUDController.shared.show(
                            state: .polishing,
                            displayMode: .minimal
                        )
                        let contextOverride = AppContext.s1Context(forBundleID: targetBundle)
                        transcript = await S1MiniEngine.shared.normalize(
                            transcript,
                            language: currentLang,
                            contextOverride: contextOverride
                        )
                        AppLogger.dictation.notice("\(normalizerName) normalized output: '\(transcript)'")
                    }

                    guard generation == self.sessionGeneration else { return }

                    // If S1-mini returned empty (e.g. input was only fillers like 'um', 'uh')
                    guard !transcript.isEmpty else {
                        self.isProcessingRelease = false
                        self.appState?.phase = .idle
                        self.appState?.hudMessage = "Done"
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard generation == self.sessionGeneration else { return }
                        self.finishIdle()
                        return
                    }

                    // Apply user's custom vocabulary casing/replacements (cached in memory)
                    transcript = VocabularyStore.applyCaseCorrections(to: transcript)

                    self.appState?.partialTranscript = transcript
                    self.appState?.noteWords(in: transcript)

                    // Only route to onboarding/demo handler if the user
                    // started dictation from SayItFlow itself (its own window).
                    // When pinnedApp is an external app, always inject there.
                    let ownPID = ProcessInfo.processInfo.processIdentifier
                    let isOwnApp = (pinnedApp != nil && pinnedApp == ownPID)
                    var injectionSucceeded = true
                    var injectionErrorMessage: String?

                    if isOwnApp, let onboardingHandler = self.onboardingInjectionHandler {
                        onboardingHandler(transcript)
                    } else {
                        var options = TextInjectionOptions()
                        options.pinnedPID = pinnedApp
                        options.preferPaste = InjectionTargetPolicy.prefersPaste(bundleID: targetBundle, pid: pinnedApp)
                        do {
                            try TextInjector().inject(transcript, options: options)
                        } catch {
                            injectionSucceeded = false
                            injectionErrorMessage = error.localizedDescription
                            AppLogger.dictation.error("Text injection failed: \(error.localizedDescription)")
                        }
                    }

                    let engineName = S1MiniEngine.shared.isEnabled && isEnglish
                        ? S1MiniEngine.shared.selectedModel.engineAnalyticsTag
                        : "voz"

                    // Persist timestamped transcript to local history store
                    TranscriptHistoryStore.shared.record(
                        text: transcript,
                        rawText: rawTranscript,
                        timestamp: startedAt,
                        durationSeconds: audioDurationSeconds,
                        language: currentLang,
                        engine: engineName,
                        targetAppName: targetAppName,
                        targetBundleID: targetBundle,
                        injectionSucceeded: injectionSucceeded
                    )

                    // Allow immediate re-press while the HUD pill fades out
                    self.isProcessingRelease = false
                    if injectionSucceeded {
                        if AppSettings.shared.soundFeedbackEnabled {
                            self.doneSound?.stop()
                            self.doneSound?.play()
                        }
                        self.appState?.phase = .idle
                        self.appState?.hudMessage = "Done"
                        RecordingHUDController.shared.show(
                            state: .done,
                            displayMode: .minimal
                        )
                    } else {
                        hudDwellNanoseconds = 2_200_000_000
                        let message = injectionErrorMessage ?? "Copied to clipboard — press ⌘V"
                        self.appState?.phase = .error(message)
                        self.appState?.hudMessage = message
                        RecordingHUDController.shared.show(
                            state: .error(message),
                            displayMode: .full
                        )
                    }
                } else {
                    AppLogger.dictation.notice("Voz produced empty transcript for session")
                    self.isProcessingRelease = false
                    self.appState?.phase = .idle
                }
            } catch {
                AppLogger.dictation.error("Voz transcription error: \(error.localizedDescription)")
                hudDwellNanoseconds = 2_200_000_000
                self.isProcessingRelease = false
                self.appState?.phase = .error(error.localizedDescription)
                RecordingHUDController.shared.show(
                    state: .error(error.localizedDescription),
                    displayMode: .full
                )
            }

            try? await Task.sleep(nanoseconds: hudDwellNanoseconds)
            guard generation == self.sessionGeneration else { return }
            self.finishIdle()
        }
    }

    func cancel(reason: String) {
        sessionGeneration &+= 1
        stopLevelMonitor()
        audioInput.stop()
        collector.clear()

        activeSession = false
        isProcessingRelease = false
        sessionStartedAt = nil
        RecordingHUDController.shared.hide()
        appState?.phase = .idle
        appState?.partialTranscript = ""
        SessionTrace.log("dictation cancelled: \(reason)", category: "session")
    }

    private func finishIdle() {
        isProcessingRelease = false
        sessionStartedAt = nil
        collector.clear()
        appState?.phase = .idle
        RecordingHUDController.shared.hide()
    }

    private func startLevelMonitor(generation: UInt64) {
        levelTask?.cancel()
        levelTask = Task { [weak self, audioInput] in
            guard !Task.isCancelled else { return }
            do {
                try await audioInput.beginStreaming()
            } catch {
                AppLogger.dictation.error("AudioInput beginStreaming failed: \(error.localizedDescription)")
                await MainActor.run {
                    guard let self, self.sessionGeneration == generation, self.activeSession else { return }
                    self.activeSession = false
                    self.audioInput.stop()
                    self.appState?.phase = .error(error.localizedDescription)
                    RecordingHUDController.shared.show(
                        state: .error(error.localizedDescription),
                        displayMode: .full
                    )
                }
                return
            }
            if Task.isCancelled {
                audioInput.stop()
                return
            }
            while !Task.isCancelled {
                let level = audioInput.peakLevel
                await MainActor.run {
                    RecordingHUDController.shared.updateAudioLevel(level)
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    private func stopLevelMonitor() {
        levelTask?.cancel()
        levelTask = nil
    }
}
