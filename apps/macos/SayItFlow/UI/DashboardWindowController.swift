import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    static let shared = DashboardWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    var isPresented: Bool { window != nil }

    func present() {
        AppState.shared.enterSetupMode()
        AppState.shared.refreshPermissionStatuses()

        if let window {
            window.centerOnVisibleScreen()
            window.presentFrontmost()
            return
        }

        let root = DashboardView()
            .environmentObject(AppState.shared)

        let hosting = NSHostingController(rootView: root)
        let size = NSSize(width: 920, height: 640)
        let frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SayItFlow"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(size)
        window.centerOnVisibleScreen()
        window.presentFrontmost()
        self.window = window
    }

    func dismiss() {
        AppState.shared.clearOnboardingHandlers()
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        // Back to menu-bar mode when the window closes (LSUIElement).
        AppState.shared.enterMenuBarMode()
    }

    func windowWillClose(_ notification: Notification) {
        dismiss()
    }
}

extension NSWindow {
    /// Re-front on the next run loop — menu bar dismiss and activation-policy switch steal focus.
    func presentFrontmost() {
        collectionBehavior.insert(.moveToActiveSpace)
        raiseNow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.centerOnVisibleScreen()
            self.raiseNow()
        }
    }

    /// Centers on the screen that contains the mouse (or main), clamped to visibleFrame.
    func centerOnVisibleScreen() {
        let screen = screen
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = self.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
        setFrame(frame, display: true)
    }

    private func raiseNow() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}
