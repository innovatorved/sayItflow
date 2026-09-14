import XCTest
import os
@testable import SayItFlow

final class AudioInputLifecycleTests: XCTestCase {
    func testStopOnFreshInstanceIsIdempotent() {
        let input = AudioInput()
        input.stop()
        input.stop()
    }

    func testDeinitAfterStopDoesNotCrash() {
        var input: AudioInput? = AudioInput()
        input?.stop()
        input = nil
    }

    func testBeginStreamingWithoutDeviceFailsCleanly() async {
        let input = AudioInput()
        do {
            try await input.beginStreaming()
        } catch let error as AudioInputError {
            switch error {
            case .noInputDevice, .microphonePermissionMissing, .engineStartFailed:
                break
            case .busy:
                XCTFail("Unexpected busy on fresh instance")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        input.stop()
    }

    func testDoubleBeginStreamingDoesNotCrash() async {
        let input = AudioInput()
        do {
            try await input.beginStreaming()
            try await input.beginStreaming()
        } catch let error as AudioInputError {
            switch error {
            case .noInputDevice, .microphonePermissionMissing, .engineStartFailed, .busy:
                break
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        input.stop()
    }

    func testStopDuringArmingIsSafe() async {
        let input = AudioInput()
        let beginTask = Task { try? await input.beginStreaming() }
        try? await Task.sleep(for: .milliseconds(10))
        input.stop()
        _ = await beginTask.value
        input.stop()
    }

    func testTeardownWithActiveContinuationDoesNotDeadlock() async {
        let input = AudioInput()
        _ = input.bufferStream
        let beginTask = Task { try? await input.beginStreaming() }
        try? await Task.sleep(for: .milliseconds(50))

        let stopCompleted = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                input.stop()
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        _ = await beginTask.value
        input.stop()
        XCTAssertTrue(stopCompleted, "stop() should complete without deadlocking")
    }

    func testConfigurationChangeWithinGracePeriodDoesNotNotifyCoordinator() async {
        let input = AudioInput()
        final class Counter: @unchecked Sendable {
            private let lock = OSAllocatedUnfairLock(initialState: 0)
            var value: Int { lock.withLock { $0 } }
            func increment() { lock.withLock { $0 += 1 } }
        }
        let counter = Counter()
        input.onConfigurationChange = { counter.increment() }

        do {
            try await input.beginStreaming()
        } catch {
            input.stop()
            return
        }

        NotificationCenter.default.post(
            name: .AVAudioEngineConfigurationChange,
            object: input.configurationChangeNotificationObject
        )
        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(counter.value, 0)
        input.stop()

        do {
            try await input.beginStreaming()
        } catch let error as AudioInputError {
            if case .busy = error {
                XCTFail("Second beginStreaming should not fail with busy after config change")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        input.stop()
    }

    /// The regression that shipped: a configuration change from an output route swap or a
    /// sample-rate nudge — same microphone, engine still running — used to end the session
    /// and leave a stale engine that then reported "no input device".
    func testSameDeviceConfigurationChangeIsIgnoredWhileCapturing() {
        XCTAssertEqual(
            AudioRouteChangeLogic.action(
                deviceChanged: false,
                isStreaming: true,
                engineRunning: true,
                withinGracePeriod: false
            ),
            .ignore
        )
    }

    func testSameDeviceWithDeadEngineRestartsInsteadOfStopping() {
        XCTAssertEqual(
            AudioRouteChangeLogic.action(
                deviceChanged: false,
                isStreaming: true,
                engineRunning: false,
                withinGracePeriod: false
            ),
            .restartEngine
        )
        XCTAssertEqual(
            AudioRouteChangeLogic.action(
                deviceChanged: false,
                isStreaming: true,
                engineRunning: false,
                withinGracePeriod: true
            ),
            .waitForGrace
        )
    }

    /// A real microphone swap mid-hold rebuilds capture; it never ignores the change, even
    /// though the engine still reports itself as running on the departed device.
    func testChangedDeviceReseatsCapture() {
        XCTAssertEqual(
            AudioRouteChangeLogic.action(
                deviceChanged: true,
                isStreaming: true,
                engineRunning: true,
                withinGracePeriod: true
            ),
            .reseat
        )
    }

    func testConfigurationChangeWhileIdleJustResets() {
        for deviceChanged in [true, false] {
            XCTAssertEqual(
                AudioRouteChangeLogic.action(
                    deviceChanged: deviceChanged,
                    isStreaming: false,
                    engineRunning: false,
                    withinGracePeriod: false
                ),
                .resetIdle
            )
        }
    }

    /// The regression that shipped: any configuration change past the grace period ended
    /// the session, so plugging in headphones (an output change, same microphone) killed
    /// dictation and left a stale engine behind that then reported "no input device".
    func testConfigurationChangeWithSameDeviceKeepsStreaming() async throws {
        let input = AudioInput()
        final class Flag: @unchecked Sendable {
            private let lock = OSAllocatedUnfairLock(initialState: false)
            var value: Bool { lock.withLock { $0 } }
            func set() { lock.withLock { $0 = true } }
        }
        let stopped = Flag()
        let streamEnded = Flag()
        input.onConfigurationChange = { stopped.set() }

        let stream = input.bufferStream
        let consumer = Task {
            for await _ in stream {}
            streamEnded.set()
        }

        do {
            try await input.beginStreaming()
        } catch {
            consumer.cancel()
            input.stop()
            throw XCTSkip("No usable input device in this environment")
        }

        // Past the start-up grace period, where the old code went straight to hard reset.
        try? await Task.sleep(for: .milliseconds(1700))
        XCTAssertTrue(input.isCapturingForTesting, "Should still be capturing before the config change")

        NotificationCenter.default.post(
            name: .AVAudioEngineConfigurationChange,
            object: input.configurationChangeNotificationObject
        )
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(stopped.value, "Unchanged input device must not stop the session")
        XCTAssertFalse(streamEnded.value, "Buffer stream must survive a configuration change")
        XCTAssertTrue(input.isCapturingForTesting, "Capture must continue after a configuration change")

        consumer.cancel()
        input.stop()
    }

    /// A stale engine (one built before Microphone was granted) is only recoverable by
    /// replacing it. Verify the swap re-registers the config observer and reinstalls the
    /// tap, so streaming still works afterwards.
    func testStreamingRecoversAfterEngineRebuild() async throws {
        let input = AudioInput()
        _ = input.bufferStream
        do {
            try await input.beginStreaming()
        } catch {
            input.stop()
            throw XCTSkip("No usable input device in this environment")
        }
        try? await Task.sleep(for: .milliseconds(100))

        input.rebuildEngineForTesting()

        do {
            try await input.beginStreaming()
        } catch {
            XCTFail("beginStreaming should recover after an engine rebuild: \(error)")
            input.stop()
            return
        }
        try? await Task.sleep(for: .milliseconds(100))

        NotificationCenter.default.post(
            name: .AVAudioEngineConfigurationChange,
            object: input.configurationChangeNotificationObject
        )
        try? await Task.sleep(for: .milliseconds(100))
        input.stop()
    }

    func testBufferStreamAttachedBeforeBeginStreamingReceivesAudio() async {
        let input = AudioInput()
        _ = input.bufferStream
        do {
            try await input.beginStreaming()
        } catch {
            input.stop()
            return
        }
        try? await Task.sleep(for: .milliseconds(100))
        input.stop()
    }
}
