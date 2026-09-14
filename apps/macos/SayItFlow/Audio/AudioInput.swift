import Accelerate
@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os

enum AudioInputError: Error, LocalizedError {
    case noInputDevice
    case microphonePermissionMissing
    case engineStartFailed(String)
    case busy

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone input device available"
        case .microphonePermissionMissing: "Microphone access is off — open SayItFlow and grant Microphone."
        case .engineStartFailed(let message): message
        case .busy: "Audio capture is busy"
        }
    }
}

struct SendablePCMBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// Push-to-talk capture. Tap persists across holds; engine start/stop per session.
final class AudioInput: @unchecked Sendable {
    private enum CapturePhase { case idle, streaming }

    private struct State: @unchecked Sendable {
        var continuation: AsyncStream<SendablePCMBuffer>.Continuation?
        var phase: CapturePhase = .idle
        var tapInstalled = false
        var ringBuffers: [SendablePCMBuffer] = []
        var latestPeakLevel: Float = 0
    }

    /// Rebuilt when the input device cache is stale. Mutated only on operationQueue.
    private var engine = AVAudioEngine()
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let operationQueue = DispatchQueue(label: "com.innovatorved.sayitflow.audio.ops")
    private var isMutating = false
    private var isTearingDown = false
    private var pendingGraceRecovery: DispatchWorkItem?
    private var lastEngineStartTime: CFAbsoluteTime = 0
    private var lastInputDeviceID: AudioDeviceID?
    /// Tap format at install time; reusing after a route change yields -10868.
    private var installedTapFormat: AVAudioFormat?
    private static let configChangeGracePeriod: CFTimeInterval = 1.5
    private static let graceRecoveryDelay: TimeInterval = 0.25
    /// HAL can report a zero format briefly after a device swap (~1.5s at 50ms polls).
    private static let settlePollAttempts = 30
    private static let tapInstallAttempts = 3
    private let ringCapacity = 8
    private var configObserver: NSObjectProtocol?

    internal var configurationChangeNotificationObject: AVAudioEngine { engine }

    #if DEBUG
    /// Exercises the stale-input-device recovery path without needing to revoke TCC.
    internal func rebuildEngineForTesting() {
        operationQueue.sync { rebuildEngineOnQueue() }
    }

    internal var isCapturingForTesting: Bool {
        operationQueue.sync { lock.withLock { $0.phase == .streaming } && engine.isRunning }
    }
    #endif
    var onConfigurationChange: (@Sendable () -> Void)?
    /// Sample rate may change; downstream recognition must restart.
    var onInputDeviceChanged: (@Sendable () -> Void)?

    var peakLevel: Float { lock.withLock { $0.latestPeakLevel } }

    init() {
        installConfigObserver()
    }

