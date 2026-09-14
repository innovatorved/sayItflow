import Foundation
import SwiftUI

// MARK: - Control Enums

/// Output style for S1-mini text normalization.
public enum S1Styling: String, CaseIterable, Identifiable, Sendable {
    case casual = "casual"
    case semiCasual = "semi-casual"
    case semiFormal = "semi-formal"
    case formal = "formal"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .casual: "Casual"
        case .semiCasual: "Semi-Casual"
        case .semiFormal: "Semi-Formal"
        case .formal: "Formal"
        }
    }
}

/// Output structure for S1-mini text normalization.
public enum S1Structure: String, CaseIterable, Identifiable, Sendable {
    case prose = "prose"
    case lists = "lists"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .prose: "Prose"
        case .lists: "Bullet Lists"
        }
    }
}

/// Context setting for S1-mini text normalization.
public enum S1Context: String, CaseIterable, Identifiable, Sendable {
    case general = "general"
    case email = "email"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .general: "General"
        case .email: "Email"
        }
    }
}

// MARK: - S1MiniEngine

/// Coordinates on-device speech-to-text transcript normalization using
/// "S1-mini" by "Superwhisper" (596M parameter causal LM based on Qwen3-0.6B).
///
/// Pipeline:
/// Audio ──▶ Desert Ant Voz (Apple Neural Engine Core ML) ──▶ S1-mini (Text Normalizer) ──▶ Injected Text
///
/// Attribution notice (required by Apache 2.0 with Additional Term):
/// Must continue to identify it by its original name, "S1-mini" by "Superwhisper".
@MainActor
public final class S1MiniEngine: ObservableObject {
    public static let shared = S1MiniEngine()

    // MARK: - Configuration Constants

    public static let modelName = "S1-mini"
    public static let modelAuthor = "Superwhisper"
    public static let licenseType = "Apache 2.0 (with name retention)"
    public static let modelSizeMB = 462

    private static let downloadURLString = "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/main/s1-mini-q4_k_m.gguf"
    private static let modelFileName = "s1-mini-q4_k_m.gguf"

    // MARK: - Published State

    @Published public private(set) var isDownloaded: Bool = false
    @Published public private(set) var isDownloading: Bool = false
    @Published public private(set) var downloadProgress: Double = 0.0
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastLatencyMs: Double = 0.0

    @Published public var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published public var styling: S1Styling {
        didSet { UserDefaults.standard.set(styling.rawValue, forKey: Keys.styling) }
    }

    @Published public var structure: S1Structure {
        didSet { UserDefaults.standard.set(structure.rawValue, forKey: Keys.structure) }
    }

    @Published public var context: S1Context {
        didSet { UserDefaults.standard.set(context.rawValue, forKey: Keys.context) }
    }

    // MARK: - Storage Keys

    private enum Keys {
        static let isEnabled = "sayitflow.s1mini.enabled"
        static let styling = "sayitflow.s1mini.styling"
        static let structure = "sayitflow.s1mini.structure"
        static let context = "sayitflow.s1mini.context"
    }

    // MARK: - Model Directory

