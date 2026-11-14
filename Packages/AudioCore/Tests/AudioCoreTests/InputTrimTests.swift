// InputTrimTests.swift — AUD-008: the analysis-only input trim (contracts/input-trim.md C1-C4).
import XCTest
import Foundation
@testable import AudioCore

/// Reads a fixed interleaved stereo buffer in chunks; reports a settable session generation.
private final class StereoArrayReader: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    private let samples: [Float]
    private var position = 0   // in frames
    var analysisSessionGeneration: UInt64 = 0

    init(_ samples: [Float]) { self.samples = samples }

    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let available = samples.count / 2 - position
        let frames = min(max(maxFrames, 0), available)
        guard frames > 0 else { return 0 }
        let start = position * 2
        let count = frames * 2
        samples.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            dst.update(from: buffer.baseAddress! + start, count: count)
        }
        position += frames
        return frames
    }
}

private enum Tone {
    /// Interleaved stereo sine (both channels equal).
    static func sine(frequency: Float, amplitude: Float, frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frames * 2)
        let rate = Float(NormalizedPCMRing.sampleRate)
        for i in 0..<frames {
            let phase: Float = 2 * Float.pi * frequency * Float(i) / rate
            let value: Float = amplitude * sinf(phase)
            out[2 * i] = value
            out[2 * i + 1] = value
        }
        return out
    }

    static func rmsDecibels(_ samples: ArraySlice<Float>) -> Double {
        var sum: Double = 0
        for v in samples { sum += Double(v) * Double(v) }
        let mean: Double = sum / Double(samples.count)
        return 10 * log10(mean)
    }
}

/// Reads everything from `reader` in chunks of `chunk` frames.
private func readAll(_ reader: any NormalizedPCMReader, chunk: Int = 441) -> [Float] {
    var out: [Float] = []
    var scratch = [Float](repeating: 0, count: chunk * 2)
    while true {
        let frames = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
            reader.read(into: b.baseAddress!, maxFrames: chunk)
        }
        if frames == 0 { break }
        out += scratch[0..<(frames * 2)]
    }
    return out
}

final class InputTrimLawTests: XCTestCase {
    func testClampedRangeAndNaN() {
        XCTAssertEqual(InputTrim.clamped(-20), -12)
        XCTAssertEqual(InputTrim.clamped(30), 24)
        XCTAssertEqual(InputTrim.clamped(.nan), 0)
        XCTAssertEqual(InputTrim.clamped(-.infinity), -12)
        XCTAssertEqual(InputTrim.clamped(6), 6)
    }

    func testLinearGain() {
        XCTAssertEqual(InputTrim.linearGain(decibels: 0), 1, "0 dB is exactly unity")
        XCTAssertEqual(InputTrim.linearGain(decibels: 6.0206), 2, accuracy: 1e-4)
        XCTAssertEqual(InputTrim.linearGain(decibels: -12), 0.251_189, accuracy: 1e-5)
        XCTAssertEqual(InputTrim.linearGain(decibels: 24), 15.848_93, accuracy: 1e-3)
        XCTAssertEqual(InputTrim.linearGain(decibels: 99), InputTrim.linearGain(decibels: 24), "clamped")
    }

    func testSoftClipShape() {
        XCTAssertEqual(InputTrim.softClip(0.3), 0.3)
        XCTAssertEqual(InputTrim.softClip(-0.5), -0.5)
        XCTAssertEqual(InputTrim.softClip(1.25), 1)
        XCTAssertEqual(InputTrim.softClip(-7), -1)
        XCTAssertEqual(InputTrim.softClip(.infinity), 1)
        XCTAssertEqual(InputTrim.softClip(-.infinity), -1)
        XCTAssertEqual(InputTrim.softClip(.nan), 0)
        var previous: Float = -2
        var x: Float = -3
        while x <= 3 {
            let y = InputTrim.softClip(x)
            XCTAssertTrue(y.isFinite && y >= -1 && y <= 1, "bounded at \(x)")
            XCTAssertGreaterThanOrEqual(y, previous, "monotonic at \(x)")
            XCTAssertEqual(InputTrim.softClip(-x), -y, "odd at \(x)")
            previous = y
            x += 0.001
        }
        // Slope is continuous at the knee: just above 0.5 it is still about 1.
        let above: Float = InputTrim.softClip(0.501)
        XCTAssertEqual(above, 0.501, accuracy: 1e-5)
    }

