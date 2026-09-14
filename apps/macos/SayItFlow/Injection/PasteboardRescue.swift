import AppKit
import Foundation

/// Saves and restores the full pasteboard around synthetic Cmd+V.
enum PasteboardRescue {
    /// Grace period for the target app to read the pasteboard before we put the
    /// user's own clipboard back.
    static let restoreDelay: TimeInterval = 0.50

    /// Deep-copies every item and type currently on the pasteboard.
    static func snapshot(_ pasteboard: NSPasteboard = .general) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }

    /// Throttle callers to longer than restoreDelay or the snapshot captures dictated text.
    @MainActor
    @discardableResult
    static func paste(
        _ text: String,
        targetPID: pid_t? = nil,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            restore(saved, to: pasteboard)
            SessionTrace.log("Pasteboard setString failed", category: "injection")
            return false
        }

        guard KeystrokeEmitter.postCommandV(targetPID: targetPID) else {
            restore(saved, to: pasteboard)
            SessionTrace.log("KeystrokeEmitter postCommandV failed", category: "injection")
            return false
        }

        SessionTrace.log("Pasteboard Cmd+V posted (\(text.count) chars)", category: "injection")
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            restore(saved, to: pasteboard)
        }
        return true
    }
}
