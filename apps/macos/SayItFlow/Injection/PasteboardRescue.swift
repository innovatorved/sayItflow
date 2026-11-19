import AppKit
import Foundation

/// Saves and restores the full pasteboard around synthetic Cmd+V.
///
/// Safe under rapid consecutive dictations and user copies:
/// - Reuses the original user clipboard snapshot if a second paste arrives before `restoreDelay`.
/// - Verifies `pasteboard.changeCount` before restoring so a manual user Cmd+C is never clobbered.
enum PasteboardRescue {
    /// Grace period for the target app to read the pasteboard before we put the
    /// user's own clipboard back.
    static let restoreDelay: TimeInterval = 0.50

    private struct PendingRestore {
        let items: [NSPasteboardItem]
        let expectedChangeCount: Int
        let workItem: DispatchWorkItem
    }

    @MainActor
    private static var pendingRestores: [ObjectIdentifier: PendingRestore] = [:]

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

    /// Restores `items` only if the pasteboard has not been modified since `expectedChangeCount`.
    @discardableResult
    static func restoreIfUnchanged(
        _ items: [NSPasteboardItem],
        expectedChangeCount: Int,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else {
            return false
        }
        restore(items, to: pasteboard)
        return true
    }

    @MainActor
    @discardableResult
    static func paste(
        _ text: String,
        targetPID: pid_t? = nil,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        let key = ObjectIdentifier(pasteboard)

        // If a restore is already pending for this pasteboard and the user hasn't modified
        // the clipboard since our previous paste, cancel that timer and preserve the original
        // user clipboard snapshot instead of snapshotting our own previous dictated text.
        let saved: [NSPasteboardItem]
        if let pending = pendingRestores.removeValue(forKey: key) {
            pending.workItem.cancel()
            if pasteboard.changeCount == pending.expectedChangeCount {
                saved = pending.items
            } else {
                saved = snapshot(pasteboard)
            }
        } else {
            saved = snapshot(pasteboard)
        }

        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            restore(saved, to: pasteboard)
            SessionTrace.log("Pasteboard setString failed", category: "injection")
            return false
        }

        let expectedCount = pasteboard.changeCount

        guard KeystrokeEmitter.postCommandV(targetPID: targetPID) else {
            restore(saved, to: pasteboard)
            SessionTrace.log("KeystrokeEmitter postCommandV failed", category: "injection")
            return false
        }

        SessionTrace.log("Pasteboard Cmd+V posted (\(text.count) chars)", category: "injection")
        let workItem = DispatchWorkItem { [weak pasteboard] in
            MainActor.assumeIsolated {
                guard let pasteboard else { return }
                pendingRestores.removeValue(forKey: ObjectIdentifier(pasteboard))
                _ = restoreIfUnchanged(saved, expectedChangeCount: expectedCount, to: pasteboard)
            }
        }
        pendingRestores[key] = PendingRestore(
            items: saved,
            expectedChangeCount: expectedCount,
            workItem: workItem
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay, execute: workItem)
        return true
    }
}
