import Foundation

/// Detects phrase boundaries for chunked polish during live dictation.
struct ChunkBoundaryDetector: Sendable {
    static let pauseDebounceSeconds: CFTimeInterval = 0.9
    static let lightPauseDebounceSeconds: CFTimeInterval = 0.65
    static let wordBudget = 10
    static let lightWordBudget = 7
    static let minimumChunkWords = 4
    static let lightMinimumChunkWords = 4
    static let sentenceMinimumChunkWords = 3

    let intensity: PolishIntensity

    init(intensity: PolishIntensity = .light) {
        self.intensity = intensity
    }

    private(set) var lastCommittedIndex = 0
    private var lastPartial = ""
    private var lastChangeAt: CFAbsoluteTime?
    private var wordsSinceLastCommit = 0

    /// Returns a phrase completed only by a speaking pause (no sentence/word budget).
    mutating func extractPauseBoundary(
        from fullText: String,
        now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    ) -> String? {
        let text = fullText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        if text != lastPartial {
            lastPartial = text
            lastChangeAt = now
        }

        let pauseDebounce = intensity == .light
            ? Self.lightPauseDebounceSeconds
            : Self.pauseDebounceSeconds
        return extractPauseChunk(from: text, now: now, debounce: pauseDebounce)
    }

    /// Returns newly completed phrase text when a boundary is found, nil otherwise.
    mutating func extractChunk(from fullText: String, now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> String? {
        let text = fullText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        if text != lastPartial {
            lastPartial = text
            lastChangeAt = now
        }

        if let sentence = extractSentenceChunk(from: text) {
            wordsSinceLastCommit = 0
            return sentence
        }

        let pauseDebounce = intensity == .light
            ? Self.lightPauseDebounceSeconds
            : Self.pauseDebounceSeconds
        if let pause = extractPauseChunk(from: text, now: now, debounce: pauseDebounce) {
            wordsSinceLastCommit = 0
            return pause
        }

        let budget = intensity == .light ? Self.lightWordBudget : Self.wordBudget
        if let word = extractWordBudgetChunk(from: text, budget: budget) {
            wordsSinceLastCommit = 0
            return word
        }
        return nil
    }

    mutating func reset() {
        lastCommittedIndex = 0
        lastPartial = ""
        lastChangeAt = nil
        wordsSinceLastCommit = 0
    }

    /// Sync detector state when a phrase was committed via STT segment callbacks.
    mutating func noteExternalCommit(chunk: String, in fullText: String) {
        let text = fullText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !chunk.isEmpty else { return }
        guard lastCommittedIndex <= text.count else { return }
        let searchStart = text.index(text.startIndex, offsetBy: lastCommittedIndex)
        guard searchStart < text.endIndex,
              let range = text.range(of: chunk, range: searchStart..<text.endIndex) else {
            lastCommittedIndex = min(text.count, lastCommittedIndex + chunk.count)
            return
        }
        lastCommittedIndex = text.distance(from: text.startIndex, to: range.upperBound)
        lastPartial = text
        lastChangeAt = nil
    }

    /// Remaining text after last committed boundary.
    func remainder(in fullText: String) -> String {
        let text = fullText.trimmingCharacters(in: .whitespaces)
        guard lastCommittedIndex < text.count else { return "" }
        let start = text.index(text.startIndex, offsetBy: lastCommittedIndex)
        return String(text[start...]).trimmingCharacters(in: .whitespaces)
    }

    func shouldPolish(_ chunk: String) -> Bool {
        Self.shouldPolish(chunk, intensity: intensity)
    }

    static func shouldPolish(_ chunk: String, intensity: PolishIntensity = .light) -> Bool {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        let count = words.count
        if endsSentence(trimmed), count >= sentenceMinimumChunkWords {
            return true
        }
        let minimum = intensity == .light ? lightMinimumChunkWords : minimumChunkWords
        return count >= minimum
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return ".!?".contains(last)
    }

    private mutating func extractSentenceChunk(from text: String) -> String? {
        guard text.count > lastCommittedIndex else { return nil }
        let start = text.index(text.startIndex, offsetBy: lastCommittedIndex)
        let slice = text[start...]
        let delimiters: [Character] = [".", "!", "?"]

        guard let delimIndex = slice.firstIndex(where: { delimiters.contains($0) }) else {
            return nil
        }
        let end = text.index(after: delimIndex)
        let chunk = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
        guard shouldPolish(chunk) else {
            lastCommittedIndex = text.distance(from: text.startIndex, to: end)
            return nil
        }
        lastCommittedIndex = text.distance(from: text.startIndex, to: end)
        return chunk
    }

    private mutating func extractPauseChunk(
        from text: String,
        now: CFAbsoluteTime,
        debounce: CFTimeInterval
    ) -> String? {
        guard let changeAt = lastChangeAt, now - changeAt >= debounce else { return nil }
        guard text.count > lastCommittedIndex else { return nil }
        let start = text.index(text.startIndex, offsetBy: lastCommittedIndex)
        var chunk = String(text[start...]).trimmingCharacters(in: .whitespaces)
        chunk = dropIncompleteTrailingWord(chunk)
        guard shouldPolish(chunk) else { return nil }
        if let range = text.range(of: chunk, range: start..<text.endIndex) {
            lastCommittedIndex = text.distance(from: text.startIndex, to: range.upperBound)
        } else {
            lastCommittedIndex = text.count
        }
        lastChangeAt = nil
        return chunk
    }

    private mutating func extractWordBudgetChunk(from text: String, budget: Int) -> String? {
        guard text.count > lastCommittedIndex else { return nil }
        let start = text.index(text.startIndex, offsetBy: lastCommittedIndex)
        let tail = String(text[start...])
        let words = tail.split(whereSeparator: { $0.isWhitespace })
        wordsSinceLastCommit = words.count
        guard wordsSinceLastCommit >= budget else { return nil }

        let chunkWords = words.prefix(budget)
        let chunk = chunkWords.joined(separator: " ")
        guard shouldPolish(chunk) else { return nil }
        if let range = text.range(of: chunk, range: start..<text.endIndex) {
            lastCommittedIndex = text.distance(from: text.startIndex, to: range.upperBound)
        }
        return chunk
    }

    /// Drop a trailing partial word while the speaker is still talking.
    private func dropIncompleteTrailingWord(_ phrase: String) -> String {
        guard !phrase.isEmpty else { return phrase }
        if Self.endsSentence(phrase) { return phrase }
        guard let lastSpace = phrase.lastIndex(where: { $0.isWhitespace }) else { return phrase }
        let trimmed = String(phrase[..<lastSpace]).trimmingCharacters(in: .whitespaces)
        if shouldPolish(trimmed) {
            return trimmed
        }
        return phrase
    }
}
