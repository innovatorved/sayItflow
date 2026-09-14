import XCTest
@testable import SayItFlow

@MainActor
final class DictationAnalyticsTests: XCTestCase {
    private func makeStore() -> (DictationAnalytics, UserDefaults) {
        let suite = "analytics-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (DictationAnalytics(defaults: defaults), defaults)
    }

    func testRecordAndAggregate() {
        let (store, _) = makeStore()
        let start = Date()
        store.record(
            startedAt: start,
            words: 42,
            chars: 210,
            chunksCommitted: 3,
            mode: "live",
            engine: "sfSpeech",
            outcome: "done"
        )
        store.record(
            startedAt: start,
            words: 10,
            chars: 55,
            chunksCommitted: 0,
            mode: "batch",
            engine: "sfSpeech",
            outcome: "stalled"
        )

        XCTAssertEqual(store.totalSessions, 2)
        XCTAssertEqual(store.totalWords, 52)
        XCTAssertEqual(store.outcomeCount("done"), 1)
        XCTAssertEqual(store.outcomeCount("stalled"), 1)
        // One of one live sessions used incremental polish.
        XCTAssertEqual(store.incrementalPolishRate, 1.0, accuracy: 0.001)
        XCTAssertEqual(store.recentSessions.first?.outcome, "stalled")
    }

    func testPersistsAcrossInstances() {
        let (store, defaults) = makeStore()
        store.record(
            startedAt: Date(),
            words: 7,
            chars: 30,
            chunksCommitted: 1,
            mode: "live",
            engine: "sfSpeech",
            outcome: "done"
        )

        let reloaded = DictationAnalytics(defaults: defaults)
        XCTAssertEqual(reloaded.totalSessions, 1)
        XCTAssertEqual(reloaded.totalWords, 7)
    }

    func testResetClearsEverything() {
        let (store, defaults) = makeStore()
        store.record(
            startedAt: Date(),
            words: 5,
            chars: 20,
            chunksCommitted: 0,
            mode: "batch",
            engine: "speechAnalyzer",
            outcome: "cancelled"
        )
        store.reset()
        XCTAssertTrue(store.sessions.isEmpty)
        // Persisted state must be empty too (nil or an empty session list).
        let reloaded = DictationAnalytics(defaults: defaults)
        XCTAssertEqual(reloaded.totalSessions, 0)
    }
}
