import AppKit
import Carbon
import CoreGraphics
import Foundation

/// Simulates native keystrokes for live dictation injection.
@MainActor
enum KeystrokeEmitter {
    /// Tag on all simulated CGEvents so InjectionSessionGuard ignores them.
    nonisolated static let simulatedEventTag: Int64 = 998_877

    private static let interKeyDelay: useconds_t = 1_000
    private static let eventPostLocation: CGEventTapLocation = .cgSessionEventTap

    /// Apps where Shift+Option+Left word boundaries differ from standard text fields.
    static let wordSelectDenylist: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.tinyspeck.slackmacgap",
        "dev.warp.Warp-Stable",
    ]

    static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    static func prefersCharacterSelect() -> Bool {
        guard let bundle = frontmostBundleID() else { return false }
        if bundle.hasPrefix("com.todesktop.") { return true }
        return wordSelectDenylist.contains(bundle)
    }

    static func isSimulated(_ event: NSEvent) -> Bool {
        event.cgEvent.map {
            InjectionSessionGuardLogic.isSimulatedKeystroke(
                userData: $0.getIntegerValueField(.eventSourceUserData),
                tag: simulatedEventTag
            )
        } ?? false
    }

    /// One UTF-16 unit per grapheme so event count matches String.count for selectBackward.
    static func graphemeUnits(for text: String) -> [[UniChar]] {
        text.map { Array(String($0).utf16) }
    }

    @discardableResult
    static func typeText(_ text: String, targetPID: pid_t? = nil) -> Bool {
        guard !text.isEmpty else { return true }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

        let safeText = text.replacingOccurrences(of: "\r\n", with: " ")
                           .replacingOccurrences(of: "\n", with: " ")
                           .replacingOccurrences(of: "\r", with: " ")
        guard !safeText.isEmpty else { return true }

        for unit in graphemeUnits(for: safeText) {
            var chars = unit
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }
            keyDown.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            keyUp.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            tag(keyDown)
            tag(keyUp)
            keyDown.post(tap: eventPostLocation)
            keyUp.post(tap: eventPostLocation)
            usleep(interKeyDelay)
        }
        return true
    }

    @discardableResult
    static func selectBackward(wordCount: Int) -> Bool {
        guard wordCount > 0 else { return true }
        for _ in 0..<wordCount {
            guard postKey(keyCode: CGKeyCode(kVK_LeftArrow), flags: [.maskShift, .maskAlternate]) else {
                return false
            }
        }
        return true
    }

    @discardableResult
    static func selectBackward(characterCount: Int) -> Bool {
        guard characterCount > 0 else { return true }
        for _ in 0..<characterCount {
            guard postKey(keyCode: CGKeyCode(kVK_LeftArrow), flags: [.maskShift]) else {
                return false
            }
        }
        return true
    }

    /// How many units may be selected backward without touching text that was already
    /// in the field before dictation. When the budget is unknown, refuse to select.
    static func clampedBackwardUnits(requested: Int, budget: Int?) -> Int {
        guard let budget, budget > 0, requested > 0 else { return 0 }
        return min(requested, budget)
    }

    /// Word-select mode can overshoot a character budget; cap word steps too.
    static func clampedWordUnits(raw: String, budget: Int) -> Int {
        guard budget > 0 else { return 0 }
        let words = raw.split(whereSeparator: { $0.isWhitespace }).count
        return min(max(words, 1), budget)
    }

    /// Select and replace typed text; maxBackwardUnits caps selection at this session's field budget.
    @discardableResult
    static func selectAndReplace(
        raw: String,
        injectedLength: Int,
        polished: String,
        maxBackwardUnits: Int?
    ) -> Bool {
        let clamped = clampedBackwardUnits(requested: injectedLength, budget: maxBackwardUnits)
        guard clamped > 0 else { return false }
        let selected: Bool
        // Character-level select (Shift+Left) is accurate across all apps and punctuation styles.
        selected = selectBackward(characterCount: clamped)
        guard selected else { return false }
        return replaceSelection(with: polished)
    }

    @discardableResult
    static func deleteSelection() -> Bool {
        postKey(keyCode: CGKeyCode(kVK_Delete), flags: [])
    }

    /// Typing an empty string is a no-op, so an empty replacement has to delete.
    @discardableResult
    static func replaceSelection(with text: String) -> Bool {
        if text.isEmpty {
            return deleteSelection()
        }
        if text.count > 15 {
            return PasteboardRescue.paste(text)
        }
        return typeText(text)
    }

    @discardableResult
    static func postCommandV(targetPID: pid_t? = nil) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        tag(keyDown)
        tag(keyUp)

        keyDown.post(tap: eventPostLocation)
        keyUp.post(tap: eventPostLocation)
        return true
    }

    private static func tag(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: simulatedEventTag)
    }

    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags, targetPID: pid_t? = nil) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        keyDown.flags = flags
        keyUp.flags = flags
        tag(keyDown)
        tag(keyUp)

        keyDown.post(tap: eventPostLocation)
        keyUp.post(tap: eventPostLocation)
        usleep(interKeyDelay)
        return true
    }
}
