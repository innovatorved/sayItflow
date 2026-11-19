import Foundation
import Combine

/// A single saved voice transcription with full metadata and wall-clock timestamp.
struct TranscriptEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var timestamp: Date
    var text: String
    /// Original raw ASR output when post-processing modified the text; nil when unchanged.
    var rawText: String?
    var wordCount: Int
    var durationSeconds: Double
    var language: String
    var engine: String
    var targetAppName: String?
    var targetBundleID: String?
    var injectionSucceeded: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        rawText: String? = nil,
        wordCount: Int? = nil,
        durationSeconds: Double = 0,
        language: String = "en",
        engine: String = "voz",
        targetAppName: String? = nil,
        targetBundleID: String? = nil,
        injectionSucceeded: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.rawText = (rawText != nil && rawText != text) ? rawText : nil
        self.wordCount = wordCount ?? text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        self.durationSeconds = max(0, durationSeconds)
        self.language = language
        self.engine = engine
        self.targetAppName = targetAppName
        self.targetBundleID = targetBundleID
        self.injectionSucceeded = injectionSucceeded
    }
}

/// Local-only, persistent store for timestamped dictation transcripts.
///
/// Saves atomically to `~/Library/Application Support/SayItFlow/history.json` on a
/// background serial queue so disk I/O never stalls dictation or UI rendering.
@MainActor
final class TranscriptHistoryStore: ObservableObject {
    static let shared = TranscriptHistoryStore()

    @Published private(set) var entries: [TranscriptEntry] = []

    let maxEntries: Int
    private let storageURL: URL
    private let ioQueue = DispatchQueue(label: "com.innovatorved.sayitflow.history.io", qos: .utility)

    static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("SayItFlow", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    init(storageURL: URL = TranscriptHistoryStore.defaultStorageURL, maxEntries: Int = 500) {
        self.storageURL = storageURL
        self.maxEntries = max(1, maxEntries)
        loadFromDisk()
    }

    // MARK: - Mutations

    func record(
        text: String,
        rawText: String? = nil,
        timestamp: Date = Date(),
        durationSeconds: Double = 0,
        language: String = "en",
        engine: String = "voz",
        targetAppName: String? = nil,
        targetBundleID: String? = nil,
        injectionSucceeded: Bool = true
    ) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let entry = TranscriptEntry(
            timestamp: timestamp,
            text: cleaned,
            rawText: rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
            durationSeconds: durationSeconds,
            language: language,
            engine: engine,
            targetAppName: targetAppName,
            targetBundleID: targetBundleID,
            injectionSucceeded: injectionSucceeded
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        persistAsync()
    }

    func delete(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: idx)
        persistAsync()
    }

    func deleteAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        persistAsync()
    }

    // MARK: - Queries

    func filtered(query: String) -> [TranscriptEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter { entry in
            entry.text.localizedCaseInsensitiveContains(q)
                || (entry.rawText?.localizedCaseInsensitiveContains(q) ?? false)
                || (entry.targetAppName?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var totalWords: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    /// Exports all stored transcripts as a readable timestamped Markdown document.
    func exportMarkdown() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        var lines: [String] = ["# SayItFlow Transcript History", ""]
        for entry in entries {
            let ts = formatter.string(from: entry.timestamp)
            let appSuffix = entry.targetAppName.map { " · \($0)" } ?? ""
            lines.append("### \(ts)\(appSuffix)")
            lines.append(entry.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Blocks until all pending disk writes finish. Useful for tests and graceful shutdown.
    func flushSync() {
        ioQueue.sync {}
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([TranscriptEntry].self, from: data)
            entries = Array(decoded.prefix(maxEntries))
        } catch {
            AppLogger.dictation.error("Failed to load transcript history: \(error.localizedDescription)")
        }
    }

    private func persistAsync() {
        let snapshot = entries
        let url = storageURL
        ioQueue.async {
            do {
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                AppLogger.dictation.error("Failed to save transcript history: \(error.localizedDescription)")
            }
        }
    }
}
