import XCTest
@testable import SayItFlow

final class LiveInjectionPolicyTests: XCTestCase {
    func testProblematicAppsUseBatchInjection() {
        XCTAssertFalse(LiveInjectionPolicy.supportsLiveTyping(bundleID: "com.todesktop.230313mzl4w4u92"))
        XCTAssertFalse(LiveInjectionPolicy.supportsLiveTyping(bundleID: "com.microsoft.VSCode"))
        XCTAssertFalse(LiveInjectionPolicy.supportsLiveTyping(bundleID: "com.apple.Terminal"))
        XCTAssertTrue(LiveInjectionPolicy.supportsLiveTyping(bundleID: "com.apple.Notes"))
    }
}
