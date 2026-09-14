import XCTest
@testable import SayItFlow

final class SetupStepLogicTests: XCTestCase {
    func testCanAdvanceWelcomeWithoutPermissions() {
        let permissions = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, PermissionStatus.notDetermined) })
        XCTAssertTrue(SetupStepLogic.canAdvance(from: .welcome, permissions: permissions, hotkeyReady: false, demoCompleted: false))
    }

    func testCannotAdvanceMicrophoneUntilGranted() {
        var permissions = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, PermissionStatus.granted) })
        permissions[.microphone] = .notDetermined
        XCTAssertFalse(SetupStepLogic.canAdvance(from: .microphone, permissions: permissions, hotkeyReady: true, demoCompleted: false))
        permissions[.microphone] = .granted
        XCTAssertTrue(SetupStepLogic.canAdvance(from: .microphone, permissions: permissions, hotkeyReady: true, demoCompleted: false))
    }

    func testFirstIncompleteStepStartsAtMicrophoneWhenNoneGranted() {
        let permissions = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, PermissionStatus.notDetermined) })
        XCTAssertEqual(SetupStepLogic.firstIncompleteStep(permissions: permissions, hotkeyReady: false), .microphone)
    }

    func testFirstIncompleteStepJumpsToVerifyWhenPermissionsGrantedButHotkeyFails() {
        let permissions = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, PermissionStatus.granted) })
        XCTAssertEqual(SetupStepLogic.firstIncompleteStep(permissions: permissions, hotkeyReady: false), .verifyHotkey)
    }

    func testTryDictationRequiresDemoCompletion() {
        let permissions = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, PermissionStatus.granted) })
        XCTAssertFalse(SetupStepLogic.canAdvance(from: .tryDictation, permissions: permissions, hotkeyReady: true, demoCompleted: false))
        XCTAssertTrue(SetupStepLogic.canAdvance(from: .tryDictation, permissions: permissions, hotkeyReady: true, demoCompleted: true))
    }
}
