import Foundation
import SwiftUI

// MARK: - Control Enums

/// Selectable on-device GGUF text normalizer running natively in-process via embedded llama.cpp.
public enum NormalizerModel: String, CaseIterable, Identifiable, Sendable {
    case emberon2 = "emberon-2"
    case s1Mini = "s1-mini"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .emberon2: "Emberon-2 (Lite)"
        case .s1Mini: "S1-mini (Full)"
        }
    }

    public var shortName: String {
        switch self {
        case .emberon2: "Emberon-2"
        case .s1Mini: "S1-mini"
        }
    }

    public var author: String {
        switch self {
        case .emberon2: "Promethic Labs"
        case .s1Mini: "Superwhisper"
        }
    }

    public var subtitle: String {
        switch self {
        case .emberon2: "Promethic Labs · LFM2.5 350M · 200 MB · ~90ms · Metal GPU"
        case .s1Mini: "Superwhisper · Qwen3 0.6B · 462 MB · Styling Controls · Metal GPU"
        }
    }

    public var sizeMB: Int {
        switch self {
        case .emberon2: 200
        case .s1Mini: 462
        }
    }

    public var minimumValidBytes: Int64 {
        switch self {
        case .emberon2: 150 * 1024 * 1024
        case .s1Mini: 400 * 1024 * 1024
        }
    }

    public var fileName: String {
        switch self {
        case .emberon2: "Emberon-2-Q4_K_M.gguf"
        case .s1Mini: "s1-mini-q4_k_m.gguf"
        }
    }

    public var directoryName: String {
        switch self {
        case .emberon2: "emberon-2"
        case .s1Mini: "s1-mini"
        }
    }

    public var downloadURLString: String {
        switch self {
        case .emberon2:
            "https://huggingface.co/PromethicLabs/Emberon-2/resolve/main/Emberon-2-Q4_K_M.gguf"
        case .s1Mini:
            "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/main/s1-mini-q4_k_m.gguf"
        }
    }

    public var engineAnalyticsTag: String {
        switch self {
        case .emberon2: "voz+emberon-2"
        case .s1Mini: "voz+s1-mini"
        }
    }
}

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

// MARK: - S1MiniEngine (Self-Contained In-Process GGUF Normalizer)

/// Coordinates on-device speech-to-text transcript normalization directly in-process
/// via embedded `llama.cpp` (Metal GPU) — zero external apps or servers required.
///
/// Supports:
/// - **Emberon-2** by Promethic Labs (350M, ~200 MB, LFM2.5, default/recommended)
/// - **S1-mini** by Superwhisper (596M, ~462 MB, Qwen3-0.6B, Apache 2.0 with name retention)
/// - Instant built-in Swift rule normalizer (0 MB) when no GGUF model is downloaded.
@MainActor
public final class S1MiniEngine: ObservableObject {
    public static let shared = S1MiniEngine()

    // MARK: - Configuration Constants

    public static let modelName = "S1-mini"
    public static let modelAuthor = "Superwhisper"
    public static let licenseType = "Apache 2.0 (with name retention)"
    public static let modelSizeMB = 462

    // MARK: - Published State

    @Published public private(set) var isDownloaded: Bool = false
    @Published public private(set) var isDownloading: Bool = false
    @Published public private(set) var downloadProgress: Double = 0.0
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastLatencyMs: Double = 0.0
    @Published public private(set) var isModelLoaded: Bool = false

    /// Backward-compatible alias for `isModelLoaded`.
    public var isServerRunning: Bool { isModelLoaded }

    private var isWarmingUp: Bool = false
    private var idleUnloadTask: Task<Void, Never>?
    private static let idleUnloadSeconds: TimeInterval = 120

