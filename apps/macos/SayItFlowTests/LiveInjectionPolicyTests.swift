import XCTest
@testable import SayItFlow

final class LiveInjectionPolicyTests: XCTestCase {
    func testPrefersPasteForAntigravityAndElectronApps() {
        XCTAssertTrue(InjectionTargetPolicy.prefersPaste(bundleID: "com.google.antigravity"))
        XCTAssertTrue(InjectionTargetPolicy.prefersPaste(bundleID: "com.microsoft.VSCode"))
        XCTAssertTrue(InjectionTargetPolicy.prefersPaste(bundleID: "com.exafunction.windsurf"))
        XCTAssertFalse(InjectionTargetPolicy.prefersPaste(bundleID: "com.apple.Notes"))
    }
}
