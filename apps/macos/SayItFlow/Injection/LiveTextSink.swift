import Foundation

/// Receives live partial and committed transcript text during dictation.
@MainActor
protocol LiveTextSink: AnyObject {
    func beginSession(prefix: String) -> Bool
    func updateLive(_ partial: String)
    func commitChunk(_ chunk: String)
    func finalize(partial: String) -> String
    func endSession()
    func replaceAllCommitted(with polished: String, matchingRaw raw: String)
    /// Sync sink + target field to the final STT transcript before end-of-session polish.
    func reconcileFinalTranscript(_ raw: String)
    var chunkCount: Int { get }
    var committedTranscript: String { get }
    var hasActiveLiveTail: Bool { get }
    /// Best-effort transcript currently visible in the target field (may exceed STT finish).
    var visibleTranscript: String { get }
    /// True when live typing into the target field has stalled mid-session.
    var injectionBlocked: Bool { get }
}

extension LiveTextSink {
    func replaceAllCommitted(with polished: String) {
        replaceAllCommitted(with: polished, matchingRaw: committedTranscript)
    }

    func reconcileFinalTranscript(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replaceAllCommitted(with: trimmed, matchingRaw: trimmed)
    }

    var hasActiveLiveTail: Bool { false }

    var visibleTranscript: String { committedTranscript }

    var injectionBlocked: Bool { false }
}

/// In-app TextEditor sink (onboarding / test dictation).
@MainActor
final class ClosureLiveTextSink: LiveTextSink {
    private var prefix = ""
    private var tracker = InjectedChunkTracker()
    private var lastEmittedPartial = ""
    private var isActive = false
    private let onUpdate: (String) -> Void

    init(onUpdate: @escaping (String) -> Void) {
        self.onUpdate = onUpdate
    }

    var chunkCount: Int { tracker.chunkCount }

    var committedTranscript: String { tracker.trimmedCommitted() }
    var injectionBlocked: Bool { false }
    var hasActiveLiveTail: Bool { !lastEmittedPartial.isEmpty }
    var visibleTranscript: String {
        let tail = lastEmittedPartial.trimmingCharacters(in: .whitespaces)
        let committed = committedTranscript
        if tail.isEmpty { return committed }
        if committed.isEmpty { return tail }
        return committed + " " + tail
    }

    func beginSession(prefix: String) -> Bool {
        self.prefix = prefix
        tracker.reset()
        lastEmittedPartial = ""
        isActive = true
        return true
    }

    func updateLive(_ partial: String) {
        // Tail-only when mid-session commits occur; full cumulative STT when commits are deferred.
        guard isActive else { return }
        let incoming = partial.trimmingCharacters(in: .whitespaces)
        let sessionTail: String
        if tracker.committedText.isEmpty {
            if lastEmittedPartial.isEmpty {
                sessionTail = incoming
            } else {
                sessionTail = LivePartialMergeLogic.mergedText(
                    existing: lastEmittedPartial,
                    incoming: incoming
                )
            }
        } else {
            sessionTail = incoming
        }
        lastEmittedPartial = sessionTail
        let visible = prefix + tracker.committedText + sessionTail
        onUpdate(visible)
    }

    func commitChunk(_ chunk: String) {
        guard isActive, !chunk.isEmpty else { return }
        _ = tracker.appendChunk(chunk, injectedLength: chunk.count)
        lastEmittedPartial = ""
        onUpdate(prefix + tracker.committedText)
    }

    func replaceAllCommitted(with polished: String, matchingRaw raw: String) {
        guard isActive else { return }
        tracker.replaceAllCommitted(with: polished)
        onUpdate(prefix + tracker.committedText)
    }

    func reconcileFinalTranscript(_ raw: String) {
        guard isActive else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tracker.replaceAllCommitted(with: trimmed)
        lastEmittedPartial = ""
        onUpdate(prefix + tracker.committedText)
    }

    func finalize(partial: String) -> String {
        guard isActive else { return partial }
        let trimmed = partial.trimmingCharacters(in: .whitespaces)
        let committed = tracker.committedText.trimmingCharacters(in: .whitespaces)
        if committed.isEmpty {
            tracker.appendTail(trimmed)
        } else if trimmed.hasPrefix(committed) {
            // Only append the uncommitted remainder — never the whole partial again.
            let tail = String(trimmed.dropFirst(committed.count)).trimmingCharacters(in: .whitespaces)
            tracker.appendTail(tail)
        }
        // Non-prefix finals were already reconciled upstream; keep committed text as-is.
        let final = tracker.trimmedCommitted()
        onUpdate(prefix + final)
        // Capture before endSession — it resets the tracker.
        endSession()
        return final
    }

    func endSession() {
        isActive = false
        prefix = ""
        tracker.reset()
        lastEmittedPartial = ""
    }
}

/// Live injection via simulated keystrokes when AX cannot pin the field (Chrome, Electron).
@MainActor
final class KeystrokeOnlyLiveTextSink: LiveTextSink {
    private var tracker = InjectedChunkTracker()
    private var lastEmittedPartial = ""
    private var isActive = false
    private var consecutiveTypeFailures = 0
    private var injectionBlockedFlag = false

