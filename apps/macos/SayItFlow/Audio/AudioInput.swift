import Accelerate
@preconcurrency import AVFoundation
import CoreAudio
import CoreMedia
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

/// Input-only push-to-talk audio capture backed by `AVCaptureSession`.
///
/// Uses `AVCaptureSession` + `AVCaptureAudioDataOutput` instead of `AVAudioEngine`
/// because `AVAudioEngine` creates a full-duplex `CADefaultDeviceAggregate` that opens
/// the default output speaker (and keeps it running even after `engine.stop()` / `reset()`),
/// causing macOS audio ducking and Bluetooth HFP volume drops on built-in and external speakers.
///
/// The capture session is created on `beginStreaming()` and completely torn down and released
/// on `stop()`, so zero audio hardware is held open while idle.
final class AudioInput: @unchecked Sendable {
    private enum CapturePhase { case idle, streaming }

    private struct State: @unchecked Sendable {
        var continuation: AsyncStream<SendablePCMBuffer>.Continuation?
        var phase: CapturePhase = .idle
        var ringBuffers: [SendablePCMBuffer] = []
        var latestPeakLevel: Float = 0
    }

    private final class CaptureSampleDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
        weak var owner: AudioInput?

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            owner?.handleSampleBuffer(sampleBuffer)
        }
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let operationQueue = DispatchQueue(label: "com.innovatorved.sayitflow.audio.ops")
    private let sampleQueue = DispatchQueue(label: "com.innovatorved.sayitflow.audio.samples", qos: .userInteractive)
    private let sampleDelegate = CaptureSampleDelegate()
    private let notificationToken = NSObject()

    /// All capture-session state is mutated exclusively on `operationQueue`.
    private var captureSession: AVCaptureSession?
    private var captureOutput: AVCaptureAudioDataOutput?
    private var captureDevice: AVCaptureDevice?
    private var sessionErrorObserver: NSObjectProtocol?
    private var deviceDisconnectObserver: NSObjectProtocol?
    private var configObserver: NSObjectProtocol?
    private var halListenerBlock: AudioObjectPropertyListenerBlock?

    private var isMutating = false
    private var isTearingDown = false
    private var pendingGraceRecovery: DispatchWorkItem?
    private var lastEngineStartTime: CFAbsoluteTime = 0
    private var lastInputDeviceID: AudioDeviceID?

    private static let configChangeGracePeriod: CFTimeInterval = 1.5
    private static let graceRecoveryDelay: TimeInterval = 0.25
    /// HAL can briefly report no capture device right after a hardware/Bluetooth swap.
    private static let deviceSettleAttempts = 15
    private let ringCapacity = 8

    internal var configurationChangeNotificationObject: AnyObject { notificationToken }

    #if DEBUG
    /// Exercises the dead-session recovery path without needing to revoke TCC.
    internal func rebuildEngineForTesting() {
        operationQueue.sync { teardownSessionOnQueue() }
    }

    internal var isCapturingForTesting: Bool {
        operationQueue.sync {
            let streaming = lock.withLock { $0.phase == .streaming }
            return streaming && (captureSession?.isRunning == true || pendingGraceRecovery != nil)
        }
    }
    #endif

    var onConfigurationChange: (@Sendable () -> Void)?
    /// Sample rate may change; downstream recognition must restart.
    var onInputDeviceChanged: (@Sendable () -> Void)?
    /// Direct zero-copy buffer callback invoked synchronously on the audio sample queue while streaming.
    /// Guarantees every captured sample up to `stop()` is delivered with zero AsyncStream scheduling lag.
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    var peakLevel: Float { lock.withLock { $0.latestPeakLevel } }

    init() {
        sampleDelegate.owner = self
        installConfigObserver()
        installDefaultInputDeviceListener()
    }

    deinit {
        removeDefaultInputDeviceListener()
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        operationQueue.sync { hardResetOnQueue() }
    }

    private func installConfigObserver() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: notificationToken,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func installDefaultInputDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleConfigurationChange()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            operationQueue,
            block
        )
        if status == noErr {
            halListenerBlock = block
        }
    }

    private func removeDefaultInputDeviceListener() {
        guard let block = halListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            operationQueue,
            block
        )
        halListenerBlock = nil
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

        if lock.withLock({ $0.phase == .streaming }), captureSession?.isRunning == true {
            logPhase("beginStreaming skipped — already streaming")
            return
        }

        if lock.withLock({ $0.phase == .streaming }), captureSession?.isRunning != true {
            logPhase("beginStreaming — recovering dead session")
            try startFreshSessionOnQueue()
            activateStreamingPhaseOnQueue()
            return
        }

        try startFreshSessionOnQueue()
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
        let directCallback = onBuffer
        for wrapped in pending {
            if let directCallback {
                directCallback(wrapped.buffer)
            } else {
                deliver(wrapped)
            }
        }
    }

    private func startFreshSessionOnQueue() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioInputError.microphonePermissionMissing
        }

        teardownSessionOnQueue()

        let device = try resolveInputDeviceOnQueue()
        let session = AVCaptureSession()
        session.beginConfiguration()

        let deviceInput: AVCaptureDeviceInput
        do {
            deviceInput = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            throw AudioInputError.engineStartFailed("Could not open microphone: \(error.localizedDescription)")
        }

        guard session.canAddInput(deviceInput) else {
            session.commitConfiguration()
            throw AudioInputError.engineStartFailed("Cannot attach audio input device")
        }
        session.addInput(deviceInput)

        let dataOutput = AVCaptureAudioDataOutput()
        dataOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true,
            AVNumberOfChannelsKey: 1,
        ]
        dataOutput.setSampleBufferDelegate(sampleDelegate, queue: sampleQueue)

        guard session.canAddOutput(dataOutput) else {
            session.commitConfiguration()
            throw AudioInputError.engineStartFailed("Cannot attach audio data output")
        }
        session.addOutput(dataOutput)
        session.commitConfiguration()

        installSessionObserversOnQueue(session: session, device: device)

        captureSession = session
        captureOutput = dataOutput
        captureDevice = device

        session.startRunning()
        guard session.isRunning else {
            teardownSessionOnQueue()
            throw AudioInputError.engineStartFailed("Audio capture session failed to start")
        }
        noteSessionStartedOnQueue()
    }

    private func resolveInputDeviceOnQueue() throws -> AVCaptureDevice {
        for attempt in 0..<Self.deviceSettleAttempts {
            if Self.defaultInputDeviceID() != nil,
               let device = AVCaptureDevice.default(for: .audio),
               device.isConnected {
                return device
            }
            if attempt + 1 < Self.deviceSettleAttempts {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        logPhase("no default input device")
        throw AudioInputError.noInputDevice
    }

    private func installSessionObserversOnQueue(session: AVCaptureSession, device: AVCaptureDevice) {
        removeSessionObserversOnQueue()
        sessionErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
        deviceDisconnectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: device,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func removeSessionObserversOnQueue() {
        if let sessionErrorObserver {
            NotificationCenter.default.removeObserver(sessionErrorObserver)
            self.sessionErrorObserver = nil
        }
        if let deviceDisconnectObserver {
            NotificationCenter.default.removeObserver(deviceDisconnectObserver)
            self.deviceDisconnectObserver = nil
        }
    }

    private func teardownSessionOnQueue() {
        removeSessionObserversOnQueue()
        captureOutput?.setSampleBufferDelegate(nil, queue: nil)
        if let session = captureSession {
            if session.isRunning {
                session.stopRunning()
            }
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            session.commitConfiguration()
        }
        captureSession = nil
        captureOutput = nil
        captureDevice = nil
    }

    private func cancelPendingGraceRecovery() {
        pendingGraceRecovery?.cancel()
        pendingGraceRecovery = nil
    }

    private func noteSessionStartedOnQueue() {
        lastEngineStartTime = CFAbsoluteTimeGetCurrent()
        lastInputDeviceID = Self.defaultInputDeviceID()
    }

    /// Route/runtime-change handler. Output-only changes never disrupt input-only capture.
    private func handleConfigurationChange() {
        operationQueue.async { [weak self] in
            guard let self else { return }
            let isStreaming = self.lock.withLock { $0.phase == .streaming }
            let elapsed = CFAbsoluteTimeGetCurrent() - self.lastEngineStartTime
            let sessionRunning = self.captureSession?.isRunning == true
            let action = AudioRouteChangeLogic.action(
                deviceChanged: Self.defaultInputDeviceID() != self.lastInputDeviceID,
                isStreaming: isStreaming,
                engineRunning: sessionRunning,
                withinGracePeriod: self.lastEngineStartTime > 0
                    && elapsed < Self.configChangeGracePeriod
            )

            switch action {
            case .ignore:
                self.logPhase("config change ignored — same input device")
                return
            case .resetIdle:
                self.cancelPendingGraceRecovery()
                if self.captureSession != nil {
                    self.logPhase("config change while idle — teardown")
                    self.teardownSessionOnQueue()
                }
                return
            case .waitForGrace:
                self.scheduleGracePeriodRecoveryOnQueue(elapsed: elapsed)
                return
            case .restartEngine:
                self.cancelPendingGraceRecovery()
                if self.reseatCaptureOnQueue() {
                    self.logPhase("session restarted after config change — same device")
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

    /// Reseat capture on the current default input device; keep phase and stream continuation alive.
    private func reseatCaptureOnQueue() -> Bool {
        do {
            try startFreshSessionOnQueue()
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
        if reseatCaptureOnQueue() {
            logPhase("session recovered after config change")
            onInputDeviceChanged?()
            return
        }
        let wasStreaming = lock.withLock { $0.phase == .streaming }
        logPhase("grace-period recovery failed — hard reset")
        hardResetOnQueue()
        if wasStreaming { onConfigurationChange?() }
    }

    private func stopCaptureOnQueue() {
        guard !isTearingDown else { return }
        cancelPendingGraceRecovery()
        lock.withLock { state in
            state.phase = .idle
            state.ringBuffers.removeAll()
            state.latestPeakLevel = 0
        }
        logPhase("stopCapture")
        teardownSessionOnQueue()
    }

    private func hardResetOnQueue() {
        cancelPendingGraceRecovery()
        isTearingDown = true
        defer { isTearingDown = false }
        lock.withLock { state in
            state.phase = .idle
            state.ringBuffers.removeAll()
            state.latestPeakLevel = 0
        }
        logPhase("hardReset")
        finishContinuationOnQueue()
        teardownSessionOnQueue()
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
        let running = captureSession?.isRunning == true
        let hasSession = captureSession != nil
        let snapshot = lock.withLock { state -> String in
            "phase=\(state.phase) sessionActive=\(hasSession) running=\(running)"
        }
        SessionTrace.log("\(message) (\(snapshot))", category: "audio")
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let isStreaming = lock.withLock { $0.phase == .streaming }
        guard isStreaming else { return }
        guard let pcmBuffer = makePCMBuffer(from: sampleBuffer) else { return }
        emit(buffer: pcmBuffer)
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer),
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }

        let asbd = asbdPtr.pointee
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0, asbd.mSampleRate > 0 else { return nil }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.mSampleRate,
            channels: 1,
            interleaved: false
        ), let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        guard let dst = pcmBuffer.floatChannelData?[0] else { return nil }

        var blockBuffer: CMBlockBuffer?
        var neededSize = 0
        let probeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &neededSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: nil
        )
        guard probeStatus == noErr, neededSize > 0 else { return nil }

        let rawList = UnsafeMutableRawPointer.allocate(
            byteCount: neededSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawList.deallocate() }
        let audioBufferListPtr = rawList.bindMemory(to: AudioBufferList.self, capacity: 1)

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPtr,
            bufferListSize: neededSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferListPtr)
        guard let firstBuffer = buffers.first, let srcData = firstBuffer.mData else { return nil }

        let isFloat32 = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && asbd.mBitsPerChannel == 32
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let channels = max(1, Int(asbd.mChannelsPerFrame))

        if isFloat32 {
            if isNonInterleaved || channels == 1 {
                let byteCount = min(Int(firstBuffer.mDataByteSize), frameCount * MemoryLayout<Float>.size)
                memcpy(dst, srcData, byteCount)
                return pcmBuffer
            } else {
                let src = srcData.assumingMemoryBound(to: Float.self)
                let availableFrames = min(frameCount, Int(firstBuffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
                for i in 0..<availableFrames {
                    dst[i] = src[i * channels]
                }
                pcmBuffer.frameLength = AVAudioFrameCount(availableFrames)
                return pcmBuffer
            }
        }

        let isInt16 = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0 && asbd.mBitsPerChannel == 16
        if isInt16 {
            let stride = isNonInterleaved ? 1 : channels
            let src = srcData.assumingMemoryBound(to: Int16.self)
            let availableFrames = min(frameCount, Int(firstBuffer.mDataByteSize) / (MemoryLayout<Int16>.size * stride))
            let scale: Float = 1.0 / 32768.0
            for i in 0..<availableFrames {
                dst[i] = Float(src[i * stride]) * scale
            }
            pcmBuffer.frameLength = AVAudioFrameCount(availableFrames)
            return pcmBuffer
        }

        return nil
    }

    private func emit(buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        let level = computePeakLevel(buffer)
        let (isStreaming, hasContinuation) = lock.withLock { state -> (Bool, Bool) in
            state.latestPeakLevel = level
            return (state.phase == .streaming, state.continuation != nil)
        }
        if let directCallback = onBuffer, isStreaming {
            directCallback(buffer)
            if !hasContinuation { return }
        }
        guard let copy = copyBuffer(buffer) else { return }
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

    /// Query HAL for default input device.
    internal static func defaultInputDeviceID() -> AudioDeviceID? {
        defaultAudioDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    /// Query HAL for default output device.
    internal static func defaultOutputDeviceID() -> AudioDeviceID? {
        defaultAudioDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    private static func defaultAudioDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        return status == noErr && id != AudioDeviceID(kAudioObjectUnknown) ? id : nil
    }

    internal static func isDeviceRunningSomewhere(_ id: AudioDeviceID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
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

/// Route-change handling for audio configuration changes.
enum AudioRouteChangeLogic {
    enum Action: Equatable {
        /// Same microphone, still capturing — the graph settled on its own.
        case ignore
        /// Same microphone, session died — restart capture on the same device.
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
