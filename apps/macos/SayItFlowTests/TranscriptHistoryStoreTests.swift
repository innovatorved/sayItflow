import XCTest
@testable import SayItFlow

@MainActor
final class TranscriptHistoryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var storageURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        storageURL = tempDir.appendingPathComponent("history.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRecordPersistsWithTimestampAcrossReloads() {
        let store = TranscriptHistoryStore(storageURL: storageURL, maxEntries: 50)
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)

        store.record(
            text: "Hello world.",
            rawText: "um hello world",
            timestamp: timestamp,
            durationSeconds: 1.8,
            language: "en",
            engine: "voz+s1-mini",
            targetAppName: "Notes",
            targetBundleID: "com.apple.Notes",
            injectionSucceeded: true
        )
        store.flushSync()

        let reloaded = TranscriptHistoryStore(storageURL: storageURL, maxEntries: 50)
        XCTAssertEqual(reloaded.entries.count, 1)
        let entry = reloaded.entries[0]
        XCTAssertEqual(entry.text, "Hello world.")
        XCTAssertEqual(entry.rawText, "um hello world")
        XCTAssertEqual(entry.timestamp.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(entry.wordCount, 2)
        XCTAssertEqual(entry.targetAppName, "Notes")
        XCTAssertTrue(entry.injectionSucceeded)
    }

    func testIgnoresWhitespaceOnlyTranscripts() {
        let store = TranscriptHistoryStore(storageURL: storageURL)
        store.record(text: "   \n\t  ")
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testEnforcesMaxEntriesAndNewestFirstOrder() {
        let store = TranscriptHistoryStore(storageURL: storageURL, maxEntries: 3)
        store.record(text: "First")
        store.record(text: "Second")
        store.record(text: "Third")
        store.record(text: "Fourth")

        XCTAssertEqual(store.entries.map(\.text), ["Fourth", "Third", "Second"])
    }

    func testSearchMatchesTextRawTextAndAppName() {
        let store = TranscriptHistoryStore(storageURL: storageURL)
        store.record(text: "Ship release v2", rawText: "uh ship release v2", targetAppName: "Slack")
        store.record(text: "Fix compiler error", targetAppName: "Xcode")

        XCTAssertEqual(store.filtered(query: "slack").count, 1)
        XCTAssertEqual(store.filtered(query: "compiler").first?.targetAppName, "Xcode")
        XCTAssertEqual(store.filtered(query: "uh ship").count, 1)
        XCTAssertEqual(store.filtered(query: "   ").count, 2)
    }

    func testDeleteSingleAndDeleteAll() {
        let store = TranscriptHistoryStore(storageURL: storageURL)
        store.record(text: "One")
        store.record(text: "Two")
        let idToDelete = store.entries[0].id

        store.delete(id: idToDelete)
        XCTAssertEqual(store.entries.map(\.text), ["One"])

        store.deleteAll()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testExportMarkdownIncludesTextAndAppName() {
        let store = TranscriptHistoryStore(storageURL: storageURL)
        store.record(text: "Deploy to production.", targetAppName: "Terminal")

        let md = store.exportMarkdown()
        XCTAssertTrue(md.contains("# SayItFlow Transcript History"))
        XCTAssertTrue(md.contains("Terminal"))
        XCTAssertTrue(md.contains("Deploy to production."))
    }
}
