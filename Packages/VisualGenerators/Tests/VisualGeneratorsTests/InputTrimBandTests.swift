// InputTrimBandTests.swift — AUD-008-S3, R3: the trim moves a test tone's band predictably and the
// oscilloscope's history shows the trimmed samples.
import AudioCore
import VisualBandFeed
import VisualGenerators
import XCTest

final class InputTrimBandTests: XCTestCase {
    /// Bands of `samples` read through a trim of `decibels` (nil: the raw tap).
    private func bands(_ samples: [Float], decibels: Float?) throws -> [Float] {
        let feed = try SpectrumBandFeed(barCount: .b32)
        let raw = ArrayPCMReader(samples)
        let produced: Bool
        if let decibels {
            produced = feed.pull(from: InputTrimReader(raw, control: InputTrimControl(decibels: decibels)))
        } else {
            produced = feed.pull(from: raw)
        }
        XCTAssertTrue(produced)
        return Array(feed.bands)
    }

    func testToneBandMovesByTrimOverTheFloor() throws {
        // −40 dBFS 1 kHz sine: below the knee at every trim tested, and its band stays inside 0…1.
        let sine = try BandFeedFixture.sine(1_000, amplitude: 0.01, seconds: 0.25)
        let reference = try bands(sine, decibels: 0)
        let raw = try bands(sine, decibels: nil)
        XCTAssertEqual(reference, raw, "0 dB: bands identical to the raw tap's")
        let peak = reference.indices.max { (a: Int, b: Int) -> Bool in reference[a] < reference[b] }!
        XCTAssertGreaterThan(reference[peak], 0.2)
        XCTAssertLessThan(reference[peak], 0.85)
        let floor: Float = -SpectrumBandFeed.floorDecibels   // 80
        for trim: Float in [-12, 6] {
            let moved = try bands(sine, decibels: trim)
            let expected: Float = reference[peak] + trim / floor
            XCTAssertEqual(moved[peak], expected, accuracy: 0.005, "band at \(trim) dB")
        }
    }

    func testOscilloscopeHistoryShowsTrimmedSamples() throws {
        // AUD-008-R3: the trim sits in front of WaveformTap, so +6.0206 dB doubles the mid history.
        let sine = try BandFeedFixture.sine(440, amplitude: 0.1, seconds: 0.1)
        let raw = WaveformTap(ArrayPCMReader(sine))
        let trimmed = WaveformTap(InputTrimReader(ArrayPCMReader(sine), control: InputTrimControl(decibels: 6.0206)))
        var scratch = [Float](repeating: 0, count: 2 * 8_192)
        for tap in [raw, trimmed] {
            _ = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                tap.read(into: b.baseAddress!, maxFrames: 8_192)
            }
        }
        let n = WaveformFrameBuffer.capacity
        var a = [Float](repeating: 0, count: n)
        var b = [Float](repeating: 0, count: n)
        _ = a.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<Float>) -> UInt64? in raw.output.readLatest(into: p.baseAddress!, capacity: n) }
        _ = b.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<Float>) -> UInt64? in trimmed.output.readLatest(into: p.baseAddress!, capacity: n) }
        for i in stride(from: 0, to: n, by: 97) {
            let doubled: Float = 2 * a[i]
            XCTAssertEqual(b[i], doubled, accuracy: 1e-3, "sample \(i)")
        }
    }
}
