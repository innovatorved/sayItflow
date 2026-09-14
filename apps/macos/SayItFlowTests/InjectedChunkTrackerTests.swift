import XCTest
@testable import SayItFlow

final class InjectedChunkTrackerTests: XCTestCase {
    func testReplaceChunkWithDuplicateSubstringsTargetsCorrectIndex() {
        var tracker = InjectedChunkTracker()
        _ = tracker.appendChunk("test", injectedLength: 4)
        _ = tracker.appendChunk("test", injectedLength: 4)
        _ = tracker.appendChunk("test", injectedLength: 4)

        XCTAssertTrue(tracker.replaceChunk(at: 1, with: "exam"))
        XCTAssertEqual(tracker.trimmedCommitted(), "test exam test")
    }

    func testReplaceChunkUpdatesLaterOffsets() {
        var tracker = InjectedChunkTracker()
        _ = tracker.appendChunk("hello world", injectedLength: 11)
        _ = tracker.appendChunk("goodbye moon", injectedLength: 12)

        XCTAssertTrue(tracker.replaceChunk(at: 0, with: "hi earth"))
        XCTAssertEqual(tracker.chunks[1].committedStart, "hi earth ".count)
    }

    func testReplaceAllCommittedResetsChunks() {
        var tracker = InjectedChunkTracker()
        _ = tracker.appendChunk("raw phrase here", injectedLength: 15)
        tracker.replaceAllCommitted(with: "polished phrase")
        XCTAssertEqual(tracker.trimmedCommitted(), "polished phrase")
        XCTAssertTrue(tracker.chunks.isEmpty)
    }
}
