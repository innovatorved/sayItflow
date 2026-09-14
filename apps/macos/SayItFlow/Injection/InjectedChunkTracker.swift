import Foundation

struct InjectedChunk: Equatable {
    let raw: String
    var committedStart: Int
    var textLength: Int
    var injectedLength: Int
    var polished: String?
}

/// Index-based committed text + chunk metadata (avoids fragile `range(of:)` matching).
struct InjectedChunkTracker {
    private(set) var committedText = ""
    private(set) var chunks: [InjectedChunk] = []

    var chunkCount: Int { chunks.count }

    mutating func reset() {
        committedText = ""
        chunks = []
    }

    @discardableResult
    mutating func appendChunk(_ raw: String, injectedLength: Int) -> Int {
        let normalized = raw
        let start = committedText.count
        committedText += normalized
        if !committedText.hasSuffix(" ") && !normalized.hasSuffix(" ") {
            committedText += " "
        }
        let chunk = InjectedChunk(
            raw: normalized,
            committedStart: start,
            textLength: normalized.count,
            injectedLength: injectedLength,
            polished: nil
        )
        chunks.append(chunk)
        return chunks.count - 1
    }

    mutating func appendTail(_ tail: String) {
        guard !tail.isEmpty else { return }
        committedText += tail
        if !committedText.hasSuffix(" ") {
            committedText += " "
        }
    }

    mutating func replaceChunk(at index: Int, with polished: String) -> Bool {
        guard chunks.indices.contains(index) else { return false }
        let chunk = chunks[index]
        guard !polished.isEmpty, polished != (chunk.polished ?? chunk.raw) else { return false }

        let start = chunk.committedStart
        let end = start + chunk.textLength
        guard start <= committedText.count, end <= committedText.count, start <= end else { return false }

        let startIdx = committedText.index(committedText.startIndex, offsetBy: start)
        let endIdx = committedText.index(committedText.startIndex, offsetBy: end)
        committedText.replaceSubrange(startIdx..<endIdx, with: polished)

        let lengthDelta = polished.count - chunk.textLength
        chunks[index].polished = polished
        chunks[index].textLength = polished.count
        chunks[index].injectedLength = polished.count

        if lengthDelta != 0 {
            for i in (index + 1)..<chunks.count {
                chunks[i].committedStart += lengthDelta
            }
        }
        return true
    }

    mutating func replaceAllCommitted(with text: String) {
        committedText = text
        if !committedText.isEmpty && !committedText.hasSuffix(" ") {
            committedText += " "
        }
        chunks.removeAll()
    }

    func trimmedCommitted() -> String {
        committedText.trimmingCharacters(in: .whitespaces)
    }

    func backwardSelectUnits(characterSelect: Bool) -> Int {
        if characterSelect {
            return chunks.reduce(0) { $0 + $1.injectedLength }
        }
        return chunks.reduce(0) { sum, chunk in
            sum + chunk.raw.split(whereSeparator: { $0.isWhitespace }).count
        }
    }
}
