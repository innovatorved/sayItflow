import Foundation
import Combine
import SwiftUI
import AppKit
import KeyboardShortcuts

enum DictationPhase: Equatable {
    case idle
    case recording
    case transcribing
    case polishing
    case injecting
    case error(String)
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: DictationPhase = .idle
    @Published var partialTranscript = ""
    @Published var hudMessage = ""
    @Published var wordCount: Int
    @Published var showOnboarding = false
    @Published var lastError: SayItFlowError?
    @Published var engineReady = false
    @Published var sttEngineName = "Voz (Neural Engine)"
    @Published var vozModelReady = false
    @Published var vozIsDownloading = false
    @Published var vozDownloadProgress: Double = 0
    @Published var modelSetupMessage = ""
    @Published var modelSetupProgress: Double = 0
    @Published var modelSetupModelName = "Voz Core ML (Neural Engine)"
    @Published var modelSetupFailed = false
    @Published private(set) var permissionStatuses: [PermissionKind: PermissionStatus] = [:]

    let settings = AppSettings.shared
    let engineSettings = EngineSettings.shared
    private var coordinator: DictationCoordinator?
    private var hotkeyEngine: HotkeyEngine?

    private init() {
        wordCount = UserDefaults.standard.integer(forKey: "wordCount")
    }

    func bootstrap() {
        refreshPermissionStatuses()
        showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingComplete")

        let coordinator = DictationCoordinator(appState: self)
        self.coordinator = coordinator
        hotkeyEngine = HotkeyEngine(
            handler: { [weak coordinator] event in
                Task { @MainActor in
                    coordinator?.handleHotkey(event)
                }
            },
            onTapFailed: { [weak self] message in
                Task { @MainActor in
                    AppLogger.hotkey.error("Event tap failed: \(message, privacy: .public)")
                    self?.lastError = .pipeline(message)
                    self?.openOnboarding()
                }
            }
        )
        hotkeyEngine?.updateMode(settings.hotkeyMode)

        if Permissions.allGranted(), !showOnboarding {
            ensureHotkeyRunning()
        } else if !Permissions.allGranted() {
            lastError = .permissionsIncomplete
        }

        checkVozModelStatus()
        Task {
            if S1MiniEngine.shared.isDownloaded && S1MiniEngine.shared.isEnabled {
                await S1MiniEngine.shared.ensureServerRunning()
            }
        }
    }

    func checkVozModelStatus() {
        VozEngine.shared.refreshStatus()
        vozModelReady = VozEngine.shared.isDownloaded
        engineReady = vozModelReady
        if vozModelReady {
            modelSetupMessage = "Voz Model Ready on Neural Engine"
            modelSetupProgress = 1.0
            Task {
                try? await VozEngine.shared.warmUp()
            }
        } else {
            modelSetupMessage = "Voz model not downloaded (467 MB)"
            modelSetupProgress = 0
        }
    }