    private func installConfigObserver() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    deinit {
        operationQueue.sync { hardResetOnQueue() }
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    var bufferStream: AsyncStream<SendablePCMBuffer> {
        AsyncStream { continuation in
            let pending = lock.withLock { state -> [SendablePCMBuffer] in
                state.continuation?.finish()
                state.continuation = continuation
                guard state.phase == .streaming else { return [] }
                let pending = state.ringBuffers
                state.ringBuffers.removeAll()
                return pending
            }
            continuation.onTermination = { _ in }
            for wrapped in pending { continuation.yield(wrapped) }
        }
    }

    func beginStreaming() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operationQueue.async {
                do {
                    try self.beginStreamingOnQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        operationQueue.sync { stopCaptureOnQueue() }
    }

    private func beginStreamingOnQueue() throws {
        guard !isTearingDown else {
            throw AudioInputError.engineStartFailed("Audio capture is resetting")
        }
        guard !isMutating else { throw AudioInputError.busy }
        isMutating = true
        defer { isMutating = false }

        if lock.withLock({ $0.phase == .streaming }), engine.isRunning {
            logPhase("beginStreaming skipped — already streaming")
            return
        }

        if lock.withLock({ $0.phase == .streaming }), !engine.isRunning {
            logPhase("beginStreaming — recovering dead engine")
            try recoverEngineOnQueue()
            activateStreamingPhaseOnQueue()
            return
        }

        try ensureTapInstalledOnQueue()
        try startEngineOnQueue()
        activateStreamingPhaseOnQueue()
    }

    private func activateStreamingPhaseOnQueue() {
        let pending = lock.withLock { state -> [SendablePCMBuffer] in
            state.phase = .streaming
            state.latestPeakLevel = 0
            let pending = state.ringBuffers
            state.ringBuffers.removeAll()
            return pending
        }
        logPhase("beginStreaming active")
        for wrapped in pending { deliver(wrapped) }
    }

    private func removeTapOnQueue() {
        if lock.withLock({ $0.tapInstalled }) {
            SIFRemoveTapSafely(engine.inputNode, 0)
            lock.withLock { $0.tapInstalled = false }
        }
        installedTapFormat = nil
    }

    private func cancelPendingGraceRecovery() {
        pendingGraceRecovery?.cancel()
        pendingGraceRecovery = nil
    }

    @discardableResult
    private func tryLightweightEngineRestartOnQueue() -> Bool {
        guard lock.withLock({ $0.tapInstalled }), !engine.isRunning else {
            return engine.isRunning
        }
        // Format mismatch after route change — reinstall tap instead of lightweight restart.
        if let installedTapFormat, engine.inputNode.outputFormat(forBus: 0) != installedTapFormat {
            logPhase("skipping lightweight restart — input format no longer matches tap")
            return false
        }
        engine.prepare()
        do {
            try engine.start()
            noteEngineStartedOnQueue()
            return true
        } catch {
            logPhase("lightweight engine restart failed: \(error.localizedDescription)")
            return false
        }
    }

    private func recoverEngineOnQueue() throws {
        if tryLightweightEngineRestartOnQueue() { return }
        removeTapOnQueue()
        if engine.isRunning { engine.stop() }
        engine.reset()
        try ensureTapInstalledOnQueue()
        engine.prepare()
        try engine.start()
        noteEngineStartedOnQueue()
    }

    private func noteEngineStartedOnQueue() {
        lastEngineStartTime = CFAbsoluteTimeGetCurrent()
        lastInputDeviceID = Self.defaultInputDeviceID()
    }

    private func startEngineOnQueue() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
            noteEngineStartedOnQueue()
        } catch {
            logPhase("engine.start failed — recovering")
            try recoverEngineOnQueue()
        }
    }

    private func pollInputFormatOnQueue(attempts: Int = 20) -> AVAudioFormat? {
        for attempt in 0..<attempts {
            let format = engine.inputNode.outputFormat(forBus: 0)
            if isValidFormat(format) { return format }
            if attempt + 1 < attempts { Thread.sleep(forTimeInterval: 0.05) }
        }
        return nil
    }

    private func waitForValidInputFormatOnQueue() throws -> AVAudioFormat {
        guard Self.defaultInputDeviceID() != nil else {
            logPhase("no default input device")
            throw AudioInputError.noInputDevice
        }

        if let format = pollInputFormatOnQueue() { return format }

        // Stale engine caches a dead input device — rebuild once, then poll longer for HAL settle.
        logPhase("input format invalid — rebuilding engine once")
        rebuildEngineOnQueue()
        if let format = pollInputFormatOnQueue(attempts: Self.settlePollAttempts) { return format }
        throw AudioInputError.noInputDevice
    }

    private func rebuildEngineOnQueue() {
        if engine.isRunning { engine.stop() }
        SIFRemoveTapSafely(engine.inputNode, 0)
        lock.withLock { $0.tapInstalled = false }
        installedTapFormat = nil
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        engine = AVAudioEngine()
        installConfigObserver()
    }

    private func ensureTapInstalledOnQueue() throws {
        if lock.withLock({ $0.tapInstalled }) { return }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioInputError.microphonePermissionMissing
        }

