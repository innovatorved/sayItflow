import XCTest
@testable import SayItFlow

final class LivePartialMergeLogicTests: XCTestCase {
    func testExtendWhenPartialGrows() {
        XCTAssertEqual(
            LivePartialMergeLogic.merge(existing: "hello", incoming: "hello world"),
            .extend(delta: " world")
        )
    }

    func testReviseWhenPartialShrinks() {
        XCTAssertEqual(
            LivePartialMergeLogic.merge(existing: "hello world", incoming: "hello"),
            .revise(to: "hello")
        )
    }

    func testReviseWhenOnlyWhitespaceOrNewlinesChange() {
        XCTAssertEqual(
            LivePartialMergeLogic.merge(existing: "hello world", incoming: "hello\nworld"),
            .revise(to: "hello\nworld")
        )
    }

    func testAppendWhenPartialIsNewLineAfterReset() {
        XCTAssertEqual(
            LivePartialMergeLogic.merge(existing: "first line", incoming: "second line"),
            .appendNewSegment(separator: " ", segment: "second line")
        )
        XCTAssertEqual(
            LivePartialMergeLogic.mergedText(existing: "first line", incoming: "second line"),
            "first line second line"
        )
    }

    func testAppendUsesEmptySeparatorWhenExistingEndsWithSpace() {
        XCTAssertEqual(
            LivePartialMergeLogic.merge(existing: "first line ", incoming: "second line"),
            .appendNewSegment(separator: "", segment: "second line")
        )
    }

    func testReviseOnMidStringSTTCorrection() {
        XCTAssertEqual(
            LivePartialMergeLogic.merge(existing: "Hello my name is V", incoming: "Hello my name is Reed"),
            .revise(to: "Hello my name is Reed")
        )
    }

    func testExtendWithCaseChangeOnPrefix() {
        XCTAssertEqual(
            LivePartialMergeLogic.merge(existing: "hello world", incoming: "Hello world foo"),
            .extend(delta: " foo")
        )
    }

    func testReviseOnCompanyNameCorrection() {
        XCTAssertEqual(
            LivePartialMergeLogic.merge(existing: "I am working in LTM", incoming: "I am working in LTi Mindtree"),
            .revise(to: "I am working in LTi Mindtree")
        )
    }
}
