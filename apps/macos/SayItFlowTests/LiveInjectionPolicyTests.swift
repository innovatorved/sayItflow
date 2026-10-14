import XCTest
@testable import SayItFlow

final class LiveInjectionPolicyTests: XCTestCase {
    func testProblematicAppsUseBatchInjection() {
        XCTAssertFalse(LiveInjectionPolicy.supportsLiveTyping(bundleID: "com.todesktop.230313mzl4w4u92"))
        XCTAssertFalse(LiveInjectionPolicy.supportsLiveTyping(bundleID: "com.microsoft.VSCode"))
        XCTAssertFalse(LiveInjectionPolicy.supportsLiveTyping(bundleID: "com.google.antigravity"))
        XCTAssertFalse(LiveInjectionPolicy.supportsLiveTyping(bundleID: "com.apple.Terminal"))
        XCTAssertTrue(LiveInjectionPolicy.supportsLiveTyping(bundleID: "com.apple.Notes"))
    }

    func testPrefersPasteForAntigravityAndElectronApps() {
        XCTAssertTrue(InjectionTargetPolicy.prefersPaste(bundleID: "com.google.antigravity"))
        XCTAssertTrue(InjectionTargetPolicy.prefersPaste(bundleID: "com.microsoft.VSCode"))
        XCTAssertTrue(InjectionTargetPolicy.prefersPaste(bundleID: "com.exafunction.windsurf"))
        XCTAssertFalse(InjectionTargetPolicy.prefersPaste(bundleID: "com.apple.Notes"))
    }
}