    func downloadVozModel() {
        guard !vozIsDownloading else { return }
        vozIsDownloading = true
        modelSetupFailed = false
        modelSetupMessage = "Downloading Voz Neural Engine Model (467 MB)…"
        modelSetupProgress = 0.05

        Task {
            do {
                try await VozEngine.shared.downloadModel()
                self.vozIsDownloading = false
                self.vozModelReady = true
                self.engineReady = true
                self.modelSetupMessage = "Voz Model Ready on Neural Engine"
                self.modelSetupProgress = 1.0
            } catch {
                self.vozIsDownloading = false
                self.modelSetupFailed = true
                self.modelSetupMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    func startModelSetup() async {
        downloadVozModel()
    }

    func retryModelSetup() {
        downloadVozModel()
    }

    static var isLocalEngineAvailable: Bool { true }

    func enterSetupMode() {
        NSApp.setActivationPolicy(.regular)
    }

    func enterMenuBarMode() {
        NSApp.setActivationPolicy(.accessory)
    }

    func onboardingCompleted() {
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        showOnboarding = false
        coordinator?.onboardingInjectionHandler = nil
        coordinator?.onboardingLiveUpdateHandler = nil
        coordinator?.onboardingLivePrefixProvider = nil
        if lastError == .permissionsIncomplete { lastError = nil }
        enterMenuBarMode()
        refreshPermissionsAndHotkey()
    }

    func refreshHotkeyMode() {
        hotkeyEngine?.updateMode(settings.hotkeyMode)
        if settings.hotkeyMode == .custom, KeyboardShortcuts.getShortcut(for: .pushToTalk) == nil {
            lastError = .hotkeyCustomShortcutMissing
        } else if lastError == .hotkeyCustomShortcutMissing {
            lastError = nil
        }
    }

    func refreshPermissionStatuses() {
        permissionStatuses = Dictionary(
            uniqueKeysWithValues: PermissionKind.allCases.map { ($0, Permissions.status(for: $0)) }
        )
    }

    func refreshPermissionsAndHotkey(allowDuringOnboarding: Bool = false) {
        refreshPermissionStatuses()
        if coordinator?.isSessionActive == true { return }

        guard Permissions.allGranted() else {
            stopHotkey()
            lastError = .permissionsIncomplete
            return
        }
        if lastError == .permissionsIncomplete { lastError = nil }

        if showOnboarding && !allowDuringOnboarding {
            if !isHotkeyRunning { ensureHotkeyRunning() }
            return
        }

        hotkeyEngine?.stop()
        guard Permissions.probeHotkeyTap() else {
            lastError = .pipeline("Hotkey listener unavailable — grant Input Monitoring")
            return
        }
        hotkeyEngine?.start()
    }

    func ensureHotkeyRunning() {
        guard Permissions.allGranted() else { return }
        if lastError == .permissionsIncomplete { lastError = nil }
        if isHotkeyRunning { return }
        hotkeyEngine?.stop()
        guard Permissions.probeHotkeyTap() else {
            lastError = .pipeline("Hotkey listener unavailable")
            return
        }
        hotkeyEngine?.start()
    }

    func stopHotkey() { hotkeyEngine?.stop() }

    func openOnboarding(startingAt step: SetupStep? = nil) {
        showOnboarding = true
        enterSetupMode()
        if !Permissions.allGranted() { stopHotkey() }
        OnboardingWindowController.shared.present(startingAt: step) {
            self.onboardingCompleted()
        }
    }

    func openDashboard() {
        DashboardWindowController.shared.present()
    }

    func startHotkeyForOnboardingTry() {
        guard Permissions.allGranted() else { return }
        refreshPermissionsAndHotkey(allowDuringOnboarding: true)
    }

    func setOnboardingInjectionHandler(_ handler: ((String) -> Void)?) {
        coordinator?.onboardingInjectionHandler = handler
    }

    func setOnboardingLiveHandlers(
        prefix: @escaping () -> String,
        update: @escaping (String) -> Void,
        onComplete: ((String) -> Void)? = nil
    ) {
        coordinator?.onboardingLivePrefixProvider = prefix
        coordinator?.onboardingLiveUpdateHandler = update
        if let onComplete {
            coordinator?.onboardingInjectionHandler = onComplete
        }
    }

    func clearOnboardingHandlers() {
        coordinator?.onboardingInjectionHandler = nil
        coordinator?.onboardingLiveUpdateHandler = nil
        coordinator?.onboardingLivePrefixProvider = nil
    }

    func cancelDictation() {
        coordinator?.cancel(reason: "userCancel")
    }

    func shutdown() {
        coordinator?.cancel(reason: "shutdown")
        hotkeyEngine?.stop()
        S1MiniEngine.shared.stopServer()
    }

    func noteWords(in text: String) {
        let count = text.split { $0.isWhitespace || $0.isNewline }.count
        wordCount += count
        UserDefaults.standard.set(wordCount, forKey: "wordCount")
    }

    var statusLabel: String {
        if !Permissions.allGranted() { return "Permissions needed" }
        if let lastError { return "Error" }
        switch phase {
        case .idle: return "Ready"
        case .recording: return "Listening…"
        case .transcribing: return "Dictating…"
        case .polishing: return "Finishing…"
        case .injecting: return "Done"
        case .error: return "Error"
        }
    }

    var isHotkeyRunning: Bool { hotkeyEngine?.hasLiveTap == true }
    var isHotkeyHealthy: Bool { hotkeyEngine?.tapIsHealthy == true }
    var hotkeyTapDegraded: Bool {
        guard let engine = hotkeyEngine else { return false }
        return engine.hasLiveTap && !engine.tapIsHealthy
    }
    var permissionsNeedAttention: Bool {
        guard Permissions.allGranted() else { return false }
        if hotkeyEngine?.hasLiveTap == true { return false }
        return !Permissions.probeHotkeyTap()
    }
}
