import AppKit
import AVFoundation
import Foundation
import KeyboardShortcuts

private final class AudioSampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 16000.0

    func append(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let count = Int(buffer.frameLength)
        let rate = buffer.format.sampleRate
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
        sampleRate = rate
        lock.unlock()
    }

    func drain() -> (samples: [Float], sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        let collected = samples
        let rate = sampleRate
        samples.removeAll(keepingCapacity: true)
        return (collected, rate)
    }

    func clear() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

@MainActor
final class DictationCoordinator {
    private weak var appState: AppState?
    private let audioInput = AudioInput()
    private let collector = AudioSampleCollector()
    private var levelTask: Task<Void, Never>?
    private var audioCaptureTask: Task<Void, Never>?
    private var sessionGeneration: UInt64 = 0
    private var activeSession = false
    private var isProcessingRelease = false
    private var sessionStartedAt: Date?
    private var pinnedPID: pid_t?

    var onboardingInjectionHandler: ((String) -> Void)?
    var onboardingLiveUpdateHandler: ((String) -> Void)?
    var onboardingLivePrefixProvider: (() -> String)?

    var isSessionActive: Bool { activeSession || isProcessingRelease }

    init(appState: AppState) {
        self.appState = appState
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
        activeSession = true
        sessionStartedAt = Date()
        collector.clear()
        let frontApp = NSWorkspace.shared.frontmostApplication
        pinnedPID = frontApp?.processIdentifier
        let targetIcon = frontApp?.icon ?? NSApp.applicationIconImage

        appState?.phase = .recording
        appState?.partialTranscript = ""
        appState?.hudMessage = "Listening…"

        RecordingHUDController.shared.show(
            state: .listening,
            hotkeyLabel: AppSettings.shared.hotkeyMode.label,
            displayMode: .minimal,
            targetAppIcon: targetIcon
        )
        startAudioCapture()
        startLevelMonitor()
    }

    private func finishSession() {
        let generation = sessionGeneration
        activeSession = false
        isProcessingRelease = true
        stopLevelMonitor()
        audioInput.stop()
        audioCaptureTask?.cancel()
        audioCaptureTask = nil

        let (samplesToTranscribe, sampleRate) = collector.drain()

        guard !samplesToTranscribe.isEmpty else {
            AppLogger.dictation.warning("finishSession: No audio samples collected")
            finishIdle()
            return
        }

        AppLogger.dictation.notice("finishSession: Transcribing \(samplesToTranscribe.count) samples (\(String(format: "%.2f", Double(samplesToTranscribe.count) / sampleRate))s) at \(sampleRate) Hz")

        appState?.phase = .transcribing
        appState?.hudMessage = "Transcribing with Voz…"
        RecordingHUDController.shared.show(
            state: .transcribing,
            displayMode: .minimal
        )

        let startedAt = sessionStartedAt ?? Date()
        let pinnedApp = pinnedPID

        Task {
            do {
                let result = try await VozEngine.shared.transcribe(
                    samples: samplesToTranscribe,
                    sampleRate: sampleRate
                )

                guard generation == self.sessionGeneration else { return }

                var transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.dictation.notice("Voz raw output: '\(transcript)'")

                if !transcript.isEmpty {
                    let currentLang = EngineSettings.shared.selectedLanguage
                    let isEnglish = (currentLang == "en")

                    // Apply S1-mini speech text normalization if enabled and language is English
                    if S1MiniEngine.shared.isEnabled && isEnglish {
                        self.appState?.hudMessage = "Polishing with S1-mini…"
                        transcript = await S1MiniEngine.shared.normalize(transcript, language: currentLang)
                        AppLogger.dictation.notice("S1-mini normalized output: '\(transcript)'")
                    }

                    // If S1-mini returned empty (e.g. input was only fillers like 'um', 'uh')
                    guard !transcript.isEmpty else {
                        self.appState?.phase = .idle
                        self.appState?.hudMessage = "Done"
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard generation == self.sessionGeneration else { return }
                        self.finishIdle()
                        return
                    }

                    self.appState?.partialTranscript = transcript
                    self.appState?.noteWords(in: transcript)

                    let wordCount = transcript.split { $0.isWhitespace || $0.isNewline }.count
                    let engineName = (S1MiniEngine.shared.isEnabled && isEnglish) ? "Voz + S1-mini" : "Voz"
                    DictationAnalytics.shared.record(
                        startedAt: startedAt,
                        words: wordCount,
                        chars: transcript.count,
                        chunksCommitted: 1,
                        mode: "batch",
                        engine: engineName,
                        outcome: "done"
                    )
                    // Only route to onboarding/demo handler if the user
                    // started dictation from SayItFlow itself (its own window).
                    // When pinnedApp is an external app, always inject there.
                    let ownPID = ProcessInfo.processInfo.processIdentifier
                    let isOwnApp = (pinnedApp != nil && pinnedApp == ownPID)
                    if isOwnApp, let onboardingHandler = self.onboardingInjectionHandler {
                        onboardingHandler(transcript)
                    } else {
                        var options = TextInjectionOptions()
                        options.pinnedPID = pinnedApp
                        let targetBundle = (pinnedApp != nil ? NSRunningApplication(processIdentifier: pinnedApp!)?.bundleIdentifier : nil)
                            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                        options.preferPaste = InjectionTargetPolicy.prefersPaste(bundleID: targetBundle)
                        do {
                            try TextInjector().inject(transcript, options: options)
                        } catch {
                            AppLogger.dictation.error("Text injection failed: \(error.localizedDescription)")
                        }
                    }

                    self.appState?.phase = .idle
                    self.appState?.hudMessage = "Done"
                    RecordingHUDController.shared.show(
                        state: .done,
                        displayMode: .minimal
                    )
                } else {
                    AppLogger.dictation.notice("Voz produced empty transcript for session")
                    self.appState?.phase = .idle
                }
            } catch {
                AppLogger.dictation.error("Voz transcription error: \(error.localizedDescription)")
                self.appState?.phase = .error(error.localizedDescription)
                RecordingHUDController.shared.show(
                    state: .error(error.localizedDescription),
                    displayMode: .full
                )
            }

            try? await Task.sleep(nanoseconds: 400_000_000)
            guard generation == self.sessionGeneration else { return }
            self.finishIdle()
        }
    }

    func cancel(reason: String) {
        sessionGeneration &+= 1
        stopLevelMonitor()
        audioCaptureTask?.cancel()
        audioCaptureTask = nil
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

    private func startAudioCapture() {
        audioCaptureTask?.cancel()
        audioCaptureTask = Task { [audioInput, collector] in
            for await wrapped in audioInput.bufferStream {
                guard !Task.isCancelled else { break }
                collector.append(buffer: wrapped.buffer)
            }
        }
    }

    private func startLevelMonitor() {
        levelTask?.cancel()
        levelTask = Task { [audioInput] in
            do {
                try await audioInput.beginStreaming()
            } catch {
                AppLogger.dictation.error("AudioInput beginStreaming failed: \(error.localizedDescription)")
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
