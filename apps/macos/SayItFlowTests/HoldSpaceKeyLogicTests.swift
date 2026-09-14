import XCTest
@testable import SayItFlow

final class HoldSpaceKeyLogicTests: XCTestCase {
    func testQuickTapPassesThrough() {
        var logic = HoldSpaceKeyLogic()
        XCTAssertFalse(logic.keyDown(isRepeat: false, isDictating: false))
        let result = logic.keyUp(now: logic.spaceDownAt! + 0.1, isDictating: false)
        XCTAssertEqual(result, HoldSpaceKeyLogic.KeyUpResult(consume: false, endDictation: false))
    }

    func testHoldThresholdStartsDictation() {
        var logic = HoldSpaceKeyLogic()
        XCTAssertFalse(logic.keyDown(isRepeat: false, isDictating: false))
        XCTAssertTrue(logic.thresholdElapsed(isDictating: false))
        XCTAssertTrue(logic.keyDown(isRepeat: true, isDictating: true))
        let result = logic.keyUp(isDictating: true)
        XCTAssertEqual(result, HoldSpaceKeyLogic.KeyUpResult(consume: true, endDictation: true))
    }

    func testAutorepeatPassesThroughWhilePending() {
        var logic = HoldSpaceKeyLogic()
        _ = logic.keyDown(isRepeat: false, isDictating: false)
        XCTAssertFalse(logic.keyDown(isRepeat: true, isDictating: false))
    }

    func testAutorepeatPassesThroughWhenIdle() {
        var logic = HoldSpaceKeyLogic()
        XCTAssertFalse(logic.keyDown(isRepeat: true, isDictating: false))
    }

    func testLongHoldWithoutTimerStillEndsDictation() {
        var logic = HoldSpaceKeyLogic()
        let down = CFAbsoluteTimeGetCurrent()
        _ = logic.keyDown(isRepeat: false, isDictating: false)
        let result = logic.keyUp(now: down + 0.6, isDictating: true)
        XCTAssertTrue(result.consume)
        XCTAssertTrue(result.endDictation)
    }

    /// Regression: the hold timer (main queue) and key-up (event-tap thread) race. If
    /// key-up lands after `thresholdElapsed` but before the engine marks itself
    /// dictating, the release must still end dictation — otherwise it gets swallowed
    /// and the session that is about to start has nothing to close it.
    func testReleaseRacingActivationStillEndsDictation() {
        var logic = HoldSpaceKeyLogic()
        _ = logic.keyDown(isRepeat: false, isDictating: false)
        XCTAssertTrue(logic.thresholdElapsed(isDictating: false))

        let result = logic.keyUp(isDictating: false)
        XCTAssertTrue(result.consume)
        XCTAssertTrue(result.endDictation)
    }

    func testFirstKeyDownNeverConsumes() {
        var logic = HoldSpaceKeyLogic()
        XCTAssertFalse(logic.keyDown(isRepeat: false, isDictating: false))
    }
}
