import Accelerate
import AVFoundation
import Foundation

/// Thread-safe PCM sample accumulator for push-to-talk dictation sessions.
///
/// Pre-allocates a 120-second mono buffer to avoid mid-speech allocations.
/// If the audio hardware changes sample rate mid-session (e.g. Bluetooth HFP
/// switching between 48 kHz and 16 kHz), segments are tracked separately and
/// resampled to 16 kHz on `drain()` so audio speed/pitch is never corrupted.
final class AudioSampleCollector: @unchecked Sendable {
    private struct Segment {
        var samples: [Float]
        let sampleRate: Double
    }

    private let lock = NSLock()
    private var segments: [Segment] = []
    private var activeSamples: [Float]
    private var activeSampleRate: Double = 0

    /// Target sample rate used when merging mixed-rate segments.
    static let targetMergeSampleRate: Double = 16_000.0
    /// Pre-allocated capacity (~120s at 16 kHz).
    private static let initialCapacity = 16_000 * 120
    /// Safety cap (~10 minutes at 48 kHz) to prevent unbounded memory growth.
    private static let maxTotalSamples = 48_000 * 600
    private var totalSampleCount = 0

    init() {
        var buffer = [Float]()
        buffer.reserveCapacity(Self.initialCapacity)
        self.activeSamples = buffer
    }

    func append(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let count = Int(buffer.frameLength)
        let rate = buffer.format.sampleRate
        guard rate > 0 else { return }
        append(samples: UnsafeBufferPointer(start: channelData, count: count), sampleRate: rate)
    }

    func append(samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty, sampleRate > 0 else { return }
        samples.withUnsafeBufferPointer { ptr in
            append(samples: ptr, sampleRate: sampleRate)
        }
    }

    private func append(samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard totalSampleCount < Self.maxTotalSamples else { return }
        let remaining = Self.maxTotalSamples - totalSampleCount
        let countToCopy = min(samples.count, remaining)
        guard countToCopy > 0 else { return }

        if activeSampleRate == 0 {
            activeSampleRate = sampleRate
        } else if abs(activeSampleRate - sampleRate) > 1.0 {
            // Hardware sample rate changed mid-recording — seal previous segment
            if !activeSamples.isEmpty {
                segments.append(Segment(samples: activeSamples, sampleRate: activeSampleRate))
                activeSamples = []
                activeSamples.reserveCapacity(16_000 * 15)
            }
            activeSampleRate = sampleRate
        }

        activeSamples.append(contentsOf: samples.prefix(countToCopy))
        totalSampleCount += countToCopy
    }

    func drain() -> (samples: [Float], sampleRate: Double) {
        lock.lock()
        let sealedSegments = segments
        let tailSamples = activeSamples
        let tailRate = activeSampleRate

        segments.removeAll(keepingCapacity: false)
        activeSamples.removeAll(keepingCapacity: true)
        activeSampleRate = 0
        totalSampleCount = 0
        lock.unlock()

        // Fast path: single consistent sample rate throughout the entire session (99.9% of cases)
        if sealedSegments.isEmpty {
            return (tailSamples, tailRate > 0 ? tailRate : Self.targetMergeSampleRate)
        }

        var allSegments = sealedSegments
        if !tailSamples.isEmpty, tailRate > 0 {
            allSegments.append(Segment(samples: tailSamples, sampleRate: tailRate))
        }

        let targetRate = Self.targetMergeSampleRate
        var merged = [Float]()
        let estimatedCount = allSegments.reduce(0) { acc, seg in
            acc + Int((Double(seg.samples.count) * targetRate / seg.sampleRate).rounded())
        }
        merged.reserveCapacity(estimatedCount)

        for seg in allSegments {
            if abs(seg.sampleRate - targetRate) <= 1.0 {
                merged.append(contentsOf: seg.samples)
            } else {
                merged.append(contentsOf: Self.resampleLinear(seg.samples, from: seg.sampleRate, to: targetRate))
            }
        }
        return (merged, targetRate)
    }

    func clear() {
        lock.lock()
        segments.removeAll(keepingCapacity: false)
        activeSamples.removeAll(keepingCapacity: true)
        activeSampleRate = 0
        totalSampleCount = 0
        lock.unlock()
    }

    /// Hardware-accelerated linear resampler using Accelerate/vDSP.
    static func resampleLinear(_ input: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !input.isEmpty, sourceRate > 0, targetRate > 0 else { return [] }
        if abs(sourceRate - targetRate) <= 1.0 { return input }

        let ratio = sourceRate / targetRate
        let outputCount = max(1, Int((Double(input.count) / ratio).rounded()))
        if input.count == 1 {
            return Array(repeating: input[0], count: outputCount)
        }

        var indices = [Float](repeating: 0, count: outputCount)
        let maxIndex = Float(input.count - 1)
        let step = Float(ratio)
        for i in 0..<outputCount {
            indices[i] = min(Float(i) * step, maxIndex)
        }

        var output = [Float](repeating: 0, count: outputCount)
        vDSP_vlint(input, &indices, 1, &output, 1, vDSP_Length(outputCount), vDSP_Length(input.count))
        return output
    }
}
