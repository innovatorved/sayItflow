import XCTest
@testable import SayItFlow

final class ReconcileFinalTranscriptTests: XCTestCase {
    func testFieldExtensionOfSttWins() {
        let stt = "hello world"
        let field = "hello world today"
        XCTAssertEqual(LivePartialMergeLogic.reconciledFinal(stt: stt, field: field), field)
    }

    func testDivergentDuplicateFieldLoses() {
        // Field holds the transcript duplicated — STT text must win.
        let stt = "please send the report"
        let field = "please send the report please send the report"
        XCTAssertEqual(LivePartialMergeLogic.reconciledFinal(stt: stt, field: field), stt)
    }

    func testEmptyFieldReturnsStt() {
        XCTAssertEqual(
            LivePartialMergeLogic.reconciledFinal(stt: "final text", field: ""),
            "final text"
        )
    }

    func testEmptySttReturnsField() {
        XCTAssertEqual(
            LivePartialMergeLogic.reconciledFinal(stt: "", field: "typed live"),
            "typed live"
        )
    }

    func testIdenticalTextsReturnSame() {
        XCTAssertEqual(
            LivePartialMergeLogic.reconciledFinal(stt: "same", field: "same"),
            "same"
        )
    }

    func testInjectionFinalPrefersPolishedOverLongerLivePartial() {
        let polished = "Hello world, this is a test."
        let live = "um hello world this is a test uh and some extra hallucinated words"
        XCTAssertEqual(
            LivePartialMergeLogic.injectionFinal(
                engineText: polished,
                livePartial: live,
                fieldText: live,
                polishApplied: true
            ),
            polished
        )
    }

    func testInjectionFinalUsesReconcileWhenPolishOff() {
        XCTAssertEqual(
            LivePartialMergeLogic.injectionFinal(
                engineText: "hello world",
                livePartial: "hello world today",
                fieldText: "hello world today",
                polishApplied: false
            ),
            "hello world today"
        )
    }
}
