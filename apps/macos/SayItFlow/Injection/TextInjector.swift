import AppKit
import ApplicationServices
import Foundation

enum TextInjectionError: Error, LocalizedError, Equatable {
    case accessibilityDenied
    case noFocusedElement
    case insertionFailed
    case pasteFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied: "Accessibility permission required for text injection"
        case .noFocusedElement: "No focused text field found"
        case .insertionFailed: "Could not insert text — copied to clipboard"
        case .pasteFailed: "Could not paste text — copied to clipboard"
        }
    }
}

struct TextInjectionOptions: Equatable {
    var pinnedPID: pid_t?
    /// Electron/Monaco editors — AX selected-text often fails; paste at pinned app after activate.
    var preferPaste: Bool = false
}

/// AX must run on main — off-main races focus changes.
@MainActor
struct TextInjector {
    func inject(_ text: String, options: TextInjectionOptions = TextInjectionOptions()) throws {
        guard AXIsProcessTrusted() else {
            copyWithNotification(text)
            throw TextInjectionError.accessibilityDenied
        }

        SessionTrace.log(
            "TextInjector.inject called (\(text.count) chars, preferPaste=\(options.preferPaste), pinnedPID=\(options.pinnedPID ?? -1))",
            category: "injection"
        )

        // Only activate and wait if the target application is not already frontmost
        if activatePinnedApp(pid: options.pinnedPID) {
            usleep(35_000)
        }

        if options.preferPaste {
            if insertViaPaste(text, targetPID: options.pinnedPID) {
                SessionTrace.log("Injected via preferPaste successfully", category: "injection")
                return
            }
        }

        if insertViaAccessibility(text, targetPID: options.pinnedPID) {
            SessionTrace.log("Injected via Accessibility successfully", category: "injection")
            return
        }

        // Accessibility failed or not supported in this app — try Cmd+V paste
        if activatePinnedApp(pid: options.pinnedPID) {
            usleep(25_000)
        }
        if insertViaPaste(text, targetPID: options.pinnedPID) {
            SessionTrace.log("Injected via paste fallback successfully", category: "injection")
            return
        }

        // Paste fallback failed — try simulated typing
        if activatePinnedApp(pid: options.pinnedPID) {
            usleep(20_000)
        }
        if KeystrokeEmitter.typeText(text, targetPID: options.pinnedPID) {
            SessionTrace.log("Injected via KeystrokeEmitter typing successfully", category: "injection")
            return
        }

        SessionTrace.log("All injection strategies failed — copying to clipboard", category: "injection")
        copyWithNotification(text)
        throw TextInjectionError.insertionFailed
    }

    @discardableResult
    private func activatePinnedApp(pid: pid_t?) -> Bool {
        guard let pid else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard pid != ownPID else { return false }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            return false
        }
        let app = NSRunningApplication(processIdentifier: pid)
        app?.activate(options: [.activateIgnoringOtherApps])
        return true
    }

    private func insertViaAccessibility(_ text: String, targetPID: pid_t?) -> Bool {
        guard let focused = AXFocusResolver.focusedTextElement(forPID: targetPID) else { return false }
        let spaced = smartSpacedText(text, for: focused)

        if insertAtCaret(into: focused, text: spaced) {
            return true
        }
        if insertIntoEmptyField(focused, text: text) {
            return true
        }
        return false
    }

    private func smartSpacedText(_ text: String, for element: AXUIElement) -> String {
        guard let first = text.first, !first.isWhitespace else { return text }
        var rangeRef: CFTypeRef?
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef, CFGetTypeID(rangeVal) == AXValueGetTypeID(),
              AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let existing = valueRef as? String else {
            return text
        }
        var cfRange = CFRange()
        guard AXValueGetValue(unsafeBitCast(rangeVal, to: AXValue.self), .cfRange, &cfRange),
              cfRange.location > 0 else {
            return text
        }
        let utf16 = existing.utf16
        guard cfRange.location <= utf16.count else { return text }
        let idx = utf16.index(utf16.startIndex, offsetBy: cfRange.location - 1)
        if let scalar = UnicodeScalar(utf16[idx]),
           !CharacterSet.whitespacesAndNewlines.contains(scalar),
           scalar != "(" && scalar != "[" && scalar != "{" && scalar != "\"" && scalar != "/" {
            return " " + text
        }
        return text
    }

    private func insertAtCaret(into element: AXUIElement, text: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else {
            return false
        }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    private func insertIntoEmptyField(_ element: AXUIElement, text: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else {
            return false
        }
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success else { return false }
        let existing = (valueRef as? String) ?? ""
        guard existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    private func insertViaPaste(_ text: String, targetPID: pid_t?) -> Bool {
        PasteboardRescue.paste(text, targetPID: targetPID)
    }

    private func copyWithNotification(_ text: String) {
        InjectionFallback.copyToClipboardWithFeedback(text)
    }
}
