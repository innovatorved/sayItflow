import Foundation

enum SetupStep: Int, CaseIterable, Identifiable {
    case welcome
    case microphone
    case accessibility
    case inputMonitoring
    case verifyHotkey
    case tryDictation

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome to SayItFlow"
        case .microphone: "Allow Microphone"
        case .accessibility: "Enable Accessibility"
        case .inputMonitoring: "Enable Input Monitoring"
        case .verifyHotkey: "Verify Hotkey"
        case .tryDictation: "Try It"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "Push-to-talk dictation, on your Mac."
        case .microphone: PermissionKind.microphone.detail
        case .accessibility: PermissionKind.accessibility.detail
        case .inputMonitoring: PermissionKind.inputMonitoring.detail
        case .verifyHotkey: "Confirm global push-to-talk is ready."
        case .tryDictation: "Hold Spacebar, speak, then release."
        }
    }

    var permissionKind: PermissionKind? {
        switch self {
        case .microphone: .microphone
        case .accessibility: .accessibility
        case .inputMonitoring: .inputMonitoring
        default: nil
        }
    }

    @MainActor
    static func firstIncompleteStep() -> SetupStep {
        var permissions: [PermissionKind: PermissionStatus] = [:]
        for kind in PermissionKind.allCases {
            permissions[kind] = Permissions.status(for: kind)
        }
        let hotkeyReady = Permissions.probeHotkeyTap()
        return SetupStepLogic.firstIncompleteStep(
            permissions: permissions,
            hotkeyReady: hotkeyReady
        )
    }
}
