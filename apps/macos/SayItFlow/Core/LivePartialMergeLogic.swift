import Foundation

enum LivePartialMergeAction: Equatable {
    case extend(delta: String)
    case revise(to: String)
    case appendNewSegment(separator: String, segment: String)
}

/// Decides whether an STT partial extends, revises, or appends after a prior line.
enum LivePartialMergeLogic {
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    static func sharedPrefixWordCount(_ existing: String, _ incoming: String) -> Int {
        let existingWords = words(existing)
        let incomingWords = words(incoming)
        var count = 0
        for (left, right) in zip(existingWords, incomingWords) {
            if left.caseInsensitiveCompare(right) != .orderedSame { break }
            count += 1
        }
        return count
    }

    /// Incoming text after the first `wordCount` words, preserving original spacing/casing.
    static func suffixInIncoming(_ incoming: String, afterWordCount wordCount: Int) -> String {
        guard wordCount > 0 else { return incoming }
        var seen = 0
        var inWord = false
        var suffixStart = incoming.endIndex
        var idx = incoming.startIndex
        while idx < incoming.endIndex {
            let char = incoming[idx]
            if char.isWhitespace || char.isNewline {
                if inWord {
                    seen += 1
                    suffixStart = idx
                    inWord = false
                    if seen >= wordCount { break }
                }
            } else {
                inWord = true
            }
            idx = incoming.index(after: idx)
        }
        if inWord {
            seen += 1
            suffixStart = incoming.endIndex
        }
        guard seen >= wordCount else { return "" }
        return String(incoming[suffixStart...])
    }

    static func wordAlignedExtendDelta(existing: String, incoming: String) -> String? {
        let existingWords = words(existing)
        let incomingWords = words(incoming)
        guard existingWords.count <= incomingWords.count else { return nil }
        guard existingWords.isEmpty || sharedPrefixWordCount(existing, incoming) == existingWords.count else {
            return nil
        }
        if existingWords.count == incomingWords.count {
            return existing == incoming ? "" : nil
        }
        return suffixInIncoming(incoming, afterWordCount: existingWords.count)
    }

    static func merge(existing: String, incoming: String) -> LivePartialMergeAction {
        if incoming.hasPrefix(existing) {
            return .extend(delta: String(incoming.dropFirst(existing.count)))
        }
        if existing.hasPrefix(incoming) {
            return .revise(to: incoming)
        }

        let normalizedExisting = normalized(existing)
        let normalizedIncoming = normalized(incoming)
        if normalizedExisting == normalizedIncoming {
            return .revise(to: incoming)
        }
        if normalizedIncoming.hasPrefix(normalizedExisting) {
            if let delta = wordAlignedExtendDelta(existing: existing, incoming: incoming) {
                return .extend(delta: delta)
            }
            return .revise(to: incoming)
        }
        if normalizedExisting.hasPrefix(normalizedIncoming) {
            return .revise(to: incoming)
        }

        if let delta = wordAlignedExtendDelta(existing: existing, incoming: incoming) {
            return .extend(delta: delta)
        }

        if sharedPrefixWordCount(existing, incoming) >= 2 {
            return .revise(to: incoming)
        }

        let separator: String
        if existing.isEmpty || existing.hasSuffix(" ") {
            separator = ""
        } else {
            separator = " "
        }
        return .appendNewSegment(separator: separator, segment: incoming)
    }

    static func mergedText(existing: String, incoming: String) -> String {
        switch merge(existing: existing, incoming: incoming) {
        case .extend(let delta):
            return existing + delta
        case .revise(let revised):
            return revised
        case .appendNewSegment(let separator, let segment):
            return existing + separator + segment
        }
    }

    /// Final transcript pick at release. Prefix extensions win (STT finish can trail
    /// typed text); anything else means the field diverged, so trust STT.
    static func reconciledFinal(stt: String, field: String) -> String {
        let t = stt.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty else { return t }
        guard !t.isEmpty else { return f }
        if f.hasPrefix(t) || t.hasPrefix(f) {
            let longer = t.count >= f.count ? t : f
            if occurrenceCount(normalized(longer), needle: normalized(t)) >= 2 {
                return t
            }
            return longer
        }
        return t
    }

    static func occurrenceCount(_ haystack: String, needle: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<haystack.endIndex
        }
        return count
    }

    /// Text to inject after engine finish. When polish ran, never prefer longer unpolished live partials.
    static func injectionFinal(
        engineText: String,
        livePartial: String,
        fieldText: String,
        polishApplied: Bool
    ) -> String {
        let engine = engineText.trimmingCharacters(in: .whitespacesAndNewlines)
        if polishApplied, !engine.isEmpty {
            return engine
        }
        if !engine.isEmpty {
            return reconciledFinal(stt: engine, field: fieldText)
        }
        let live = livePartial.trimmingCharacters(in: .whitespacesAndNewlines)
        let field = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { return live }
        return field
    }
}
