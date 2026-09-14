import Foundation
import Combine

/// One recorded dictation session.
struct AnalyticsSession: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var startedAt: Date
    var durationMs: Int
    var words: Int
    var chars: Int
    var chunksCommitted: Int
    /// "live" (typed while speaking) or "batch" (inserted on release)
    var mode: String
    var engine: String
    /// "done" | "cancelled" | "stalled" | "error"
    var outcome: String

    var durationSeconds: Double { Double(durationMs) / 1000 }

    static let outcomes = ["done", "cancelled", "stalled", "error"]
}

/// Local-only dictation analytics. Nothing leaves the device.
@MainActor
final class DictationAnalytics: ObservableObject {
    static let shared = DictationAnalytics()

    static let storageKey = "dictationAnalytics.v1"

    @Published private(set) var sessions: [AnalyticsSession] = []

    private let defaults: UserDefaults
    private let maxSessions = 200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func record(
        startedAt: Date,
        words: Int,
        chars: Int,
        chunksCommitted: Int,
        mode: String,
        engine: String,
        outcome: String
    ) {
        let session = AnalyticsSession(
            startedAt: startedAt,
            durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            words: words,
            chars: chars,
            chunksCommitted: chunksCommitted,
            mode: mode,
            engine: engine,
            outcome: outcome
        )
        sessions.insert(session, at: 0)
        if sessions.count > maxSessions {
            sessions.removeLast(sessions.count - maxSessions)
        }
        save()
    }

    // MARK: - Aggregates

    var totalSessions: Int { sessions.count }

    var totalWords: Int { sessions.reduce(0) { $0 + $1.words } }

    var totalDurationSeconds: Double {
        sessions.reduce(0.0) { $0 + Double($1.durationMs) / 1000 }
    }

    var averageWordsPerSession: Int {
        guard !sessions.isEmpty else { return 0 }
        return Int((Double(totalWords) / Double(sessions.count)).rounded())
    }

    var longestSessionSeconds: Double {
        sessions.map(\.durationSeconds).max() ?? 0
    }

    func outcomeCount(_ outcome: String) -> Int {
        sessions.filter { $0.outcome == outcome }.count
    }

    /// Sessions that used incremental (chunked) polish, as a fraction of live sessions.
    var incrementalPolishRate: Double {
        let live = sessions.filter { $0.mode == "live" }
        guard !live.isEmpty else { return 0 }
        let polished = live.filter { $0.chunksCommitted > 0 }
        return Double(polished.count) / Double(live.count)
    }

    var recentSessions: [AnalyticsSession] {
        Array(sessions.prefix(20))
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        sessions = (try? JSONDecoder().decode([AnalyticsSession].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func reset() {
        sessions.removeAll()
        save()
    }
}
