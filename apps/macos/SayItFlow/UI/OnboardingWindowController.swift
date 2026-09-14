import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var windowDelegate: OnboardingWindowDelegate?
    private var didFinish = false

    private override init() {
        super.init()
    }

    var isPresented: Bool { window != nil }

    func present(startingAt step: SetupStep? = nil, onComplete: @escaping () -> Void) {
        didFinish = false
        let initialStep = step ?? SetupStep.firstIncompleteStep()
        let root = OnboardingView(startingAt: initialStep, onComplete: { [weak self] in
            self?.didFinish = true
            onComplete()
            self?.dismiss()
        })
        .environmentObject(AppState.shared)

        // Rebuild root when already open or "Fix Permissions…" drops the new completion handler.
        if let window {
            window.contentViewController = NSHostingController(rootView: root)
            window.centerOnVisibleScreen()
            window.presentFrontmost()
            return
        }

        let hosting = NSHostingController(rootView: root)
        let size = NSSize(width: 860, height: 600)
        let frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 800, height: 560)
        window.title = "SayItFlow Setup"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false

        let delegate = OnboardingWindowDelegate { [weak self] in
            self?.handleCloseWithoutFinish()
        }
        windowDelegate = delegate
        window.delegate = delegate

        window.setContentSize(size)
        window.centerOnVisibleScreen()
        window.presentFrontmost()
        self.window = window
    }

    func dismiss() {
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        windowDelegate = nil
    }

    private func handleCloseWithoutFinish() {
        guard !didFinish else { return }
        AppLogger.permissions.notice("Onboarding closed without Finish — recovering app state")
        AppState.shared.clearOnboardingHandlers()
        AppState.shared.showOnboarding = false
        dismiss()
        AppState.shared.enterMenuBarMode()

        // Setup incomplete — keep hotkey off until the demo step passes.
        AppState.shared.stopHotkey()
        AppState.shared.lastError = Permissions.allGranted()
            ? .pipeline("Setup incomplete — finish the test dictation to enable dictation.")
            : .permissionsIncomplete
    }
}

private final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    private let onCloseWithoutFinish: () -> Void

    init(onCloseWithoutFinish: @escaping () -> Void) {
        self.onCloseWithoutFinish = onCloseWithoutFinish
    }

    func windowWillClose(_ notification: Notification) {
        onCloseWithoutFinish()
    }
}
