import AVFoundation
import AppKit
@preconcurrency import ApplicationServices

enum PermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    var detail: String {
        switch self {
        case .microphone:
            "Required to capture your voice for dictation."
        case .accessibility:
            "Required for global hotkeys and inserting text at the cursor."
        case .inputMonitoring:
            "Required for the global push-to-talk hotkey listener."
        }
    }

    var settingsAnchor: String {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
    }

    /// System Settings renamed the pane bundle to `com.apple.settings.PrivacySecurity.extension`
    /// but still registers only the older `x-apple.systempreferences` scheme — there is no
    /// `x-apple.systemsettings` handler. Modern pane first, legacy pane as the fallback.
    var settingsURLCandidates: [URL] {
        ["com.apple.settings.PrivacySecurity.extension", "com.apple.preference.security"]
            .compactMap { URL(string: "x-apple.systempreferences:\($0)?\(settingsAnchor)") }
    }
}

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
    /// User was prompted; grant requires toggling SayItFlow in System Settings.
    case needsSettings

    var badgeKind: StatusBadgeKind {
        switch self {
        case .granted: .granted
        case .denied: .denied
        case .notDetermined: .pending
        case .needsSettings: .warning
        }
    }

    var label: String {
        switch self {
        case .granted: "Granted"
        case .denied: "Denied"
        case .notDetermined: "Not Set"
        case .needsSettings: "Open Settings"
        }
    }
}

enum Permissions {
    @MainActor
    static func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        case .accessibility:
            if AXIsProcessTrusted() {
                return .granted
            }
            if UserDefaults.standard.bool(forKey: "accessibilityPromptShown") {
                return .needsSettings
            }
            return .notDetermined
        case .inputMonitoring:
            if CGPreflightListenEventAccess() {
                return .granted
            }
            if UserDefaults.standard.bool(forKey: "inputMonitoringPromptShown") {
                return .needsSettings
            }
            return .notDetermined
        }
    }

    @MainActor
    static func allGranted() -> Bool {
        var statuses: [PermissionKind: PermissionStatus] = [:]
        for kind in PermissionKind.allCases {
            statuses[kind] = status(for: kind)
        }
        return PermissionsLogic.allGranted(statuses: statuses)
    }

    /// TCC dialogs must be requested on the main thread (sayitdev pattern).
    @MainActor
    static func request(_ kind: PermissionKind) async -> PermissionStatus {
        let current = status(for: kind)
        if current == .granted { return .granted }

        switch kind {
        case .microphone:
            return await requestMicrophone()
        case .accessibility:
            return requestAccessibility()
        case .inputMonitoring:
            return requestInputMonitoring()
        }
    }

    @MainActor
    private static func requestMicrophone() async -> PermissionStatus {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return .granted
        }
        let granted = await requestMicrophoneAccess()
        return granted ? .granted : openSettingsForUnresolved(.microphone)
    }

    /// TCC only ever shows its dialog once. If the request came back ungranted the user
    /// has to flip the switch themselves, so send them there instead of leaving the
    /// setup step waiting for a prompt that will never reappear.
    @MainActor
    private static func openSettingsForUnresolved(_ kind: PermissionKind) -> PermissionStatus {
        let current = status(for: kind)
        guard current != .granted else { return .granted }
        openSettings(for: kind)
        return current == .denied ? .needsSettings : current
    }

    /// Walks the deep links in order, then falls back to just launching System Settings
    /// so the user is never left staring at an unhandled-URL alert.
    @MainActor
    static func openSettings(for kind: PermissionKind) {
        for url in kind.settingsURLCandidates where NSWorkspace.shared.open(url) {
            return
        }
        AppLogger.permissions.notice(
            "Settings deep link failed for \(kind.rawValue, privacy: .public) — opening System Settings"
        )
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// `@concurrent` + `@Sendable`: a plain nonisolated `async` helper inherits the
    /// caller's executor, so being called from `@MainActor` bakes a main-actor check
    /// into the TCC handler. TCC answers on a background queue and the check traps.
    @concurrent
    private static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.main.async {
                AVCaptureDevice.requestAccess(for: .audio) { @Sendable ok in
                    cont.resume(returning: ok)
                }
            }
        }
    }

    @MainActor
    private static func requestAccessibility() -> PermissionStatus {
        UserDefaults.standard.set(true, forKey: "accessibilityPromptShown")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !AXIsProcessTrusted() {
            openSettings(for: .accessibility)
        }
        return status(for: .accessibility)
    }

    @MainActor
    private static func requestInputMonitoring() -> PermissionStatus {
        UserDefaults.standard.set(true, forKey: "inputMonitoringPromptShown")
        CGRequestListenEventAccess()
        if !CGPreflightListenEventAccess() {
            openSettings(for: .inputMonitoring)
        }
        return status(for: .inputMonitoring)
    }

    @MainActor
    static func nextUngrantedKind() -> PermissionKind? {
        PermissionKind.allCases.first { status(for: $0) != .granted }
    }

    @MainActor
    static func requestNextUngranted() async -> PermissionKind? {
        guard let kind = PermissionKind.allCases.first(where: { status(for: $0) != .granted }) else {
            return nil
        }
        _ = await request(kind)
        return kind
    }

    /// Validates Accessibility + Input Monitoring by creating a short-lived event tap.
    static func probeHotkeyTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        return true
    }
}
