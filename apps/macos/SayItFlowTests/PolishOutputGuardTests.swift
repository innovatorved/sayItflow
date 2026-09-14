import XCTest
@testable import SayItFlow

final class PolishOutputGuardTests: XCTestCase {
    func testAcceptsReasonablePolish() {
        XCTAssertTrue(PolishOutputGuard.shouldApplyPolishResult(raw: "hello world", polished: "Hello world."))
    }

    func testRejectsEmptyPolish() {
        XCTAssertFalse(PolishOutputGuard.shouldApplyPolishResult(raw: "hello world", polished: "   "))
    }

    func testRejectsTooShortRatio() {
        XCTAssertFalse(PolishOutputGuard.shouldApplyPolishResult(raw: "this is a longer dictated sentence for testing", polished: "ok"))
    }

    func testRejectsTooLongRatio() {
        let bloated = String(repeating: "word ", count: 20)
        XCTAssertFalse(PolishOutputGuard.shouldApplyPolishResult(raw: "hi", polished: bloated))
    }

    func testRejectsHeavyRewrite() {
        let raw = "um hello world this is a test sentence"
        let rewritten = "Greetings. This constitutes an evaluation statement."
        XCTAssertFalse(PolishOutputGuard.shouldApplyPolishResult(raw: raw, polished: rewritten))
    }

    func testListsStructureAllowsMoreRewrite() {
        let raw = "one two three four five six seven eight nine"
        let polished = "one two three reformatted"
        XCTAssertTrue(
            PolishOutputGuard.shouldApplyPolishResult(
                raw: raw,
                polished: polished,
                structure: .lists
            )
        )
        XCTAssertFalse(
            PolishOutputGuard.shouldApplyPolishResult(
                raw: raw,
                polished: polished,
                structure: .prose
            )
        )
    }
}
