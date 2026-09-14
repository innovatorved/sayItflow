import XCTest
@testable import SayItFlow

final class ChunkBoundaryDetectorTests: XCTestCase {
    func testExtractsSentenceChunk() {
        var detector = ChunkBoundaryDetector(intensity: .standard)
        XCTAssertNil(detector.extractChunk(from: "one two three"))
        let chunk = detector.extractChunk(from: "one two three four. More words here")
        XCTAssertEqual(chunk, "one two three four.")
    }

    func testRemainderAfterCommit() {
        var detector = ChunkBoundaryDetector(intensity: .standard)
        _ = detector.extractChunk(from: "one two three four. Second phrase here")
        XCTAssertEqual(detector.remainder(in: "one two three four. Second phrase here"), "Second phrase here")
    }

    func testPauseDebounceExtractsStableTail() {
        var detector = ChunkBoundaryDetector(intensity: .standard)
        let t0: CFAbsoluteTime = 1000
        XCTAssertNil(detector.extractChunk(from: "one two three four", now: t0))
        let chunk = detector.extractChunk(
            from: "one two three four",
            now: t0 + ChunkBoundaryDetector.pauseDebounceSeconds + 0.1
        )
        XCTAssertEqual(chunk, "one two three four")
    }

    func testWordBudgetExtractsChunk() {
        var detector = ChunkBoundaryDetector(intensity: .standard)
        let words = (1...10).map { "word\($0)" }.joined(separator: " ")
        let chunk = detector.extractChunk(from: words)
        XCTAssertEqual(chunk, words)
    }

    func testShouldPolishRequiresMinimumWords() {
        XCTAssertFalse(ChunkBoundaryDetector.shouldPolish("one two three", intensity: .standard))
        XCTAssertTrue(ChunkBoundaryDetector.shouldPolish("one two three four", intensity: .standard))
    }

    func testLightModeAllowsFourWordPauseChunk() {
        XCTAssertFalse(ChunkBoundaryDetector.shouldPolish("one two three", intensity: .light))
        XCTAssertTrue(ChunkBoundaryDetector.shouldPolish("one two three four", intensity: .light))
    }

    func testLightModeUsesPauseBoundaries() {
        var detector = ChunkBoundaryDetector(intensity: .light)
        let t0: CFAbsoluteTime = 1000
        XCTAssertNil(detector.extractChunk(from: "one two three four", now: t0))
        let chunk = detector.extractChunk(
            from: "one two three four",
            now: t0 + ChunkBoundaryDetector.lightPauseDebounceSeconds + 0.1
        )
        XCTAssertEqual(chunk, "one two three four")
    }

    func testSentenceWithThreeWordsPolishes() {
        XCTAssertTrue(ChunkBoundaryDetector.shouldPolish("hello there friend.", intensity: .light))
    }

    func testNoteExternalCommitAdvancesRemainder() {
        var detector = ChunkBoundaryDetector(intensity: .light)
        let full = "First phrase here. Second phrase"
        detector.noteExternalCommit(chunk: "First phrase here.", in: full)
        XCTAssertEqual(detector.remainder(in: full), "Second phrase")
    }
}