        for attempt in 0..<Self.tapInstallAttempts {
            // Resolve format here — waitForValidInputFormat may replace the engine.
            let format = try waitForValidInputFormatOnQueue()
            let input = engine.inputNode
            SIFRemoveTapSafely(input, 0)
            if SIFInstallTapSafely(input, 0, 4096, format, { [weak self] buffer, _ in
                self?.emit(buffer: buffer)
            }) {
                installedTapFormat = format
                lock.withLock { $0.tapInstalled = true }
                logPhase("installTap once")
                return
            }
            logPhase("installTap rejected by engine (attempt \(attempt + 1))")
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw AudioInputError.noInputDevice
    }

    /// Config-change fires for output route swaps too — only rebuild when the input device changes.
    private func handleConfigurationChange() {
        operationQueue.async { [weak self] in
            guard let self else { return }
            let isStreaming = self.lock.withLock { $0.phase == .streaming }
            let elapsed = CFAbsoluteTimeGetCurrent() - self.lastEngineStartTime
            let action = AudioRouteChangeLogic.action(
                deviceChanged: Self.defaultInputDeviceID() != self.lastInputDeviceID,
                isStreaming: isStreaming,
                engineRunning: self.engine.isRunning,
                withinGracePeriod: self.lastEngineStartTime > 0
                    && elapsed < Self.configChangeGracePeriod
            )

            switch action {
            case .ignore:
                self.logPhase("config change ignored — same input device")
                return
            case .resetIdle:
                self.cancelPendingGraceRecovery()
                self.logPhase("config change while idle — reset")
                self.resetIdleEngineOnQueue()
                return
            case .waitForGrace:
                self.scheduleGracePeriodRecoveryOnQueue(elapsed: elapsed)
                return
            case .restartEngine:
                self.cancelPendingGraceRecovery()
                if self.tryLightweightEngineRestartOnQueue() {
                    self.logPhase("engine restarted after config change — same device")
                    return
                }
            case .reseat:
                self.cancelPendingGraceRecovery()
            }

            SessionTrace.log("audio input device changed — reseating capture", category: "audio")
            if self.reseatCaptureOnQueue() {
                self.logPhase("capture reseated on new input device")
                self.onInputDeviceChanged?()
                return
            }

            self.logPhase("input device lost — hard reset")
            SessionTrace.log("microphone disconnected — stopping session", category: "audio")
            self.hardResetOnQueue()
            self.onConfigurationChange?()
        }
    }

    private func resetIdleEngineOnQueue() {
        if engine.isRunning { engine.stop() }
        engine.reset()
        removeTapOnQueue()
    }

    /// Reseat capture on a new default input device; keep phase and stream continuation alive.
    private func reseatCaptureOnQueue() -> Bool {
        rebuildEngineOnQueue()
        do {
            try ensureTapInstalledOnQueue()
            engine.prepare()
            try engine.start()
            noteEngineStartedOnQueue()
            return true
        } catch {
            logPhase("reseat failed: \(error.localizedDescription)")
            return false
        }
    }

