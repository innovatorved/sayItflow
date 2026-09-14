import XCTest
@testable import SayItFlow

/// `typeText` used to emit one event per Unicode *scalar* via `UniChar(scalar.value)`,
/// which truncated non-BMP characters and split combining sequences. It also made the
/// emitted event count disagree with `String.count`, which is the number handed to
/// `selectBackward(characterCount:)` when replacing typed text — so polish rewrites
/// under-selected and ate neighbouring characters.
@MainActor
final class KeystrokeEmitterTests: XCTestCase {
    func testEmittedUnitCountMatchesCharacterCount() {
        let samples = [
            "hello world",
            "cafe\u{301}",          // combining acute accent
            "family: \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",
            "emoji \u{1F600} tail",
            "\u{1F1EE}\u{1F1F3} flag",
        ]

        for sample in samples {
            XCTAssertEqual(
                KeystrokeEmitter.graphemeUnits(for: sample).count,
                sample.count,
                "unit count diverged from String.count for \(sample.debugDescription)"
            )
        }
    }

    func testUnitsReassembleIntoOriginalText() {
        let text = "Caf\u{65}\u{301} \u{1F600} done"
        let rebuilt = KeystrokeEmitter.graphemeUnits(for: text)
            .map { String(utf16CodeUnits: $0, count: $0.count) }
            .joined()
        XCTAssertEqual(rebuilt, text)
    }

    func testNonBMPCharacterKeepsBothSurrogates() {
        let units = KeystrokeEmitter.graphemeUnits(for: "\u{1F600}")
        XCTAssertEqual(units.count, 1)
        // Truncating to a single UniChar was exactly the old bug.
        XCTAssertEqual(units.first?.count, 2)
    }

    func testEmptyTextProducesNoUnits() {
        XCTAssertTrue(KeystrokeEmitter.graphemeUnits(for: "").isEmpty)
    }

    func testClampedBackwardUnitsRejectsUnknownBudget() {
        XCTAssertEqual(KeystrokeEmitter.clampedBackwardUnits(requested: 50, budget: nil), 0)
        XCTAssertEqual(KeystrokeEmitter.clampedBackwardUnits(requested: 50, budget: 0), 0)
    }

    func testClampedBackwardUnitsNeverExceedsBudget() {
        XCTAssertEqual(KeystrokeEmitter.clampedBackwardUnits(requested: 200, budget: 42), 42)
        XCTAssertEqual(KeystrokeEmitter.clampedBackwardUnits(requested: 10, budget: 42), 10)
    }

    func testWordUnitsNeverExceedCharacterBudget() {
        let raw = "one two three four five six seven eight nine ten"
        XCTAssertLessThanOrEqual(
            KeystrokeEmitter.clampedWordUnits(raw: raw, budget: 3),
            3
        )
        XCTAssertEqual(
            KeystrokeEmitter.clampedWordUnits(raw: raw, budget: 0),
            0
        )
    }
}
