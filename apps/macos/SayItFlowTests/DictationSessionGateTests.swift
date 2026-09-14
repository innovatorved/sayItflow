import XCTest
@testable import SayItFlow

final class DictationSessionGateTests: XCTestCase {
    func testBeginIncrementsSessionID() {
        var gate = DictationSessionGate()
        let first = gate.begin()
        let second = gate.begin()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
    }

    func testInvalidateMakesPriorSessionStale() {
        var gate = DictationSessionGate()
        let id = gate.begin()
        XCTAssertTrue(gate.isValid(id, cancelled: false))
        gate.invalidate()
        XCTAssertFalse(gate.isValid(id, cancelled: false))
    }

    func testCancellationInvalidatesSession() {
        var gate = DictationSessionGate()
        let id = gate.begin()
        XCTAssertFalse(gate.isValid(id, cancelled: true))
    }

    /// Why `DictationCoordinator.isSessionActive` has to include `isProcessingRelease`.
    ///
    /// Recording stops at the head of the release tail (finish → polish → inject), but
    /// the tail keeps running against session `id`. If a second hotkey press is accepted
    /// during that window it calls `begin()`, which invalidates `id` — the in-flight tail
    /// then fails every `isSessionValid` guard and bails out without cleaning up, leaving
    /// a stranded HUD and a live sink. Refusing the press is what keeps `id` valid.
    func testPressDuringReleaseTailWouldInvalidateTheInFlightSession() {
        var gate = DictationSessionGate()
        let inFlight = gate.begin()
        XCTAssertTrue(gate.isValid(inFlight, cancelled: false), "tail should still own the session")

        _ = gate.begin()
        XCTAssertFalse(
            gate.isValid(inFlight, cancelled: false),
            "accepting a press mid-tail strands the in-flight release work"
        )
    }

    func testTailStaysValidWhenNoNewSessionBegins() {
        var gate = DictationSessionGate()
        let inFlight = gate.begin()
        XCTAssertTrue(gate.isValid(inFlight, cancelled: false))
        XCTAssertTrue(gate.isValid(inFlight, cancelled: false))
    }
}