    var chunkCount: Int { tracker.chunkCount }
    var committedTranscript: String { tracker.trimmedCommitted() }
    var injectionBlocked: Bool { injectionBlockedFlag }
    var hasActiveLiveTail: Bool { !lastEmittedPartial.isEmpty }
    var visibleTranscript: String {
        let tail = lastEmittedPartial.trimmingCharacters(in: .whitespaces)
        let committed = committedTranscript
        if tail.isEmpty { return committed }
        if committed.isEmpty { return tail }
        return committed + " " + tail
    }

    func beginSession(prefix: String) -> Bool {
        _ = prefix
        tracker.reset()
        lastEmittedPartial = ""
        consecutiveTypeFailures = 0
        injectionBlockedFlag = false
        isActive = true
        return true
    }

    /// Seed already-typed live text after mid-session fallback so updateLive only emits deltas.
    func adoptLivePrefix(_ text: String) {
        lastEmittedPartial = text.trimmingCharacters(in: .whitespaces)
    }

    func updateLive(_ partial: String) {
        guard isActive else { return }
        typePartialDelta(partial.trimmingCharacters(in: .whitespaces))
    }

    func commitChunk(_ chunk: String) {
        guard isActive, !chunk.isEmpty else { return }
        _ = tracker.appendChunk(chunk, injectedLength: chunk.count)
        lastEmittedPartial = ""
    }

    func replaceAllCommitted(with polished: String, matchingRaw raw: String) {
        guard isActive else { return }
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !polished.isEmpty, polished != trimmedRaw else { return }
        guard !hasActiveLiveTail else {
            return
        }

        tracker.replaceAllCommitted(with: polished)
        KeystrokeEmitter.selectAndReplace(
            raw: trimmedRaw,
            injectedLength: trimmedRaw.count,
            polished: polished,
            maxBackwardUnits: typedCharacterBudget()
        )
        lastEmittedPartial = ""
    }

    func reconcileFinalTranscript(_ raw: String) {
        guard isActive else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sessionBody = visibleTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let budget = typedCharacterBudget()
        if budget > 0, !sessionBody.isEmpty {
            _ = KeystrokeEmitter.selectAndReplace(
                raw: sessionBody,
                injectedLength: sessionBody.count,
                polished: trimmed,
                maxBackwardUnits: budget
            )
        } else if sessionBody.isEmpty {
            _ = KeystrokeEmitter.typeText(trimmed)
        }
        tracker.replaceAllCommitted(with: trimmed)
        lastEmittedPartial = ""
    }

    func finalize(partial: String) -> String {
        guard isActive else { return partial }
        var result = tracker.trimmedCommitted()
        if result.isEmpty {
            let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                typePartialDelta(trimmed)
                tracker.appendTail(trimmed)
                result = tracker.trimmedCommitted()
            }
        }
        endSession()
        return result.isEmpty ? partial.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }

    func endSession() {
        isActive = false
        tracker.reset()
        lastEmittedPartial = ""
        consecutiveTypeFailures = 0
        injectionBlockedFlag = false
    }

    private func markTypeFailure() {
        consecutiveTypeFailures += 1
        if consecutiveTypeFailures >= 2 {
            injectionBlockedFlag = true
        }
    }

    private func typePartialDelta(_ partial: String) {
        let budget = typedCharacterBudget()
        switch LivePartialMergeLogic.merge(existing: lastEmittedPartial, incoming: partial) {
        case .extend(let delta):
            if delta.isEmpty {
                lastEmittedPartial = partial
                return
            }
            guard KeystrokeEmitter.typeText(delta) else {
                markTypeFailure()
                return
            }
        case .revise(let revised):
            guard revised != lastEmittedPartial else { return }
            let existingChars = Array(lastEmittedPartial)
            let revisedChars = Array(revised)
            var common = 0
            while common < existingChars.count && common < revisedChars.count && existingChars[common] == revisedChars[common] {
                common += 1
            }
            let deleteCount = existingChars.count - common
            if deleteCount <= 8 {
                for _ in 0..<deleteCount {
                    _ = KeystrokeEmitter.deleteSelection()
                }
                let suffix = String(revisedChars[common...])
                if !suffix.isEmpty {
                    _ = KeystrokeEmitter.typeText(suffix)
                }
                consecutiveTypeFailures = 0
                lastEmittedPartial = revised
                return
            }
            return
        case .appendNewSegment(let separator, let segment):
            let delta = separator + segment
            guard KeystrokeEmitter.typeText(delta) else {
                markTypeFailure()
                return
            }
            consecutiveTypeFailures = 0
            lastEmittedPartial = lastEmittedPartial + delta
            return
        }
        consecutiveTypeFailures = 0
        lastEmittedPartial = partial
    }

    /// Characters this sink has typed — never select backward past this count.
    private func typedCharacterBudget() -> Int {
        tracker.backwardSelectUnits(characterSelect: true) + lastEmittedPartial.count
    }
}
