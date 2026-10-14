import Foundation
import Combine

/// Represents an individual voice dictation event stored in history.
public struct DictationRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let wordCount: Int
    public let charCount: Int
    public let appName: String
    public let durationSeconds: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        wordCount: Int? = nil,
        charCount: Int? = nil,
        appName: String = "",
        durationSeconds: Double = 0.0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.wordCount = wordCount ?? text.split { $0.isWhitespace || $0.isNewline }.count
        self.charCount = charCount ?? text.count
        self.appName = appName
        self.durationSeconds = durationSeconds
    }
}

/// On-device storage for past voice dictation sessions.
/// Persists records locally to UserDefaults with JSON encoding.
@MainActor
public final class DictationHistoryStore: ObservableObject {
    public static let shared = DictationHistoryStore()

    private static let storageKey = "SayItFlow.DictationHistory"
    private static let maxRecords = 500

    @Published public private(set) var records: [DictationRecord] = []

    public init() {
        load()
    }

    /// Records a new dictation transcript and saves to persistent storage.
    @discardableResult
    public func record(text: String, appName: String = "", durationSeconds: Double = 0.0) -> DictationRecord? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let item = DictationRecord(
            text: trimmed,
            appName: appName,
            durationSeconds: durationSeconds
        )

        records.insert(item, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }

        save()
        return item
    }

    /// Deletes a specific record by its unique ID.
    public func delete(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    /// Deletes records at specified index offsets.
    public func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    /// Clears all recorded dictations.
    public func clearAll() {
        records.removeAll()
        save()
    }

    /// Searches records matching query in transcript or app name.
    public func search(query: String) -> [DictationRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return records }

        return records.filter { record in
            record.text.localizedCaseInsensitiveContains(trimmed) ||
            record.appName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - Private Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([DictationRecord].self, from: data)
        } catch {
            records = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            // Ignore persistence write failure
        }
    }
}