    func testProcessorHasOnlyScalarStorage() {
        // AUD-008-R10: no buffers, no references; nothing to allocate per read.
        XCTAssertLessThanOrEqual(MemoryLayout<InputTrimProcessor>.size, 32)
    }
}

final class InputTrimReaderTests: XCTestCase {
    private let frames = 44_100 / 2

    private func trimmed(_ source: [Float], decibels: Float, chunk: Int = 441) -> [Float] {
        readAll(InputTrimReader(StereoArrayReader(source), control: InputTrimControl(decibels: decibels)), chunk: chunk)
    }

    func testToneLevelFollowsTheTrimExactlyBelowTheKnee() {
        // −20 dBFS 1 kHz sine: −12, +6 and +12 dB keep every sample below the knee (0.1 × 3.98 = 0.398).
        let source = Tone.sine(frequency: 1_000, amplitude: 0.1, frames: frames)
        let reference = Tone.rmsDecibels(source[...])
        for trim: Float in [-12, 6, 12] {
            let out = trimmed(source, decibels: trim)
            XCTAssertEqual(out.count, source.count)
            let measured = Tone.rmsDecibels(out[...]) - reference
            XCTAssertEqual(measured, Double(trim), accuracy: 0.05, "RMS change at \(trim) dB")
        }
    }

    func testPlus24OnAFullScaleToneSaturatesSafely() {
        let source = Tone.sine(frequency: 1_000, amplitude: 1, frames: frames)
        let out = trimmed(source, decibels: 24)
        XCTAssertTrue(out.allSatisfy { (v: Float) -> Bool in v.isFinite && v >= -1 && v <= 1 })
        let peak: Float = out.map { (v: Float) -> Float in abs(v) }.max() ?? 0
        XCTAssertGreaterThanOrEqual(peak, 0.99, "loud, not silenced")
        let rms = Tone.rmsDecibels(out[...])
        XCTAssertLessThanOrEqual(rms, 0.0001, "RMS never above full scale")
    }

    func testNonFiniteInputComesOutFinite() {
        let source: [Float] = [.nan, .infinity, -.infinity, 0.2, 3, -3]
        let out = trimmed(source, decibels: 6)
        XCTAssertEqual(out, [0, 1, -1, InputTrim.softClip(0.2 * InputTrim.linearGain(decibels: 6)), 1, -1])
    }

    func testZeroDecibelsIsBitExact() {
        var source = Tone.sine(frequency: 440, amplitude: 0.7, frames: 4_000)
        source[10] = 1.7
        source[11] = -2.5
        source[12] = .nan
        source[13] = .infinity
        let out = trimmed(source, decibels: 0, chunk: 333)
        XCTAssertEqual(out.map(\.bitPattern), source.map(\.bitPattern))
    }