    private func scheduleGracePeriodRecoveryOnQueue(elapsed: CFTimeInterval) {
        cancelPendingGraceRecovery()
        logPhase("config change — scheduling recovery (grace \(String(format: "%.2f", elapsed))s)")
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingGraceRecovery = nil
            self.performGracePeriodRecoveryOnQueue()
        }
        pendingGraceRecovery = work
        operationQueue.asyncAfter(deadline: .now() + Self.graceRecoveryDelay, execute: work)
    }

    private func performGracePeriodRecoveryOnQueue() {
        guard lock.withLock({ $0.phase == .streaming }) else { return }
        do {
            try recoverEngineOnQueue()
            logPhase("engine recovered after config change")
        } catch {
            if reseatCaptureOnQueue() {
                logPhase("capture reseated after grace-period recovery failed")
                onInputDeviceChanged?()
                return
            }
            let wasStreaming = lock.withLock { $0.phase == .streaming }
            logPhase("grace-period recovery failed — hard reset")
            hardResetOnQueue()
            if wasStreaming { onConfigurationChange?() }
        }
    }

    private func stopCaptureOnQueue() {
        guard !isTearingDown else { return }
        cancelPendingGraceRecovery()
        logPhase("stopCapture")
        if engine.isRunning { engine.stop() }
        lock.withLock { state in
            state.phase = .idle
            state.ringBuffers.removeAll()
            state.latestPeakLevel = 0
        }
    }

    private func hardResetOnQueue() {
        cancelPendingGraceRecovery()
        isTearingDown = true
        defer { isTearingDown = false }
        logPhase("hardReset")
        finishContinuationOnQueue()
        removeTapOnQueue()
        if engine.isRunning { engine.stop() }
        engine.reset()
        lock.withLock { state in
            state.phase = .idle
            state.ringBuffers.removeAll()
            state.latestPeakLevel = 0
        }
    }

    private func finishContinuationOnQueue() {
        let continuation = lock.withLock { state -> AsyncStream<SendablePCMBuffer>.Continuation? in
            let current = state.continuation
            state.continuation = nil
            return current
        }
        continuation?.finish()
    }

    private func logPhase(_ message: String) {
        let snapshot = lock.withLock { state -> String in
            "phase=\(state.phase) tapInstalled=\(state.tapInstalled) engineRunning=\(engine.isRunning)"
        }
        SessionTrace.log("\(message) (\(snapshot))", category: "audio")
    }

    private func emit(buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        let level = computePeakLevel(buffer)
        guard let copy = copyBuffer(buffer) else { return }
        lock.withLock { $0.latestPeakLevel = level }
        deliver(SendablePCMBuffer(buffer: copy))
    }

    private func computePeakLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
        return min(max(rms * 4, 0), 1)
    }

    private func deliver(_ wrapped: SendablePCMBuffer) {
        let action = lock.withLock { state -> (AsyncStream<SendablePCMBuffer>.Continuation?, Bool) in
            if let continuation = state.continuation, state.phase == .streaming {
                return (continuation, true)
            }
            if state.ringBuffers.count < ringCapacity {
                state.ringBuffers.append(wrapped)
            } else if !state.ringBuffers.isEmpty {
                state.ringBuffers.removeFirst()
                state.ringBuffers.append(wrapped)
            }
            return (nil, false)
        }
        if let continuation = action.0, action.1 { continuation.yield(wrapped) }
    }

    /// Query HAL for default input device — AVAudioEngine caches its own and lies after route changes.
    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        return status == noErr && id != AudioDeviceID(kAudioObjectUnknown) ? id : nil
    }

    private func isValidFormat(_ format: AVAudioFormat) -> Bool {
        format.channelCount > 0 && format.sampleRate > 0
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        guard let src = buffer.floatChannelData?[0], let dst = copy.floatChannelData?[0] else { return nil }
        memcpy(dst, src, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        return copy
    }
}

/// Route-change handling for AVAudioEngineConfigurationChange.
enum AudioRouteChangeLogic {
    enum Action: Equatable {
        /// Same microphone, still capturing — the graph settled on its own.
        case ignore
        /// Same microphone, engine died — a plain restart keeps the existing tap.
        case restartEngine
        /// Too soon after a start to tell churn from a real failure; retry shortly.
        case waitForGrace
        /// The microphone moved mid-hold — rebuild capture onto the new device.
        case reseat
        case resetIdle
    }

    static func action(
        deviceChanged: Bool,
        isStreaming: Bool,
        engineRunning: Bool,
        withinGracePeriod: Bool
    ) -> Action {
        guard isStreaming else { return .resetIdle }
        if deviceChanged { return .reseat }
        if engineRunning { return .ignore }
        return withinGracePeriod ? .waitForGrace : .restartEngine
    }
}