    public var modelFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("SayItFlow/models/s1-mini", isDirectory: true)
        return dir.appendingPathComponent(Self.modelFileName)
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.isEnabled) != nil {
            self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        } else {
            self.isEnabled = true
        }

        if let rawStyle = defaults.string(forKey: Keys.styling),
           let style = S1Styling(rawValue: rawStyle) {
            self.styling = style
        } else {
            self.styling = .semiFormal
        }

        if let rawStruct = defaults.string(forKey: Keys.structure),
           let structVal = S1Structure(rawValue: rawStruct) {
            self.structure = structVal
        } else {
            self.structure = .prose
        }

        if let rawContext = defaults.string(forKey: Keys.context),
           let ctx = S1Context(rawValue: rawContext) {
            self.context = ctx
        } else {
            self.context = .general
        }

        refreshStatus()
    }

    // MARK: - Status & Model Management

    public func refreshStatus() {
        let url = modelFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs[.size] as? Int64) ?? 0
                // Valid if file is > 400 MB
                isDownloaded = size > 400 * 1024 * 1024
            } catch {
                isDownloaded = false
            }
        } else {
            isDownloaded = false
        }
    }

    /// Downloads the official S1-mini GGUF model into the local cache.
    public func downloadModel() async throws {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0.01
        lastError = nil

        let targetURL = modelFileURL
        let dir = targetURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            guard let remoteURL = URL(string: Self.downloadURLString) else {
                throw NSError(domain: "S1MiniEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL"])
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let delegate = S1DownloadSession(
                    targetURL: targetURL,
                    continuation: continuation,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            self?.downloadProgress = min(max(progress, 0.01), 0.99)
                        }
                    }
                )

                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                let task = session.downloadTask(with: remoteURL)
                task.resume()
            }

            isDownloaded = true
            isDownloading = false
            downloadProgress = 1.0
        } catch {
            isDownloading = false
            downloadProgress = 0.0
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Deletes the downloaded model file.
    public func deleteModel() throws {
        let url = modelFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        refreshStatus()
    }

    // MARK: - Normalization Pipeline

    /// Normalizes a speech-to-text transcript.
    ///
    /// - Parameters:
    ///   - rawTranscript: Raw transcript output from Desert Ant Voz.
    ///   - language: ISO language code (e.g. "en").
    /// - Returns: Cleaned, punctuated, normalized text ready for injection.
    public func normalize(_ rawTranscript: String, language: String = "en") async -> String {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Gate 1: S1-mini is English-only. If non-English, preserve Voz raw transcript directly.
        guard language == "en" else {
            return trimmed
        }

        // Gate 2: If S1-mini post-processing is disabled, return raw transcript.
        guard isEnabled else {
            return trimmed
        }

        // Gate 3: Filler-only check.
        if isFillerOnly(trimmed) {
            return ""
        }

        let start = CFAbsoluteTimeGetCurrent()

        // Inference Attempt: If model is downloaded and inference runner is available
        if isDownloaded {
            if let output = await runInference(rawText: trimmed) {
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                lastLatencyMs = elapsed
                return output
            }
        }

        // Fallback: Swift speech normalizer (removes disfluencies, fixes casing/punctuation)
        let fallbackPolished = ruleBasedNormalize(trimmed)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        lastLatencyMs = elapsed
        return fallbackPolished
    }

    // MARK: - Prompt Formatting

    /// Formats the prompt according to S1-mini specifications.
    ///
    /// System prompt specifies text normalizer role.
    /// User message starts with control line: `[Styling: ...] [Structure: ...] [Context: ...]`.
    /// Assistant turn is pre-seeded with `<think>\n\n</think>\n\n` to enforce `enable_thinking=false`.
    public func buildPrompt(for rawTranscript: String) -> String {
        """
        <|im_start|>system
        You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text.<|im_end|>
        <|im_start|>user
        [Styling: \(styling.rawValue)] [Structure: \(structure.rawValue)] [Context: \(context.rawValue)]
        \(rawTranscript)<|im_end|>
        <|im_start|>assistant
        <think>

        </think>

        """
    }

    // MARK: - Inference Execution

    private func queryLocalServer(prompt: String) async -> String? {
        guard let url = URL(string: "http://127.0.0.1:8080/completion") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 0.35
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "prompt": prompt,
            "n_predict": 256,
            "temperature": 0.0,
            "stop": ["<|im_end|>", "<|endoftext|>"]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? String {
                return content
            }
        } catch {
            return nil
        }
        return nil
    }

    private func runInference(rawText: String) async -> String? {
        let prompt = buildPrompt(for: rawText)

        // 1. Try warm local server (sub-50ms)
        if let output = await queryLocalServer(prompt: prompt) {
            let cleaned = cleanModelOutput(output, input: rawText)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        // 2. Cold process spawn is bypassed on the user-facing release path to prevent 3.5s lag.
        // Rule-based speech normalizer executes instantly (<1ms).
        return nil
    }

    nonisolated private func cleanModelOutput(_ raw: String, input: String) -> String {
        var output = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop any residual think tags
        if let thinkEnd = output.range(of: "</think>") {
            output = String(output[thinkEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Drop any accidental control line echo
        if output.starts(with: "[Styling:") {
            if let firstNewline = output.firstIndex(of: "\n") {
                output = String(output[output.index(after: firstNewline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Strip endoftext token if echoed
        output = output.replacingOccurrences(of: "<|im_end|>", with: "")
        output = output.replacingOccurrences(of: "<|endoftext|>", with: "")
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the model produced empty text and input was not filler-only, return fallback
        if output.isEmpty && !isFillerOnly(input) {
            return ruleBasedNormalize(input)
        }

        return output
    }

    // MARK: - Rule-Based Speech Normalizer

    /// Instant, high-speed fallback speech normalizer.
    /// Collapses filler words, stutters, and normalizes capitalization.
    nonisolated public func ruleBasedNormalize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        var result = text

        // 1. Remove standalone speech disfluencies (case-insensitive)
        let fillers = [
            "\\b(um|uh|erm|ah)\\b,?\\s*",
            "\\b(like)\\b(?=\\s+like\\b)",
            "\\b(you know)\\b,?\\s*(?=\\b(um|uh|like)\\b)"
        ]

        for pattern in fillers {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: ""
                )
            }
        }

        // 2. Collapse immediate word repetitions ("the the" -> "the", "I I" -> "I")
        let stutterPattern = "\\b([A-Za-z]+)\\s+\\1\\b"
        if let regex = try? NSRegularExpression(pattern: stutterPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "$1"
            )
        }

        // 3. Normalize excess whitespace
        result = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !result.isEmpty else { return "" }

        // 4. Ensure first character is capitalized
        result = result.prefix(1).uppercased() + result.dropFirst()

        return result
    }

    /// Checks if a transcript is composed purely of speech fillers.
    nonisolated public func isFillerOnly(_ text: String) -> Bool {
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return true }

        let fillerSet: Set<String> = ["um", "uh", "ah", "erm", "hmm", "er"]
        return tokens.allSatisfy { fillerSet.contains($0) }
    }
}

// MARK: - Download Session Delegate

private final class S1DownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let targetURL: URL
    private let continuation: CheckedContinuation<Void, Error>
    private let onProgress: @Sendable (Double) -> Void
    private var hasResumed = false
    private let lock = NSLock()

    init(
        targetURL: URL,
        continuation: CheckedContinuation<Void, Error>,
        onProgress: @escaping @Sendable (Double) -> Void
    ) {
        self.targetURL = targetURL
        self.continuation = continuation
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true

        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.moveItem(at: location, to: targetURL)
            continuation.resume()
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            lock.lock()
            defer { lock.unlock() }
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(throwing: error)
        }
    }
}

