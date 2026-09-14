import AppKit
import ApplicationServices
import Foundation

/// Detects user takeover (click, type, focus change) during live injection.
@MainActor
final class InjectionSessionGuard {
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var focusTask: Task<Void, Never>?
    private var pinnedElement: AXUIElement?
    private var pinnedPID: pid_t?
    private var pinnedBundleID: String?
    private var onInterrupt: ((String) -> Void)?

    func start(pinnedElement: AXUIElement?, onInterrupt: @escaping (String) -> Void) {
        stop()
        self.pinnedElement = pinnedElement
        self.pinnedPID = pinnedElement.flatMap { AXHelpers.processID(of: $0) }
        self.pinnedBundleID = pinnedElement.flatMap { AXHelpers.bundleIdentifier(of: $0) }
        self.onInterrupt = onInterrupt
        installMonitors()
    }

    /// Keystroke-only live injection — watch frontmost app without an AX pin.
    func start(bundleIdentifier: String?, onInterrupt: @escaping (String) -> Void) {
        stop()
        self.pinnedElement = nil
        self.pinnedPID = nil
        self.pinnedBundleID = bundleIdentifier
        self.onInterrupt = onInterrupt
        installMonitors()
    }

    private func installMonitors() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                guard let pinnedBundle = self.pinnedBundleID else { return }
                guard !InjectionSessionGuardLogic.isSameApplicationFamily(pinnedBundle, frontBundle) else {
                    return
                }
                self.fireInterrupt(reason: "click outside app")
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.shouldInterrupt(for: event) {
                Task { @MainActor in self.fireInterrupt(reason: "keyboard takeover") }
            }
            return event
        }

        focusTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                await MainActor.run {
                    self?.checkFocusDrift()
                }
            }
        }
    }

    func stop() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        focusTask?.cancel()
        focusTask = nil
        pinnedElement = nil
        pinnedPID = nil
        pinnedBundleID = nil
        onInterrupt = nil
    }

    private func shouldInterrupt(for event: NSEvent) -> Bool {
        if KeystrokeEmitter.isSimulated(event) { return false }
        return InjectionSessionGuardLogic.shouldInterruptForKeyDown(
            keyCode: event.keyCode,
            hotkeyMode: AppSettings.shared.hotkeyMode,
            isSimulated: false
        )
    }

    private func checkFocusDrift() {
        guard pinnedBundleID != nil || pinnedElement != nil else { return }

        if pinnedElement == nil {
            let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            guard let pinnedBundle = pinnedBundleID else { return }
            if !InjectionSessionGuardLogic.isSameApplicationFamily(pinnedBundle, frontBundle) {
                fireInterrupt(reason: "focus drift")
            }
            return
        }

        guard let pinned = pinnedElement else { return }
        guard let current = queryFocusedElement() else {
            // No focused text element at all (desktop click, modal, target app quit).
            // Returning silently left a stale pin and skipped clipboard rescue.
            fireInterrupt(reason: "focus drift")
            return
        }

        let handlesEqual = CFEqual(pinned, current)
        if handlesEqual {
            return
        }

        let currentPID = AXHelpers.processID(of: current)
        let currentBundleID = AXHelpers.bundleIdentifier(of: current)
        let currentIsTextInput = AXHelpers.isTextInputElement(current)

        if InjectionSessionGuardLogic.isGenuineFocusDrift(
            pinnedPID: pinnedPID,
            currentPID: currentPID,
            pinnedBundleID: pinnedBundleID,
            currentBundleID: currentBundleID,
            handlesEqual: false,
            currentIsTextInput: currentIsTextInput
        ) {
            fireInterrupt(reason: "focus drift")
            return
        }

        // Same app, still a text field — refresh stale AX handle (Chrome/Electron recycle).
        pinnedElement = current
        if let currentPID {
            pinnedPID = currentPID
        }
        if let currentBundleID {
            pinnedBundleID = currentBundleID
        }
    }

    private func fireInterrupt(reason: String) {
        guard onInterrupt != nil else { return }
        AppLogger.injection.notice("Injection guard abort: \(reason, privacy: .public)")
        let handler = onInterrupt
        stop()
        handler?(reason)
    }

    private func queryFocusedElement() -> AXUIElement? {
        AXFocusResolver.focusedTextElement()
    }
}
