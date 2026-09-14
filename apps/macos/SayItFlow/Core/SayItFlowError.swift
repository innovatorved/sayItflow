import Foundation

enum SayItFlowError: Error, LocalizedError, Equatable {
    case permissionsIncomplete
    case hotkeyCustomShortcutMissing
    case pipeline(String)
    case engineUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionsIncomplete:
            "Grant microphone, accessibility, and input monitoring in Settings."
        case .hotkeyCustomShortcutMissing:
            "Choose a custom push-to-talk shortcut in Dashboard."
        case .pipeline(let message):
            message
        case .engineUnavailable:
            "Speech models are not ready yet."
        }
    }
}
