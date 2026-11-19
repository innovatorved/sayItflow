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
        let compiled = Self.compileRules(for: terms)
        return Self.apply(compiled, to: text)
    }

    struct CompiledRule: @unchecked Sendable {
        let regex: NSRegularExpression
        let template: String
    }

    static func compileRules(for terms: [String]) -> [CompiledRule] {
        terms.compactMap { term in
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else {
                return nil
            }
            return CompiledRule(
                regex: regex,
                template: NSRegularExpression.escapedTemplate(for: trimmed)
            )
        }
    }

    static func apply(_ rules: [CompiledRule], to text: String) -> String {
        guard !rules.isEmpty, !text.isEmpty else { return text }
        var output = text
        for rule in rules {
            output = rule.regex.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..., in: output),
                withTemplate: rule.template
            )
        }
        return output
    }
}

enum VocabularyStore {
    private static let key = "sayitflow.customVocabulary"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedVocabulary: Vocabulary?
    nonisolated(unsafe) private static var cachedRules: [Vocabulary.CompiledRule] = []

    static func load() -> Vocabulary {
        lock.lock()
        if let cached = cachedVocabulary {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded: Vocabulary
        if let data = UserDefaults.standard.data(forKey: key),
           let vocab = try? JSONDecoder().decode(Vocabulary.self, from: data) {
            loaded = vocab
        } else {
            loaded = .empty
        }

        let rules = Vocabulary.compileRules(for: loaded.terms)
        lock.lock()
        cachedVocabulary = loaded
        cachedRules = rules
        lock.unlock()
        return loaded
    }

    static func save(_ vocabulary: Vocabulary) {
        let rules = Vocabulary.compileRules(for: vocabulary.terms)
        lock.lock()
        cachedVocabulary = vocabulary
        cachedRules = rules
        lock.unlock()

        guard let data = try? JSONEncoder().encode(vocabulary) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Hot-path helper using cached pre-compiled regexes (zero disk/JSON/regex overhead).
    static func applyCaseCorrections(to text: String) -> String {
        guard !text.isEmpty else { return text }
        _ = load()
        lock.lock()
        let rules = cachedRules
        lock.unlock()
        return Vocabulary.apply(rules, to: text)
    }

    static func invalidateCache() {
        lock.lock()
        cachedVocabulary = nil
        cachedRules = []
        lock.unlock()
    }
}
