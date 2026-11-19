import XCTest
@testable import SayItFlow

final class AudioSampleCollectorTests: XCTestCase {
    func testHomogeneousSampleRateDrainsWithoutResampling() {
        let collector = AudioSampleCollector()
        let chunk1: [Float] = [0.1, 0.2, 0.3]
        let chunk2: [Float] = [0.4, 0.5]

        collector.append(samples: chunk1, sampleRate: 48_000)
        collector.append(samples: chunk2, sampleRate: 48_000)

        let drained = collector.drain()
        XCTAssertEqual(drained.sampleRate, 48_000)
        XCTAssertEqual(drained.samples, [0.1, 0.2, 0.3, 0.4, 0.5])

        // Second drain is empty
        let second = collector.drain()
        XCTAssertTrue(second.samples.isEmpty)
    }

    func testMixedSampleRateResamplesTo16kHzWithoutCorruptingDuration() {
        let collector = AudioSampleCollector()
        // 0.5 seconds at 48 kHz = 24,000 samples
        let seg1 = [Float](repeating: 0.5, count: 24_000)
        // 0.5 seconds at 16 kHz = 8,000 samples (e.g. Bluetooth HFP switch)
        let seg2 = [Float](repeating: -0.25, count: 8_000)

        collector.append(samples: seg1, sampleRate: 48_000)
        collector.append(samples: seg2, sampleRate: 16_000)

        let drained = collector.drain()
        XCTAssertEqual(drained.sampleRate, 16_000)
        // Total duration should be ~1.0 second at 16 kHz = 16,000 samples
        XCTAssertEqual(drained.samples.count, 16_000)
        XCTAssertEqual(drained.samples.first ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(drained.samples.last ?? 0, -0.25, accuracy: 0.01)
    }

    func testClearDiscardsAllSegments() {
        let collector = AudioSampleCollector()
        collector.append(samples: [0.1, 0.2], sampleRate: 48_000)
        collector.append(samples: [0.3, 0.4], sampleRate: 16_000)
        collector.clear()

        let drained = collector.drain()
        XCTAssertTrue(drained.samples.isEmpty)
    }
}
