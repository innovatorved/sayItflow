import Foundation

/// Custom vocabulary terms fed to speech recognition and polish hints.
struct Vocabulary: Codable, Equatable, Sendable {
    var terms: [String]

    static let empty = Vocabulary(terms: [])

    var speechContextHint: String {
        guard !terms.isEmpty else { return "" }
        return "Preferred terms: \(terms.joined(separator: ", "))"
    }

    func applyCaseCorrections(to text: String) -> String {
        guard !terms.isEmpty, !text.isEmpty else { return text }
        var output = text
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else {
                continue
            }
            output = regex.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..., in: output),
                withTemplate: NSRegularExpression.escapedTemplate(for: trimmed)
            )
        }
        return output
    }
}

enum VocabularyStore {
    private static let key = "sayitflow.customVocabulary"

    static func load() -> Vocabulary {
        guard let data = UserDefaults.standard.data(forKey: key),
              let vocab = try? JSONDecoder().decode(Vocabulary.self, from: data) else {
            return .empty
        }
        return vocab
    }

    static func save(_ vocabulary: Vocabulary) {
        guard let data = try? JSONEncoder().encode(vocabulary) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
