import XCTest
@testable import SayItFlow

final class HotkeyEngineStopTests: XCTestCase {
    func testStopOnMainThreadDoesNotTrap() {
        let engine = HotkeyEngine(handler: { _ in }, onTapFailed: { _ in })
        engine.start()
        engine.stop()
        engine.stop()
    }

    func testStopWithoutStartIsSafe() {
        let engine = HotkeyEngine(handler: { _ in }, onTapFailed: { _ in })
        engine.stop()
    }
}
