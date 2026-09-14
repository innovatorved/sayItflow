import Foundation

/// Append-only session trace and engine logging for diagnosing dictation, injection, and polish behavior.
/// Written to ~/Library/Logs/SayItFlow/ (visible even when Unified Logging is silent).
enum SessionTrace {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var inMemoryRecent: [String] = []
    private static let maxInMemory = 300

    static var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SayItFlow", isDirectory: true)
    }

    static var traceURL: URL {
        logsDirectory.appendingPathComponent("session.trace")
    }

    static var engineLogURL: URL {
        logsDirectory.appendingPathComponent("engine.log")
    }

    static func log(_ message: String, category: String = "session") {
        lock.lock()
        defer { lock.unlock() }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) [\(category)] \(message)\n"
        let entry = "\(timestamp) [\(category)] \(message)"

        inMemoryRecent.append(entry)
        if inMemoryRecent.count > maxInMemory {
            inMemoryRecent.removeFirst(inMemoryRecent.count - maxInMemory)
        }

        appendToFile(url: traceURL, line: line)
        AppLogger.dictation.notice("\(message, privacy: .public)")
    }

    static func logEngine(_ text: String) {
        guard !text.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        let trimmed = text.trimmingCharacters(in: .newlines)
        for subline in trimmed.components(separatedBy: .newlines) {
            let line = "\(timestamp) [engine] \(subline)\n"
            let entry = "\(timestamp) [engine] \(subline)"
            inMemoryRecent.append(entry)
            if inMemoryRecent.count > maxInMemory {
                inMemoryRecent.removeFirst(inMemoryRecent.count - maxInMemory)
            }
            appendToFile(url: engineLogURL, line: line)
        }
    }

    static func recentLogs(limit: Int = 100) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let count = inMemoryRecent.count
        if count <= limit {
            return inMemoryRecent
        }
        return Array(inMemoryRecent.suffix(limit))
    }

    private static func appendToFile(url: URL, line: String) {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            // Best-effort only — never crash for tracing.
        }
    }
}