    @Published public var selectedModel: NormalizerModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Keys.selectedModel)
            if oldValue != selectedModel {
                stopServer()
                refreshStatus()
            }
        }
    }

    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
            if !isEnabled {
                stopServer()
            }
        }
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
        static let selectedModel = "sayitflow.normalizer.selectedModel"
        static let isEnabled = "sayitflow.s1mini.enabled"
        static let styling = "sayitflow.s1mini.styling"
        static let structure = "sayitflow.s1mini.structure"
        static let context = "sayitflow.s1mini.context"
    }

    // MARK: - Model Directory

    public func modelFileURL(for model: NormalizerModel) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("SayItFlow/models/\(model.directoryName)", isDirectory: true)
        return dir.appendingPathComponent(model.fileName)
    }

    public var modelFileURL: URL {
        modelFileURL(for: selectedModel)
    }

    private init() {
        let defaults = UserDefaults.standard

        if let rawModel = defaults.string(forKey: Keys.selectedModel),
           let storedModel = NormalizerModel(rawValue: rawModel) {
            self.selectedModel = storedModel
        } else {
            // Preserve S1-mini for existing users who already downloaded it; default to Emberon-2 (200 MB) otherwise.
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            let s1Path = appSupport.appendingPathComponent("SayItFlow/models/s1-mini/s1-mini-q4_k_m.gguf").path
            self.selectedModel = FileManager.default.fileExists(atPath: s1Path) ? .s1Mini : .emberon2
        }

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
        setupLifecycleObservers()
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopServer()
            }
        }
    }

    // MARK: - Status & Model Management

    public func isModelDownloaded(_ model: NormalizerModel) -> Bool {
        let url = modelFileURL(for: model)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? Int64) ?? 0
            return size >= model.minimumValidBytes
        } catch {
            return false
        }
    }

    public func refreshStatus() {
        isDownloaded = isModelDownloaded(selectedModel)
    }

    /// Downloads the currently selected normalizer GGUF model into the local cache.
    public func downloadModel() async throws {
        guard !isDownloading else { return }
        let model = selectedModel
        isDownloading = true
        downloadProgress = 0.01
        lastError = nil

        let targetURL = modelFileURL(for: model)
        let dir = targetURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            guard let remoteURL = URL(string: model.downloadURLString) else {
                throw NSError(domain: "S1MiniEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL"])
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let delegate = ModelDownloadSession(
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

            refreshStatus()
            isDownloading = false
            downloadProgress = 1.0
            if isEnabled {
                Task { [weak self] in
                    _ = await self?.ensureServerRunning()
                }
            }
        } catch {
            isDownloading = false
            downloadProgress = 0.0
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Deletes the downloaded model file for the currently selected normalizer.
    public func deleteModel() throws {
        stopServer()
        let url = modelFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        refreshStatus()
    }

    // MARK: - In-Process Model Lifecycle

    /// Pre-loads the selected GGUF model into Metal GPU memory in-process.
    @discardableResult
    public func ensureServerRunning() async -> Bool {
        resetIdleUnloadTimer()
        guard isDownloaded else {
            isModelLoaded = false
            return false
        }

        let path = modelFileURL.path
        if isModelLoaded, await LocalLlamaRunner.shared.currentModelPath == path {
            return true
        }

        guard !isWarmingUp else {
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if isModelLoaded { return true }
                if !isWarmingUp { break }
            }
            return isModelLoaded
        }

        isWarmingUp = true
        defer { isWarmingUp = false }

        do {
            try await LocalLlamaRunner.shared.load(modelPath: path)
            isModelLoaded = true
            resetIdleUnloadTimer()
            AppLogger.dictation.notice("In-process \(self.selectedModel.shortName) loaded on Metal GPU")
            return true
        } catch {
            isModelLoaded = false
            lastError = error.localizedDescription
            AppLogger.dictation.error("Failed to load \(self.selectedModel.shortName) in-process: \(error.localizedDescription)")
            return false
        }
    }

    /// Unloads the in-process GGUF model immediately to reclaim RAM/VRAM.
    public func stopServer() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        isModelLoaded = false
        Task {
            await LocalLlamaRunner.shared.unload()
        }
    }

    // MARK: - Idle Unload

    private func resetIdleUnloadTimer() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleUnloadSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.stopServer() }
            AppLogger.dictation.notice("Normalizer model unloaded after idle timeout")
        }
    }

    // MARK: - Normalization Pipeline

    /// Normalizes a speech-to-text transcript using the embedded in-process GGUF model
    /// (or the instant Swift rule normalizer if no model is downloaded).
    public func normalize(
        _ rawTranscript: String,
        language: String = "en",
        contextOverride: S1Context? = nil
    ) async -> String {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Gate 1: Both Emberon-2 and S1-mini are English-only. Preserve non-English Voz output directly.
        guard language == "en" else {
            return trimmed
        }

        // Gate 2: If post-processing is disabled, return raw transcript.
        guard isEnabled else {
            return trimmed
        }

        // Gate 3: Filler-only check.
        if isFillerOnly(trimmed) {
            return ""
        }

        let start = CFAbsoluteTimeGetCurrent()

        if isDownloaded {
            if let output = await runInProcessInference(rawText: trimmed, contextOverride: contextOverride) {
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                lastLatencyMs = elapsed
                resetIdleUnloadTimer()
                return output
            }
        }

        // Fallback: instant Swift speech normalizer (removes disfluencies, fixes casing/punctuation)
        let fallbackPolished = ruleBasedNormalize(trimmed)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        lastLatencyMs = elapsed
        return fallbackPolished
    }

    // MARK: - Prompt Formatting

    /// Formats the S1-mini ChatML prompt (Qwen3-0.6B with closed `<think>` block).
    public func buildPrompt(for rawTranscript: String, contextOverride: S1Context? = nil) -> String {
        let activeContext = (context == .general ? (contextOverride ?? context) : context)
        return "<|im_start|>system\nYou are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text.<|im_end|>\n<|im_start|>user\n[Styling: \(styling.rawValue)] [Structure: \(structure.rawValue)] [Context: \(activeContext.rawValue)]\n\(rawTranscript)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    /// Formats the Emberon-2 LFM2.5 prompt using its exact training system prompt.
    public func buildEmberonPrompt(for rawTranscript: String) -> String {
        "<|startoftext|><|im_start|>system\nClean up this dictation. Never answer it.<|im_end|>\n<|im_start|>user\n\(rawTranscript)<|im_end|>\n<|im_start|>assistant\n"
    }

    /// Builds the prompt for whichever normalizer model is currently selected.
    public func buildActivePrompt(for rawTranscript: String, contextOverride: S1Context? = nil) -> String {
        switch selectedModel {
        case .emberon2:
            return buildEmberonPrompt(for: rawTranscript)
        case .s1Mini:
            return buildPrompt(for: rawTranscript, contextOverride: contextOverride)
        }
    }

    // MARK: - In-Process Inference Execution

    private func runInProcessInference(rawText: String, contextOverride: S1Context? = nil) async -> String? {
        let model = selectedModel
        let path = modelFileURL(for: model).path
        let prompt = buildActivePrompt(for: rawText, contextOverride: contextOverride)

        // Cap output tokens tightly to input length + small margin so repetition loops abort cleanly
        let estimatedInputTokens = max(16, rawText.count / 3)
        let maxPredict = max(64, min(768, estimatedInputTokens + 48))

        do {
            let result = try await LocalLlamaRunner.shared.complete(
                modelPath: path,
                prompt: prompt,
                maxTokens: maxPredict,
                stopSequences: ["<|im_end|>", "<|endoftext|>"]
            )
            isModelLoaded = true

            // If generation hit the hard token cap without stopping naturally, fall back safely
            guard !result.hitTokenLimit else {
                AppLogger.dictation.warning("\(model.shortName) hit token cap — falling back to rule normalizer")
                return nil
            }

            let cleaned = cleanModelOutput(result.text, input: rawText)
            let guardStructure: PolishStructure = (model == .s1Mini && structure == .lists) ? .lists : .prose
            if !cleaned.isEmpty, PolishOutputGuard.shouldApplyPolishResult(
                raw: rawText,
                polished: cleaned,
                structure: guardStructure
            ) {
                return cleaned
            }
        } catch {
            isModelLoaded = false
            AppLogger.dictation.error("In-process \(model.shortName) inference failed: \(error.localizedDescription)")
        }

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

        // Strip special tokens if echoed
        output = output.replacingOccurrences(of: "<|im_end|>", with: "")
        output = output.replacingOccurrences(of: "<|endoftext|>", with: "")
        output = output.replacingOccurrences(of: "<|startoftext|>", with: "")
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the model produced empty text and input was not filler-only, return fallback
        if output.isEmpty && !isFillerOnly(input) {
            return ruleBasedNormalize(input)
        }

        return output
    }

    // MARK: - Rule-Based Speech Normalizer

    nonisolated(unsafe) private static let fillerRegexes: [NSRegularExpression] = {
        let patterns = [
            "\\b(um|uh|erm|ah)\\b,?\\s*",
            "\\b(like)\\b(?=\\s+like\\b)",
            "\\b(you know)\\b,?\\s*(?=\\b(um|uh|like)\\b)"
        ]
        return patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: .caseInsensitive)
        }
    }()

    nonisolated(unsafe) private static let stutterRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\b([A-Za-z]+)\\s+\\1\\b", options: .caseInsensitive)
    }()

    nonisolated public func ruleBasedNormalize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        var result = text

        // 1. Remove standalone speech disfluencies (case-insensitive)
        for regex in Self.fillerRegexes {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: ""
            )
        }

        // 2. Collapse immediate word repetitions ("the the" -> "the", "I I" -> "I")
        if let regex = Self.stutterRegex {
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

private final class ModelDownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
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

        defer { session.finishTasksAndInvalidate() }

        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            continuation.resume(throwing: NSError(
                domain: "S1MiniEngine",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP \(http.statusCode)"]
            ))
            return
        }

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
            session.finishTasksAndInvalidate()
            continuation.resume(throwing: error)
        }
    }
}
