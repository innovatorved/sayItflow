import AppKit
import ApplicationServices
import Carbon
import Foundation

/// Live text injection into a pinned AX field while dictating.
@MainActor
final class StreamingTextInjector: LiveTextSink {
    private var pinnedElement: AXUIElement?
    private var pinnedPID: pid_t?
    private var pinnedBundleID: String?
    private var prefixBeforeSession = ""
    private var tracker = InjectedChunkTracker()
    private var livePartial = ""
    private var lastReceivedPartial = ""
    private var lastDisplayed = ""
    private var lastEmittedPartial = ""
    private var keystrokeModeActive = false
    private var isActive = false
    private var lastPasteAttempt: CFAbsoluteTime = 0
    private(set) var usedClipboardFallback = false
    private(set) var liveInjectionDegraded = false
    private(set) var secureInputDetected = false

    var injectionBlocked: Bool {
        liveInjectionDegraded || secureInputDetected || pinnedElement == nil
    }

    var hasActiveSession: Bool { isActive }
    var pinnedAXElement: AXUIElement? { pinnedElement }
    var pinnedProcessID: pid_t? { pinnedPID }
    var chunkCount: Int { tracker.chunkCount }
    var committedTranscript: String { tracker.trimmedCommitted() }
    var hasActiveLiveTail: Bool { !livePartial.isEmpty || !lastEmittedPartial.isEmpty }
    var visibleTranscript: String {
        if let element = pinnedElement, let full = readValue(from: element) {
            if !prefixBeforeSession.isEmpty, full.hasPrefix(prefixBeforeSession) {
                return String(full.dropFirst(prefixBeforeSession.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Field diverged from pin-time prefix — use only what this session typed.
            return dictatedBodyText().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let tail = livePartial.isEmpty ? lastEmittedPartial : livePartial
        let committed = committedTranscript
        if tail.isEmpty { return committed }
        if committed.isEmpty { return tail }
        return committed + " " + tail
    }

    /// Pin focus synchronously at hotkey press — before async mic/engine startup.
    func pinFocusedElement() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let element = queryFocusedElement() else { return false }
        prefixBeforeSession = readValue(from: element) ?? ""
        pinnedElement = element
        pinnedPID = AXHelpers.processID(of: element)
        pinnedBundleID = AXHelpers.bundleIdentifier(of: element)
        tracker.reset()
        livePartial = ""
        lastReceivedPartial = ""
        lastDisplayed = ""
        lastEmittedPartial = ""
        keystrokeModeActive = false
        isActive = true
        usedClipboardFallback = false
        liveInjectionDegraded = false
        secureInputDetected = false
        wasReconciledInField = false
        SessionTrace.log(
            "pinFocusedElement pinned PID \(pinnedPID ?? -1) (\(pinnedBundleID ?? "unknown")) prefixLen=\(prefixBeforeSession.count)",
            category: "injection"
        )
        return true
    }

    func beginSession(prefix: String) -> Bool {
        if isActive { return true }
        return pinFocusedElement()
    }

    func updateLive(_ partial: String) {
        guard isActive else { return }
        livePartial = partial.trimmingCharacters(in: .whitespaces)
        let partialChanged = livePartial != lastReceivedPartial
        lastReceivedPartial = livePartial
        let visible = composedVisibleText()
        guard visible != lastDisplayed || partialChanged else { return }

        if SecureInputChecker.isActive() {
            secureInputDetected = true
            liveInjectionDegraded = true
            return
        }

        refreshPinnedElementIfNeeded()

        if applyKeystrokeDelta(for: livePartial) {
            keystrokeModeActive = true
            lastDisplayed = visible
            return
        }

        if syncFullValue(visible) {
            return
        }
    }

    func commitChunk(_ chunk: String) {
        guard isActive, !chunk.isEmpty, pinnedElement != nil else { return }
        _ = tracker.appendChunk(chunk, injectedLength: chunk.count)
        livePartial = ""
        lastEmittedPartial = ""
        let visible = composedVisibleText()
        lastDisplayed = visible
        if !keystrokeModeActive {
            _ = writeFullValue(visible)
        }
    }

    func replaceAllCommitted(with polished: String, matchingRaw raw: String) {
        guard isActive, pinnedElement != nil else { return }
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !polished.isEmpty, polished != trimmedRaw else { return }

        if !PolishOutputGuard.shouldApplyPolishResult(raw: trimmedRaw, polished: polished) {
            return
        }

        if hasActiveLiveTail {
            return
        }

        refreshPinnedElementIfNeeded()
        tracker.replaceAllCommitted(with: polished)
        livePartial = ""
        lastEmittedPartial = ""
        let visible = composedVisibleText()
        lastDisplayed = visible

        if keystrokeModeActive {
            let selectTotal = trimmedRaw.count
            let applied = selectAndReplace(
                raw: trimmedRaw,
                injectedLength: selectTotal,
                polished: polished
            )
            if !applied, selectTotal > 0 {
                if !syncFullValue(visible) {
                    liveInjectionDegraded = true
                }
            }
            return
        }

        if !syncFullValue(visible) {
            liveInjectionDegraded = true
        }
    }

    private var wasReconciledInField = false

    func reconcileFinalTranscript(_ raw: String) {
        guard isActive else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        livePartial = ""
        lastEmittedPartial = ""
        keystrokeModeActive = false
        tracker.replaceAllCommitted(with: trimmed)
        refreshPinnedElementIfNeeded()
        let visible = composedVisibleText()
        lastDisplayed = visible
        if syncFullValue(visible) {
            wasReconciledInField = true
            SessionTrace.log("reconcileFinalTranscript: AX sync succeeded ('\(trimmed)')", category: "injection")
            return
        }

        let sessionBody = visibleTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sessionBody.isEmpty,
           selectAndReplace(raw: sessionBody, injectedLength: sessionBody.count, polished: trimmed) {
            lastDisplayed = composedVisibleText()
            wasReconciledInField = true
            SessionTrace.log("reconcileFinalTranscript: selectAndReplace succeeded ('\(trimmed)')", category: "injection")
        } else if sessionBody.isEmpty {
            // Nothing was in the field yet; type it
            if KeystrokeEmitter.typeText(trimmed) {
                wasReconciledInField = true
                SessionTrace.log("reconcileFinalTranscript: KeystrokeEmitter typed fresh ('\(trimmed)')", category: "injection")
            } else {
                liveInjectionDegraded = true
                SessionTrace.log("reconcileFinalTranscript: KeystrokeEmitter typing failed", category: "injection")
            }
        } else {
            liveInjectionDegraded = true
            SessionTrace.log("reconcileFinalTranscript: degradation detected", category: "injection")
        }
    }

    func finalize(partial: String) -> String {
        guard isActive else { return partial }
        let trimmedPartial = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = tracker.trimmedCommitted()
        if result.isEmpty, !trimmedPartial.isEmpty {
            tracker.appendTail(trimmedPartial)
            result = tracker.trimmedCommitted()
        }

        SessionTrace.log(
            "finalize called (result='\(result)', wasReconciled=\(wasReconciledInField), degraded=\(liveInjectionDegraded))",
            category: "injection"
        )

        if !result.isEmpty {
            if SecureInputChecker.isActive() || secureInputDetected {
                secureInputDetected = true
                usedClipboardFallback = true
                InjectionFallback.copyToClipboardWithFeedback(result)
                SessionTrace.log("finalize: Secure input detected — copied to clipboard", category: "injection")
            } else if !wasReconciledInField {
                // Only attempt field rewrite if it was not already reconciled by keystrokes/AX
                refreshPinnedElementIfNeeded()
                if let element = pinnedElement {
                    let full = prefixBeforeSession + result
                    if AXUIElementSetAttributeValue(
                        element,
                        kAXValueAttribute as CFString,
                        full as CFTypeRef
                    ) != .success {
                        // If direct AX value write failed, try typing or pasteboard rescue
                        if !PasteboardRescue.paste(result) {
                            usedClipboardFallback = true
                            InjectionFallback.copyToClipboardWithFeedback(result)
                            SessionTrace.log("finalize: AX write & paste failed — copied to clipboard", category: "injection")
                        } else {
                            SessionTrace.log("finalize: Pasted successfully", category: "injection")
                        }
                    } else {
                        SessionTrace.log("finalize: AX write succeeded", category: "injection")
                    }
                } else {
                    usedClipboardFallback = true
                    InjectionFallback.copyToClipboardWithFeedback(result)
                    SessionTrace.log("finalize: No element pinned — copied to clipboard", category: "injection")
                }
            } else {
                SessionTrace.log("finalize: Field was already reconciled cleanly", category: "injection")
            }
        }

        endSession()
        return result.isEmpty ? partial : result
    }

    func endSession() {
        isActive = false
        pinnedElement = nil
        pinnedPID = nil
        pinnedBundleID = nil
        prefixBeforeSession = ""
        tracker.reset()
        livePartial = ""
        lastReceivedPartial = ""
        lastDisplayed = ""
        lastEmittedPartial = ""
        keystrokeModeActive = false
        wasReconciledInField = false
    }

    private func composedVisibleText() -> String {
        prefixBeforeSession + dictatedBodyText()
    }

    private func dictatedBodyText() -> String {
        let committed = tracker.committedText
        let sessionTail: String
        if lastEmittedPartial.isEmpty {
            sessionTail = livePartial
        } else if livePartial.isEmpty {
            sessionTail = lastEmittedPartial
        } else {
            sessionTail = LivePartialMergeLogic.mergedText(
                existing: lastEmittedPartial,
                incoming: livePartial
            )
        }
        return committed + sessionTail
    }

    private func refreshPinnedElementIfNeeded() {
        guard let pinned = pinnedElement else { return }
        guard let current = queryFocusedElement() else { return }
        if CFEqual(pinned, current) { return }

        let currentPID = AXHelpers.processID(of: current)
        let currentBundleID = AXHelpers.bundleIdentifier(of: current)
        if InjectionSessionGuardLogic.isGenuineFocusDrift(
            pinnedPID: pinnedPID,
            currentPID: currentPID,
            pinnedBundleID: pinnedBundleID,
            currentBundleID: currentBundleID,
            handlesEqual: false,
            currentIsTextInput: AXHelpers.isTextInputElement(current)
        ) {
            return
        }

        pinnedElement = current
        if let currentPID {
            pinnedPID = currentPID
        }
        if let currentBundleID {
            pinnedBundleID = currentBundleID
        }
    }

    /// Refresh AX pin without resetting committed transcript state.
    @discardableResult
    private func repinFocusedElementIfNeeded() -> Bool {
        guard let current = queryFocusedElement() else { return false }
        pinnedElement = current
        pinnedPID = AXHelpers.processID(of: current)
        pinnedBundleID = AXHelpers.bundleIdentifier(of: current)
        return true
    }

    /// Re-pin mid-session (guard recovery) without resetting typed state.
    func repinPreservingSession() -> Bool {
        guard let current = queryFocusedElement() else { return false }
        pinnedElement = current
        pinnedPID = AXHelpers.processID(of: current)
        pinnedBundleID = AXHelpers.bundleIdentifier(of: current)

        let body = dictatedBodyText()
        if !body.isEmpty, let full = readValue(from: current), full.hasSuffix(body) {
            prefixBeforeSession = String(full.dropLast(body.count))
        }
        isActive = true
        return true
    }

    private func applyKeystrokeDelta(for partial: String) -> Bool {
        if SecureInputChecker.isActive() { return false }

        switch LivePartialMergeLogic.merge(existing: lastEmittedPartial, incoming: partial) {
        case .extend(let delta):
            guard delta.isEmpty || KeystrokeEmitter.typeText(delta) else { return false }
            lastEmittedPartial = partial
            return true
        case .revise(let revised):
            guard revised != lastEmittedPartial else { return true }
            let existingChars = Array(lastEmittedPartial)
            let revisedChars = Array(revised)
            var common = 0
            while common < existingChars.count && common < revisedChars.count && existingChars[common] == revisedChars[common] {
                common += 1
            }
            let deleteCount = existingChars.count - common
            guard deleteCount <= 8 else { return false }
            for _ in 0..<deleteCount {
                _ = KeystrokeEmitter.deleteSelection()
            }
            let suffix = String(revisedChars[common...])
            if !suffix.isEmpty {
                _ = KeystrokeEmitter.typeText(suffix)
            }
            lastEmittedPartial = revised
            return true
        case .appendNewSegment(let separator, let segment):
            let delta = separator + segment
            guard KeystrokeEmitter.typeText(delta) else { return false }
            lastEmittedPartial = lastEmittedPartial + delta
            return true
        }
    }

    /// Characters this session owns at the caret — field value minus the prefix
    /// captured at pin time. Nil when the field was edited externally or unreadable.
    private func dictatedFieldCharacterBudget() -> Int? {
        guard let element = pinnedElement, let full = readValue(from: element) else { return nil }
        guard full.hasPrefix(prefixBeforeSession) else { return nil }
        return full.count - prefixBeforeSession.count
    }

    private func selectAndReplace(raw: String, injectedLength: Int, polished: String) -> Bool {
        if SecureInputChecker.isActive() { return false }
        guard let budget = dictatedFieldCharacterBudget(), budget > 0 else { return false }
        return KeystrokeEmitter.selectAndReplace(
            raw: raw,
            injectedLength: injectedLength,
            polished: polished,
            maxBackwardUnits: budget
        )
    }

    /// AX sync writes the full field; keep tail tracking so keystroke fallback only types deltas.
    @discardableResult
    private func syncFullValue(_ full: String) -> Bool {
        guard writeFullValue(full) else { return false }
        lastDisplayed = full
        lastEmittedPartial = livePartial
        keystrokeModeActive = false
        return true
    }

    @discardableResult
    private func writeFullValue(_ full: String) -> Bool {
        guard let element = pinnedElement else { return false }
        if SecureInputChecker.isActive() { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            full as CFTypeRef
        ) == .success
    }

    private func readValue(from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success else { return nil }
        return valueRef as? String
    }

    private func queryFocusedElement() -> AXUIElement? {
        AXFocusResolver.focusedTextElement()
    }
}
