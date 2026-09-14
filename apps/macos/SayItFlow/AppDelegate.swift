import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didBecomeActiveObserver: NSObjectProtocol?

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        if Self.isRunningUnderXCTest {
            NSApp.setActivationPolicy(.regular)
            return
        }
        enforceSingleInstance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isRunningUnderXCTest {
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        AppState.shared.bootstrap()

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppState.shared.refreshPermissionsAndHotkey(
                    allowDuringOnboarding: AppState.shared.showOnboarding
                )
            }
        }

        if AppState.shared.showOnboarding {
            AppState.shared.enterSetupMode()
            let startStep = SetupStep.firstIncompleteStep()
            OnboardingWindowController.shared.present(startingAt: startStep) {
                AppState.shared.onboardingCompleted()
            }
        } else {
            AppState.shared.enterMenuBarMode()
            AppState.shared.refreshPermissionsAndHotkey()
            AppState.shared.openDashboard()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // LSUIElement — reopen shows dashboard since there's no Dock window to raise.
        if AppState.shared.showOnboarding {
            AppState.shared.openOnboarding()
        } else {
            AppState.shared.openDashboard()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionTrace.log("applicationWillTerminate", category: "app")
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
        AppState.shared.shutdown()
    }

    private func enforceSingleInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != pid }
        if let existing = others.first {
            existing.activate()
            NSApp.terminate(nil)
        }
    }
}