    func testControlChangeRampsWithinTheBoundAndSettlesExactly() {
        // AUD-008-R7, R11: a change through the shared control while a reader runs. DC input below the
        // knee at every gain (0.01 × 15.85 = 0.158), so output / input is the gain frame by frame.
        let dc: Float = 0.01
        let total = 12_000
        let source = [Float](repeating: dc, count: total * 2)
        let control = InputTrimControl(decibels: -12)
        let reader = InputTrimReader(StereoArrayReader(source), control: control)
        var gains: [Float] = []
        var scratch = [Float](repeating: 0, count: 2 * 800)
        var chunk = 1
        var changedAt = -1
        var backAt = -1
        while true {
            if gains.count >= 1_000, changedAt < 0 { control.decibels = 24; changedAt = gains.count }
            if gains.count >= 6_000, backAt < 0 { control.decibels = 0; backAt = gains.count }
            let n = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                reader.read(into: b.baseAddress!, maxFrames: chunk)
            }
            if n == 0 { break }
            for i in 0..<n { gains.append(scratch[2 * i] / dc) }
            chunk = chunk % 700 + 37
        }
        XCTAssertEqual(gains.count, total)
        XCTAssertEqual(gains[0], InputTrim.linearGain(decibels: -12), accuracy: 1e-6, "a new reader starts at the target")
        let bound: Float = InputTrim.maximumRampStep + 1e-5
        for i in 1..<gains.count {
            XCTAssertLessThanOrEqual(abs(gains[i] - gains[i - 1]), bound, "step at frame \(i)")
        }
        let g24 = InputTrim.linearGain(decibels: 24)
        let settled = changedAt + InputTrim.rampFrames - 1
        XCTAssertLessThan(gains[settled - 1], g24, "still ramping before the 2,048th frame")
        XCTAssertEqual(gains[settled], g24, accuracy: 1e-5, "target after 2,048 frames")
        // Back to 0 dB: once settled the output is the input again, bit for bit.
        let unity = backAt + InputTrim.rampFrames
        XCTAssertTrue(gains[unity...].allSatisfy { (g: Float) -> Bool in g == 1 })
    }

    func testSessionChangeSnapsToTheTarget() {
        let dc: Float = 0.01
        let inner = StereoArrayReader([Float](repeating: dc, count: 8_000))
        let control = InputTrimControl(decibels: 0)
        let reader = InputTrimReader(inner, control: control)
        var scratch = [Float](repeating: 0, count: 200)
        _ = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in reader.read(into: b.baseAddress!, maxFrames: 100) }
        control.decibels = 12
        inner.analysisSessionGeneration = 1   // a new capture session
        _ = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in reader.read(into: b.baseAddress!, maxFrames: 100) }
        XCTAssertEqual(scratch[0] / dc, InputTrim.linearGain(decibels: 12), accuracy: 1e-5, "no ramp across sessions")
    }

    func testForwardsFrameCountAndGeneration() {
        let inner = StereoArrayReader([Float](repeating: 0.1, count: 20))
        inner.analysisSessionGeneration = 5
        let reader = InputTrimReader(inner, control: InputTrimControl(decibels: 6))
        XCTAssertEqual(reader.analysisSessionGeneration, 5)
        var scratch = [Float](repeating: 0, count: 40)
        let n = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in reader.read(into: b.baseAddress!, maxFrames: 20) }
        XCTAssertEqual(n, 10)
        let plain = InputTrimReader(NormalizedPCMRing(), control: InputTrimControl())
        XCTAssertEqual(plain.analysisSessionGeneration, 0)
    }

    func testControlClampsAndIgnoresNaN() {
        let control = InputTrimControl(decibels: 40)
        XCTAssertEqual(control.decibels, 24)
        control.decibels = .nan
        XCTAssertEqual(control.decibels, 0)
        control.decibels = -100
        XCTAssertEqual(control.decibels, -12)
    }
}

final class InputTrimSeamTests: XCTestCase {
    /// AUD-008-R1, S5: projectM's ring output is bit-identical whether or not the tap is read through a
    /// +24 dB trim. (The audio-state classifier's levels are computed from the sink before the ring is
    /// written, in `AudioAnalyzer`, so the trim cannot reach them either.)
    func testProjectMRingIsBitIdenticalWithTrimOnTheTap() throws {
        let tone = Tone.sine(frequency: 1_000, amplitude: 0.9, frames: 1_800)

        func run(trim: Float?) throws -> (main: [Float], analysis: [Float]) {
            let ring = NormalizedPCMRing(analysisTapCapacityFrames: 4_096)
            tone.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in ring.write(b.baseAddress!, frames: 1_800) }
            let tap = try XCTUnwrap(ring.analysisTap)
            let consumer: any NormalizedPCMReader = trim.map { (db: Float) -> any NormalizedPCMReader in
                InputTrimReader(tap, control: InputTrimControl(decibels: db))
            } ?? tap
            let analysis = readAll(consumer)
            var main = [Float](repeating: 0, count: 1_800 * 2)
            let frames = main.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                ring.readAll(into: b.baseAddress!, maxFrames: 1_800)
            }
            XCTAssertEqual(frames, 1_800)
            return (main, analysis)
        }

        let raw = try run(trim: nil)
        let trimmed = try run(trim: 24)
        XCTAssertEqual(raw.main.map(\.bitPattern), tone.map(\.bitPattern), "projectM reads exactly what was written")
        XCTAssertEqual(trimmed.main.map(\.bitPattern), raw.main.map(\.bitPattern), "a +24 dB trim leaves projectM's PCM untouched")
        XCTAssertEqual(raw.analysis.map(\.bitPattern), tone.map(\.bitPattern))
        XCTAssertNotEqual(trimmed.analysis, raw.analysis, "the trim acted on the analysis copy")
        XCTAssertTrue(trimmed.analysis.allSatisfy { (v: Float) -> Bool in abs(v) <= 1 })
    }
}
