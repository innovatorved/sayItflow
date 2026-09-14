import XCTest
@testable import SayItFlow

final class InjectionSessionGuardLogicTests: XCTestCase {
    func testSimulatedKeystrokeMatchesTag() {
        XCTAssertTrue(
            InjectionSessionGuardLogic.isSimulatedKeystroke(
                userData: KeystrokeEmitter.simulatedEventTag,
                tag: KeystrokeEmitter.simulatedEventTag
            )
        )
        XCTAssertFalse(
            InjectionSessionGuardLogic.isSimulatedKeystroke(userData: 0, tag: KeystrokeEmitter.simulatedEventTag)
        )
    }

    func testShouldNotInterruptSimulatedKeyDown() {
        XCTAssertFalse(
            InjectionSessionGuardLogic.shouldInterruptForKeyDown(
                keyCode: 0,
                hotkeyMode: .holdSpace,
                isSimulated: true
            )
        )
    }

    func testShouldNotInterruptSpaceHotkey() {
        XCTAssertFalse(
            InjectionSessionGuardLogic.shouldInterruptForKeyDown(
                keyCode: 49,
                hotkeyMode: .holdSpace,
                isSimulated: false
            )
        )
        XCTAssertTrue(
            InjectionSessionGuardLogic.shouldInterruptForKeyDown(
                keyCode: 1,
                hotkeyMode: .holdSpace,
                isSimulated: false
            )
        )
    }

    func testSameApplicationFamilyMatchesExactBundle() {
        XCTAssertTrue(
            InjectionSessionGuardLogic.isSameApplicationFamily(
                "com.google.Chrome",
                "com.google.Chrome"
            )
        )
    }

    func testSameApplicationFamilyMatchesChromeHelper() {
        XCTAssertTrue(
            InjectionSessionGuardLogic.isSameApplicationFamily(
                "com.google.Chrome",
                "com.google.Chrome.helper"
            )
        )
        XCTAssertTrue(
            InjectionSessionGuardLogic.isSameApplicationFamily(
                "com.google.Chrome.helper.renderer",
                "com.google.Chrome"
            )
        )
    }

    func testSamePIDTextInputIsNotFocusDrift() {
        XCTAssertFalse(
            InjectionSessionGuardLogic.isGenuineFocusDrift(
                pinnedPID: 100,
                currentPID: 100,
                pinnedBundleID: "com.example.app",
                currentBundleID: "com.example.app",
                handlesEqual: false,
                currentIsTextInput: true
            )
        )
    }

    func testDifferentPIDSameBundleIsNotFocusDrift() {
        XCTAssertFalse(
            InjectionSessionGuardLogic.isGenuineFocusDrift(
                pinnedPID: 100,
                currentPID: 200,
                pinnedBundleID: "com.google.Chrome",
                currentBundleID: "com.google.Chrome",
                handlesEqual: false,
                currentIsTextInput: true
            )
        )
    }

    func testChromeHelperProcessIsNotFocusDrift() {
        XCTAssertFalse(
            InjectionSessionGuardLogic.isGenuineFocusDrift(
                pinnedPID: 100,
                currentPID: 200,
                pinnedBundleID: "com.google.Chrome",
                currentBundleID: "com.google.Chrome.helper",
                handlesEqual: false,
                currentIsTextInput: true
            )
        )
    }

    func testDifferentBundleIsFocusDrift() {
        XCTAssertTrue(
            InjectionSessionGuardLogic.isGenuineFocusDrift(
                pinnedPID: 100,
                currentPID: 200,
                pinnedBundleID: "com.google.Chrome",
                currentBundleID: "com.apple.Notes",
                handlesEqual: false,
                currentIsTextInput: true
            )
        )
    }

    func testDifferentPIDWithoutBundleIsNotFocusDrift() {
        XCTAssertFalse(
            InjectionSessionGuardLogic.isGenuineFocusDrift(
                pinnedPID: 100,
                currentPID: 200,
                pinnedBundleID: nil,
                currentBundleID: nil,
                handlesEqual: false,
                currentIsTextInput: true
            )
        )
    }

    func testEqualHandlesIsNotFocusDrift() {
        XCTAssertFalse(
            InjectionSessionGuardLogic.isGenuineFocusDrift(
                pinnedPID: 100,
                currentPID: 100,
                pinnedBundleID: "com.example.app",
                currentBundleID: "com.example.app",
                handlesEqual: true,
                currentIsTextInput: false
            )
        )
    }
}
