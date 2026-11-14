// ChannelSelectionBandTests.swift — AUD-009-S2, R3: a left-only fixture's tone band per mode, and the
// oscilloscope's history shows the selected signal.
import AudioCore
import VisualBandFeed
import VisualGenerators
import XCTest

final class ChannelSelectionBandTests: XCTestCase {
    /// A −40 dBFS 1 kHz sine on L, silence on R (its band stays inside 0…1 in every mode).
    private func leftOnly() throws -> [Float] {
        var samples = try BandFeedFixture.sine(1_000, amplitude: 0.01, seconds: 0.25)
        for i in stride(from: 1, to: samples.count, by: 2) { samples[i] = 0 }
        return samples
    }

    /// Bands of `samples` read through `mode` (nil: the raw tap).
    private func bands(_ samples: [Float], mode: AnalysisChannelMode?) throws -> [Float] {
        let feed = try SpectrumBandFeed(barCount: .b32)
        let raw = ArrayPCMReader(samples)
        let produced: Bool
        if let mode {
            produced = feed.pull(from: ChannelSelectionReader(raw, control: ChannelSelectionControl(mode: mode)))
        } else {
            produced = feed.pull(from: raw)
        }
        XCTAssertTrue(produced)
        return Array(feed.bands)
    }

    /// The roadmap acceptance in band units: the tone band relative to Left moves by dB/80.
    func testLeftOnlyFixtureBandPerMode() throws {
        let fixture = try leftOnly()
        let left = try bands(fixture, mode: .left)
        let peak = left.indices.max { (a: Int, b: Int) -> Bool in left[a] < left[b] }!
        XCTAssertGreaterThan(left[peak], 0.2)
        XCTAssertLessThan(left[peak], 0.85)
        let floor: Float = -SpectrumBandFeed.floorDecibels   // 80
        let expected: [(AnalysisChannelMode, Float)] = [(.mix, -6.0206), (.mid, -3.0103), (.side, -3.0103)]
        for (mode, decibels) in expected {
            let moved = try bands(fixture, mode: mode)
            let value: Float = left[peak] + decibels / floor
            XCTAssertEqual(moved[peak], value, accuracy: 0.005, "\(mode)")
        }
        let right = try bands(fixture, mode: .right)
        XCTAssertTrue(right.allSatisfy { (v: Float) -> Bool in v == 0 }, "Right lights no band: \(right)")
        XCTAssertEqual(try bands(fixture, mode: .mix), try bands(fixture, mode: nil), "Mix: bands identical to the raw tap's")
    }

    func testOscilloscopeHistoryShowsTheSelectedSignal() throws {
        let fixture = try BandFeedFixture.sine(440, amplitude: 0.1, seconds: 0.1).enumerated().map { (pair: (offset: Int, element: Float)) -> Float in
            pair.offset % 2 == 0 ? pair.element : 0
        }
        func history(_ mode: AnalysisChannelMode) -> [Float] {
            let tap = WaveformTap(ChannelSelectionReader(ArrayPCMReader(fixture), control: ChannelSelectionControl(mode: mode)))
            var scratch = [Float](repeating: 0, count: 2 * 8_192)
            _ = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                tap.read(into: b.baseAddress!, maxFrames: 8_192)
            }
            let n = WaveformFrameBuffer.capacity
            var out = [Float](repeating: 0, count: n)
            _ = out.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<Float>) -> UInt64? in
                tap.output.readLatest(into: p.baseAddress!, capacity: n)
            }
            return out
        }
        let n = WaveformFrameBuffer.capacity
        let frames = fixture.count / 2
        let left = history(.left)
        let mix = history(.mix)
        XCTAssertTrue(history(.right).allSatisfy { (v: Float) -> Bool in v == 0 }, "Right: a silent line")
        for i in stride(from: 0, to: n, by: 97) {
            let frame = frames - n + i
            XCTAssertEqual(left[i], fixture[2 * frame], accuracy: 1e-6, "Left: the L samples, sample \(i)")
            let half: Float = 0.5 * left[i]
            XCTAssertEqual(mix[i], half, accuracy: 1e-6, "Mix: (L + 0)/2, sample \(i)")
        }
    }
}
