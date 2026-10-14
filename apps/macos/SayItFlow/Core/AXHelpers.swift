import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum AXHelpers {
    static func uiElement(from ref: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXUIElement.self)
    }

    static func cgRect(from ref: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(ref, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return rect
    }

    static func processID(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    static func bundleIdentifier(forPID pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    static func bundleIdentifier(of element: AXUIElement) -> String? {
        guard let pid = processID(of: element) else { return nil }
        return bundleIdentifier(forPID: pid)
    }

    static func role(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &ref
        ) == .success else { return nil }
        return ref as? String
    }

    static func isTextInputElement(_ element: AXUIElement) -> Bool {
        guard let role = role(of: element) else { return false }
        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXTextArea",
            "AXTextField",
            "AXEditableText",
            "AXSearchField",
        ]
        if textRoles.contains(role) { return true }

        var editableRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            "AXEditable" as CFString,
            &editableRef
        ) == .success, let editable = editableRef as? Bool, editable {
            return true
        }
        return false
    }
}

/// Resolves the focused text field — supports native Cocoa, WebKit, and Electron.
enum AXFocusResolver {
    struct Diagnostics: Sendable {
        var frontBundle: String?
        var systemWideRole: String?
        var appScopedRole: String?
        var searchRole: String?
    }

    static func focusedTextElement(forPID targetPID: pid_t? = nil, diagnostics: inout Diagnostics) -> AXUIElement? {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let appPID = targetPID ?? frontmostPID
        if let appPID {
            diagnostics.frontBundle = NSRunningApplication(processIdentifier: appPID)?.bundleIdentifier
            let appElement = AXUIElementCreateApplication(appPID)
            AXUIElementSetMessagingTimeout(appElement, 0.025)
            if let element = copyFocused(from: appElement) {
                AXUIElementSetMessagingTimeout(element, 0.025)
                diagnostics.appScopedRole = AXHelpers.role(of: element)
                if AXHelpers.isTextInputElement(element) || canInsertText(into: element) {
                    return element
                }
            }

            if let window = focusedWindow(in: appElement) {
                AXUIElementSetMessagingTimeout(window, 0.025)
                if let element = findEditableElement(in: window, depth: 0) {
                    diagnostics.searchRole = AXHelpers.role(of: element)
                    return element
                }
            }
        }

        // Only query system-wide focus if no specific targetPID was requested or it matches the frontmost app.
        if targetPID == nil || targetPID == frontmostPID {
            let systemWide = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(systemWide, 0.025)
            if let element = copyFocused(from: systemWide) {
                AXUIElementSetMessagingTimeout(element, 0.025)
                if let targetPID, AXHelpers.processID(of: element) != targetPID {
                    return nil
                }
                diagnostics.systemWideRole = AXHelpers.role(of: element)
                if AXHelpers.isTextInputElement(element) || canInsertText(into: element) {
                    return element
                }
            }
        }

        return nil
    }

    static func focusedTextElement(forPID targetPID: pid_t? = nil) -> AXUIElement? {
        var diagnostics = Diagnostics()
        return focusedTextElement(forPID: targetPID, diagnostics: &diagnostics)
    }

    private static func copyFocused(from root: AXUIElement) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else { return nil }
        return AXHelpers.uiElement(from: focusedRef)
    }

    private static func focusedWindow(in app: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success, let windowRef else { return nil }
        return AXHelpers.uiElement(from: windowRef)
    }

    private static func canInsertText(into element: AXUIElement) -> Bool {
        if AXHelpers.isTextInputElement(element) { return true }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue {
            return true
        }
        if AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        ) == .success, settable.boolValue {
            return true
        }
        return false
    }

    private static func findEditableElement(in root: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 3 else { return nil }

        if let focused = copyFocused(from: root) {
            AXUIElementSetMessagingTimeout(focused, 0.02)
            if canInsertText(into: focused) {
                return focused
            }
        }
        if depth > 0 && canInsertText(into: root) {
            return root
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            root,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success, let children = childrenRef as? [AnyObject] else {
            return nil
        }

        for child in children.prefix(12) {
            guard let childRef = child as CFTypeRef?,
                  let element = AXHelpers.uiElement(from: childRef) else { continue }
            AXUIElementSetMessagingTimeout(element, 0.02)
            if let match = findEditableElement(in: element, depth: depth + 1) {
                return match
            }
        }
        return nil
    }
}
