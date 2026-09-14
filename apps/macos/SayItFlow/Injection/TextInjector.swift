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

        ensureAppActive(pid: options.pinnedPID)

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

        ensureAppActive(pid: options.pinnedPID)
        if insertViaPaste(text, targetPID: options.pinnedPID) {
            SessionTrace.log("Injected via paste fallback successfully", category: "injection")
            return
        }

        if KeystrokeEmitter.typeText(text, targetPID: options.pinnedPID) {
            SessionTrace.log("Injected via KeystrokeEmitter typing successfully", category: "injection")
            return
        }

        SessionTrace.log("All injection strategies failed — copying to clipboard", category: "injection")
        copyWithNotification(text)
        throw TextInjectionError.insertionFailed
    }

    private func ensureAppActive(pid: pid_t?) {
        guard let pid else { return }
        let app = NSRunningApplication(processIdentifier: pid)
        guard let app else { return }
        if !app.isActive {
            app.activate(options: [.activateIgnoringOtherApps])
            let deadline = CFAbsoluteTimeGetCurrent() + 0.15
            while !app.isActive && CFAbsoluteTimeGetCurrent() < deadline {
                usleep(10_000)
            }
            usleep(25_000)
        }
    }

    private func insertViaAccessibility(_ text: String, targetPID: pid_t?) -> Bool {
        guard let focused = AXFocusResolver.focusedTextElement(forPID: targetPID) else { return false }

        if insertAtCaret(into: focused, text: text) {
            return true
        }
        if insertIntoEmptyField(focused, text: text) {
            return true
        }
        return false
    }

    private func insertAtCaret(into element: AXUIElement, text: String) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    private func insertIntoEmptyField(_ element: AXUIElement, text: String) -> Bool {
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
