import ApplicationServices
import Carbon
import Foundation

enum InjectionSessionGuardLogic {
    private static let processSuffixes = [
        ".helper",
        ".renderer",
        ".gpu",
        ".plugin",
        ".framework",
    ]

    static func isSimulatedKeystroke(userData: Int64, tag: Int64) -> Bool {
        userData == tag
    }

    /// Returns true when a local keyDown should abort live injection.
    static func shouldInterruptForKeyDown(
        keyCode: UInt16,
        hotkeyMode: HotkeyMode,
        isSimulated: Bool
    ) -> Bool {
        if isSimulated { return false }
        switch hotkeyMode {
        case .holdSpace:
            return keyCode != 49
        case .fnKey:
            return keyCode != 63
        case .rightOption:
            return keyCode != 61 && keyCode != 62
        case .custom:
            return true
        }
    }

    /// Normalizes Chrome/Electron helper/renderer bundle IDs to their parent app.
    static func normalizedApplicationBundle(_ bundleID: String) -> String {
        var base = bundleID
        var changed = true
        while changed {
            changed = false
            for suffix in processSuffixes where base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                changed = true
                break
            }
        }
        return base
    }

    /// True when both bundle IDs belong to the same application (incl. multi-process helpers).
    static func isSameApplicationFamily(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        if lhs == rhs { return true }
        if lhs.hasPrefix("\(rhs).") || rhs.hasPrefix("\(lhs).") { return true }
        return normalizedApplicationBundle(lhs) == normalizedApplicationBundle(rhs)
    }

    /// True when focus genuinely left the pinned app (not AX handle recycling in the same app).
    static func isGenuineFocusDrift(
        pinnedPID: pid_t?,
        currentPID: pid_t?,
        pinnedBundleID: String?,
        currentBundleID: String?,
        handlesEqual: Bool,
        currentIsTextInput: Bool
    ) -> Bool {
        if handlesEqual { return false }

        if isSameApplicationFamily(pinnedBundleID, currentBundleID) {
            // Same app, but focus moved to something that is not a text field (toolbar
            // button, menu, sidebar). That is real drift — re-pinning here would point
            // injection at a non-editable element.
            return !currentIsTextInput
        }

        if pinnedBundleID != nil, currentBundleID != nil {
            return true
        }

        guard let pinnedPID, let currentPID else { return false }
        if pinnedPID == currentPID { return false }

        // Different PID with unknown bundle — assume same multi-process app; refresh handle.
        return false
    }
}

enum SecureInputChecker {
    static func isActive() -> Bool {
        IsSecureEventInputEnabled()
    }
}
