import XCTest
@testable import SayItFlow

@MainActor
final class ClosureLiveTextSinkFinalizeTests: XCTestCase {
    func testFinalizeAfterCommitAppendsOnlyRemainder() {
        let sink = ClosureLiveTextSink { _ in }
        _ = sink.beginSession(prefix: "")
        sink.commitChunk("first chunk")
        let result = sink.finalize(partial: "first chunk second part")
        XCTAssertEqual(result, "first chunk second part")
    }

    func testFinalizeWithoutCommitsAppendsWholePartial() {
        let sink = ClosureLiveTextSink { _ in }
        _ = sink.beginSession(prefix: "")
        let result = sink.finalize(partial: "all of it")
        XCTAssertEqual(result, "all of it")
    }

    func testDivergentFinalKeepsCommittedChunks() {
        let sink = ClosureLiveTextSink { _ in }
        _ = sink.beginSession(prefix: "")
        sink.commitChunk("committed words")
        let result = sink.finalize(partial: "divergent stt text")
        XCTAssertEqual(result, "committed words")
    }
}
