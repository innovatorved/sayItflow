import Foundation

/// Tracks dictation session identity so async work can detect stale sessions.
struct DictationSessionGate: Sendable {
    private(set) var currentID: UInt64 = 0

    mutating func begin() -> UInt64 {
        currentID &+= 1
        return currentID
    }

    mutating func invalidate() {
        currentID &+= 1
    }

    func isValid(_ id: UInt64, cancelled: Bool) -> Bool {
        !cancelled && currentID == id
    }
}
