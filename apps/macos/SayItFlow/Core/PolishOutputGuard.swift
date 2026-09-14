import Foundation

enum PolishStructure: String, CaseIterable, Identifiable, Codable {
    case prose
    case lists
    var id: String { rawValue }
}

enum PolishOutputGuard {
    static func shouldApplyPolishResult(
        raw: String,
        polished: String,
        structure: PolishStructure = .prose
    ) -> Bool {
        let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let ratio = Double(trimmed.count) / Double(max(raw.count, 1))
        if ratio > 4.0 || ratio < 0.20 { return false }
        let minJaccard = structure == .lists ? 0.30 : 0.40
        return wordTokenJaccard(raw, trimmed) >= minJaccard
    }

    private static func wordTokenJaccard(_ left: String, _ right: String) -> Double {
        func tokens(from text: String) -> Set<String> {
            Set(
                text.lowercased()
                    .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                    .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
                    .filter { !$0.isEmpty }
            )
        }
        let a = tokens(from: left)
        let b = tokens(from: right)
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        return Double(a.intersection(b).count) / Double(max(a.union(b).count, 1))
    }
}
