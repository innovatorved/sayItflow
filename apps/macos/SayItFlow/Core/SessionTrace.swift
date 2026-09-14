import Foundation

/// Append-only session trace and engine logging for diagnosing dictation, injection, and polish behavior.
/// Written to ~/Library/Logs/SayItFlow/ (visible even when Unified Logging is silent).
enum SessionTrace {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var inMemoryRecent: [String] = []
    private static let maxInMemory = 300

    /// Pre-configured shared formatter (ISO8601DateFormatter is thread-safe after setup).
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Persistent file handles to avoid open/close churn on every log entry.
    nonisolated(unsafe) private static var traceHandle: FileHandle?
    nonisolated(unsafe) private static var engineHandle: FileHandle?

    /// Maximum log file size before rotation (~1 MB).
    private static let maxLogFileSize: UInt64 = 1_048_576

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

        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) [\(category)] \(message)\n"
        let entry = "\(timestamp) [\(category)] \(message)"

        inMemoryRecent.append(entry)
        if inMemoryRecent.count > maxInMemory {
            inMemoryRecent.removeFirst(inMemoryRecent.count - maxInMemory)
        }

        appendToFile(url: traceURL, line: line, handle: &traceHandle)
        AppLogger.dictation.notice("\(message, privacy: .public)")
    }

    static func logEngine(_ text: String) {
        guard !text.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let timestamp = formatter.string(from: Date())

        let trimmed = text.trimmingCharacters(in: .newlines)
        for subline in trimmed.components(separatedBy: .newlines) {
            let line = "\(timestamp) [engine] \(subline)\n"
            let entry = "\(timestamp) [engine] \(subline)"
            inMemoryRecent.append(entry)
            if inMemoryRecent.count > maxInMemory {
                inMemoryRecent.removeFirst(inMemoryRecent.count - maxInMemory)
            }
            appendToFile(url: engineLogURL, line: line, handle: &engineHandle)
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

    private static func appendToFile(url: URL, line: String, handle: inout FileHandle?) {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            // Rotate if file exceeds max size
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64, size > maxLogFileSize {
                handle?.closeFile()
                handle = nil
                let rotatedURL = url.deletingPathExtension()
                    .appendingPathExtension("prev.\(url.pathExtension)")
                try? FileManager.default.removeItem(at: rotatedURL)
                try? FileManager.default.moveItem(at: url, to: rotatedURL)
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            if handle == nil {
                handle = try FileHandle(forWritingTo: url)
            }
            guard let h = handle else { return }
            try h.seekToEnd()
            if let data = line.data(using: .utf8) {
                try h.write(contentsOf: data)
            }
        } catch {
            // Best-effort only — never crash for tracing.
            handle = nil
        }
    }
}
