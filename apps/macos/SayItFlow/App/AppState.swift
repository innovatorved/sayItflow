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
    @Published private(set) var permissionStatuses: [PermissionKind: PermissionStatus] = [:]

    var engineReady: Bool { VozEngine.shared.isDownloaded }

    let settings = AppSettings.shared
    let engineSettings = EngineSettings.shared
    private var coordinator: DictationCoordinator?
    private var hotkeyEngine: HotkeyEngine?
    private var permissionMonitorTask: Task<Void, Never>?

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
                    self?.startPermissionMonitor()
                }
            }
        )
        hotkeyEngine?.updateMode(settings.hotkeyMode)

        if Permissions.allGranted(), !showOnboarding {
            ensureHotkeyRunning()
        } else if !Permissions.allGranted() {
            lastError = .permissionsIncomplete
            startPermissionMonitor()
        }

        VozEngine.shared.refreshStatus()
    }

    func startPermissionMonitor() {
        permissionMonitorTask?.cancel()
        permissionMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { break }
                self.refreshPermissionStatuses()
                if PermissionsLogic.allGranted(statuses: self.permissionStatuses) {
                    if !self.isHotkeyRunning {
                        self.ensureHotkeyRunning()
                        try? await Task.sleep(for: .milliseconds(60))
                    }
                    if self.isHotkeyRunning {
                        self.lastError = nil
                        break
                    }
                }
            }
        }
    }

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
        let updated = Dictionary(
            uniqueKeysWithValues: PermissionKind.allCases.map { ($0, Permissions.status(for: $0)) }
        )
        if updated != permissionStatuses {
            permissionStatuses = updated
            let summary = PermissionKind.allCases
                .map { "\($0.rawValue)=\(updated[$0]?.label ?? "nil")" }
                .joined(separator: ", ")
            let ax = AXIsProcessTrusted()
            let im = CGPreflightListenEventAccess()
            let tap = Permissions.probeHotkeyTap()
            SessionTrace.log(
                "Permission statuses: \(summary) (AX=\(ax), IM=\(im), tap=\(tap))",
                category: "permissions"
            )
        }
    }

    func refreshPermissionsAndHotkey(allowDuringOnboarding: Bool = false) {
        refreshPermissionStatuses()
        if coordinator?.isSessionActive == true { return }

        guard Permissions.allGranted() else {
            stopHotkey()
            lastError = .permissionsIncomplete
            startPermissionMonitor()
            return
        }
        if lastError == .permissionsIncomplete { lastError = nil }

        if showOnboarding && !allowDuringOnboarding {
            if !isHotkeyRunning { ensureHotkeyRunning() }
            return
        }

        if isHotkeyHealthy {
            if case .pipeline = lastError { lastError = nil }
            return
        }

        hotkeyEngine?.stop()
        guard Permissions.probeHotkeyTap() else {
            lastError = .pipeline("Hotkey listener unavailable — grant Input Monitoring")
            startPermissionMonitor()
            return
        }
        if case .pipeline = lastError { lastError = nil }
        hotkeyEngine?.start()
    }

    func ensureHotkeyRunning() {
        guard Permissions.allGranted() else { return }
        if lastError == .permissionsIncomplete { lastError = nil }
        if isHotkeyHealthy {
            if case .pipeline = lastError { lastError = nil }
            return
        }
        hotkeyEngine?.stop()
        guard Permissions.probeHotkeyTap() else {
            lastError = .pipeline("Hotkey listener unavailable")
            return
        }
        if case .pipeline = lastError { lastError = nil }
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

    func openDashboard(section: MainWindowSection? = nil) {
        DashboardWindowController.shared.present(section: section)
    }

    func startHotkeyForOnboardingTry() {
        guard Permissions.allGranted() else { return }
        refreshPermissionsAndHotkey(allowDuringOnboarding: true)
    }

    func setOnboardingInjectionHandler(_ handler: ((String) -> Void)?) {
        coordinator?.onboardingInjectionHandler = handler
    }

    func clearOnboardingHandlers() {
        coordinator?.onboardingInjectionHandler = nil
    }

    func cancelDictation() {
        coordinator?.cancel(reason: "userCancel")
    }

    func shutdown() {
        coordinator?.cancel(reason: "shutdown")
        hotkeyEngine?.stop()
        S1MiniEngine.shared.stopServer()
        TranscriptHistoryStore.shared.flushSync()
    }

    func noteWords(in text: String) {
        let count = text.split { $0.isWhitespace || $0.isNewline }.count
        wordCount += count
        UserDefaults.standard.set(wordCount, forKey: "wordCount")
    }

    var statusLabel: String {
        let granted = permissionStatuses.isEmpty
            ? Permissions.allGranted()
            : PermissionsLogic.allGranted(statuses: permissionStatuses)
        if !granted { return "Permissions needed" }
        if lastError != nil { return "Error" }
        switch phase {
        case .idle: return "Ready"
        case .recording: return "Listening…"
        case .transcribing: return "Dictating…"
        case .polishing: return "Finishing…"
        case .injecting: return "Done"
        case .error: return "Error"
        }
    }

    var didPassThroughInitialSpace: Bool {
        hotkeyEngine?.didPassThroughInitialSpace == true
    }

    var isHotkeyRunning: Bool { hotkeyEngine?.hasLiveTap == true }
    var isHotkeyHealthy: Bool { hotkeyEngine?.tapIsHealthy == true }
    var hotkeyTapDegraded: Bool {
        guard let engine = hotkeyEngine else { return false }
        return engine.hasLiveTap && !engine.tapIsHealthy
    }
    var permissionsNeedAttention: Bool {
        let granted = permissionStatuses.isEmpty
            ? Permissions.allGranted()
            : PermissionsLogic.allGranted(statuses: permissionStatuses)
        guard granted else { return true }
        return hotkeyEngine?.hasLiveTap != true
    }
}
