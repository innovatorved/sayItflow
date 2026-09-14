import Foundation

/// Pure hold-space state machine (unit-testable, no event taps).
/// Tap Space passes through unchanged; only hold ≥ threshold activates dictation.
struct HoldSpaceKeyLogic: Sendable {
    static let holdThresholdSeconds: CFTimeInterval = 0.25

    struct KeyUpResult: Equatable {
        var consume: Bool
        var endDictation: Bool
    }

    private(set) var spaceDownAt: CFAbsoluteTime?
    private(set) var holdActivated = false

    /// Returns whether the keyDown event should be consumed (swallowed).
    /// First press and autorepeat pass through until hold activates.
    mutating func keyDown(isRepeat: Bool, isDictating: Bool) -> Bool {
        if holdActivated || isDictating {
            return true
        }
        if isRepeat {
            return false
        }
        spaceDownAt = CFAbsoluteTimeGetCurrent()
        return false
    }

    /// Returns `true` when dictation should begin after the hold threshold.
    mutating func thresholdElapsed(isDictating: Bool) -> Bool {
        guard spaceDownAt != nil, !holdActivated, !isDictating else { return false }
        holdActivated = true
        return true
    }

    mutating func keyUp(
        now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        isDictating: Bool
    ) -> KeyUpResult {
        let activated = holdActivated
        let downAt = spaceDownAt
        spaceDownAt = nil
        holdActivated = false

        // Once the hold activated, the release must always end dictation. Reporting
        // `isDictating` alone let a release that raced the activation timer be
        // swallowed, starting a session with no matching end.
        if activated || isDictating {
            return KeyUpResult(consume: true, endDictation: activated || isDictating)
        }
        if let downAt, now - downAt < Self.holdThresholdSeconds {
            return KeyUpResult(consume: false, endDictation: false)
        }
        return KeyUpResult(consume: false, endDictation: false)
    }

    mutating func reset() {
        spaceDownAt = nil
        holdActivated = false
    }
}
