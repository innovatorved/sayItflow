import Foundation

enum SetupStepLogic {
    static func canAdvance(
        from step: SetupStep,
        permissions: [PermissionKind: PermissionStatus],
        hotkeyReady: Bool,
        demoCompleted: Bool
    ) -> Bool {
        switch step {
        case .welcome: return true
        case .microphone, .accessibility, .inputMonitoring:
            guard let kind = step.permissionKind else { return false }
            return permissions[kind] == .granted
        case .verifyHotkey: return hotkeyReady
        case .tryDictation: return demoCompleted
        }
    }

    static func firstIncompleteStep(
        permissions: [PermissionKind: PermissionStatus],
        hotkeyReady: Bool
    ) -> SetupStep {
        for kind in PermissionKind.allCases {
            if permissions[kind] != .granted,
               let step = SetupStep.allCases.first(where: { $0.permissionKind == kind }) {
                return step
            }
        }
        if !hotkeyReady {
            return .verifyHotkey
        }
        return .tryDictation
    }
}
