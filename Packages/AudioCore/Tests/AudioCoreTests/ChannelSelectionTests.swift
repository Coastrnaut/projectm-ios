// ChannelSelectionTests.swift — AUD-009: the analysis-only channel selection
// (specs/089-aud-009-channel-selection, contracts/channel-selection.md C1-C3; spec User Stories 2, 3).
import XCTest
import Foundation
@testable import AudioCore

/// Reads a fixed interleaved stereo buffer in chunks; reports a settable session generation.
private final class StereoFixtureReader: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
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

/// The fixtures of User Story 2: a 1 kHz sine placed on the channels in different ways.
private enum Fixture {
    static let frames = 4_410   // 0.1 s: a whole number of 1 kHz periods (44.1 per ms × 100)
    static let amplitude: Float = 0.1   // −20 dBFS peak

    static func sine(_ i: Int) -> Float {
        let rate = Float(NormalizedPCMRing.sampleRate)
        let phase: Float = 2 * Float.pi * 1_000 * Float(i) / rate
        return amplitude * sinf(phase)
    }

    /// Interleaved stereo with L = left(i), R = right(i).
    static func make(left: (Int) -> Float, right: (Int) -> Float) -> [Float] {
        var out = [Float](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            out[2 * i] = left(i)
            out[2 * i + 1] = right(i)
        }
        return out
    }

    static var leftOnly: [Float] { make(left: { (i: Int) -> Float in sine(i) }, right: { (_: Int) -> Float in 0 }) }
    static var rightOnly: [Float] { make(left: { (_: Int) -> Float in 0 }, right: { (i: Int) -> Float in sine(i) }) }
    static var antiPhase: [Float] { make(left: { (i: Int) -> Float in sine(i) }, right: { (i: Int) -> Float in -sine(i) }) }
    static var mono: [Float] { make(left: { (i: Int) -> Float in sine(i) }, right: { (i: Int) -> Float in sine(i) }) }

    static func channel(_ samples: [Float], _ index: Int) -> [Float] {
        stride(from: index, to: samples.count, by: 2).map { (i: Int) -> Float in samples[i] }
    }

    static func rms(_ samples: [Float]) -> Double {
        var sum: Double = 0
        for v in samples { sum += Double(v) * Double(v) }
        let count: Double = Double(max(samples.count, 1))
        return (sum / count).squareRoot()
    }

    /// 20·log10(rms(a)/rms(b)).
    static func relativeDecibels(_ a: [Float], to b: [Float]) -> Double {
        let ratio: Double = rms(a) / rms(b)
        return 20 * log10(ratio)
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

private func select(_ samples: [Float], _ mode: AnalysisChannelMode) -> [Float] {
    readAll(ChannelSelectionReader(StereoFixtureReader(samples), control: ChannelSelectionControl(mode: mode)))
}

final class ChannelSelectionModeTests: XCTestCase {
    /// The analysed signal s: what the downstream mono mix ((L′ + R′)·0.5, `SpectrumStream` `.mid` and
    /// `WaveformTap`) makes of the reader's output. Outside Mix both output channels must carry s.
    private func selected(_ samples: [Float], _ mode: AnalysisChannelMode, file: StaticString = #filePath, line: UInt = #line) -> [Float] {
        let out = select(samples, mode)
        XCTAssertEqual(out.count, samples.count, file: file, line: line)
        let left = Fixture.channel(out, 0)
        let right = Fixture.channel(out, 1)
        if mode != .mix {
            XCTAssertEqual(left.map(\.bitPattern), right.map(\.bitPattern), "\(mode): both channels carry s", file: file, line: line)
        }
        return zip(left, right).map { (pair: (Float, Float)) -> Float in (pair.0 + pair.1) * 0.5 }
    }

    /// The roadmap acceptance (AUD-009-S1): a left-only fixture in each mode.
    func testLeftOnlyFixtureGivesTheExpectedLevelPerMode() {
        let input = Fixture.leftOnly
        let left = Fixture.channel(input, 0)
        let expected: [(AnalysisChannelMode, Double)] = [(.mix, -6.0206), (.left, 0), (.mid, -3.0103), (.side, -3.0103)]
        for (mode, decibels) in expected {
            let s = selected(input, mode)
            XCTAssertEqual(Fixture.relativeDecibels(s, to: left), decibels, accuracy: 0.01, "\(mode)")
        }
        XCTAssertEqual(selected(input, .left).map(\.bitPattern), left.map(\.bitPattern), "Left is an exact copy of L")
        XCTAssertTrue(selected(input, .right).allSatisfy { (v: Float) -> Bool in v == 0 }, "Right is silent")
    }

    func testRightOnlyFixtureMirrorsTheLeftOnlyOne() {
        let input = Fixture.rightOnly
        let right = Fixture.channel(input, 1)
        XCTAssertTrue(selected(input, .left).allSatisfy { (v: Float) -> Bool in v == 0 }, "Left is silent")
        XCTAssertEqual(selected(input, .right).map(\.bitPattern), right.map(\.bitPattern), "Right is an exact copy of R")
        XCTAssertEqual(Fixture.relativeDecibels(selected(input, .mix), to: right), -6.0206, accuracy: 0.01)
        XCTAssertEqual(Fixture.relativeDecibels(selected(input, .mid), to: right), -3.0103, accuracy: 0.01)
        XCTAssertEqual(Fixture.relativeDecibels(selected(input, .side), to: right), -3.0103, accuracy: 0.01)
    }

    /// Mid versus Side: anti-phase content is invisible to Mix and Mid and +3 dB in Side.
    func testAntiPhaseFixtureSeparatesMidFromSide() {
        let input = Fixture.antiPhase
        let left = Fixture.channel(input, 0)
        XCTAssertTrue(selected(input, .mix).allSatisfy { (v: Float) -> Bool in v == 0 }, "Mix cancels")
        XCTAssertTrue(selected(input, .mid).allSatisfy { (v: Float) -> Bool in v == 0 }, "Mid cancels")
        XCTAssertEqual(Fixture.relativeDecibels(selected(input, .side), to: left), 3.0103, accuracy: 0.01)
    }

    /// Clarification "mono source": Mix, Left, Right give the mono signal bit for bit; Mid +3.01 dB; Side silent.
    func testMonoSourceGivesTheMonoSignal() {
        let input = Fixture.mono
        let mono = Fixture.channel(input, 0)
        for mode: AnalysisChannelMode in [.mix, .left, .right] {
            XCTAssertEqual(selected(input, mode).map(\.bitPattern), mono.map(\.bitPattern), "\(mode)")
        }
        XCTAssertEqual(Fixture.relativeDecibels(selected(input, .mid), to: mono), 3.0103, accuracy: 0.01)
        XCTAssertTrue(selected(input, .side).allSatisfy { (v: Float) -> Bool in v == 0 }, "a mono source has no side")
    }

    /// AUD-009-R4, S4: Mix is bit-exact (the downstream (L + R)·0.5 is today's mix), even above 1 and NaN.
    func testMixIsBitExact() {
        var input = Fixture.make(left: { (i: Int) -> Float in Fixture.sine(i) }, right: { (i: Int) -> Float in Fixture.sine(i + 7) * 0.5 })
        input[10] = 3.5
        input[11] = -.infinity
        input[12] = .nan
        XCTAssertEqual(select(input, .mix).map(\.bitPattern), input.map(\.bitPattern))
    }

    /// AUD-009-R3, research D2: every downstream mono mix of (s, s) is s exactly, so the pipeline and the
    /// oscilloscope see the selected signal unchanged.
    func testDownstreamMixOfTheSelectedPairIsExactlyS() {
        let input = Fixture.make(left: { (i: Int) -> Float in Fixture.sine(i) }, right: { (i: Int) -> Float in Fixture.sine(i + 11) * 0.3 })
        for mode: AnalysisChannelMode in [.left, .right, .mid, .side] {
            let out = select(input, mode)
            for i in stride(from: 0, to: out.count, by: 2) {
                let mixed: Float = (out[i] + out[i + 1]) * 0.5
                XCTAssertEqual(mixed.bitPattern, out[i].bitPattern, "\(mode) frame \(i / 2)")
            }
        }
    }

    func testDefinitionsPerFrame() {
        let l: Float = 0.6
        let r: Float = -0.2
        let k: Float = ChannelSelection.inverseSquareRootOfTwo
        let cases: [(AnalysisChannelMode, Float)] = [(.mix, (l + r) * 0.5), (.left, l), (.right, r), (.mid, (l + r) * k), (.side, (l - r) * k)]
        for (mode, expected) in cases {
            var frame: [Float] = [l, r]
            frame.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Void in
                ChannelSelection.apply(b.baseAddress!, frames: 1, mode: mode)
            }
            if mode == .mix {
                XCTAssertEqual(frame, [l, r], "Mix leaves the pair for the downstream mix")
            } else {
                XCTAssertEqual(frame, [expected, expected], "\(mode)")
            }
        }
        XCTAssertEqual(k, Float(0.5).squareRoot(), "1/√2")
    }
}

final class ChannelSelectionReaderTests: XCTestCase {
    /// AUD-009-R10: a mode change through the shared control reaches a live reader at its next read.
    func testModeChangeReachesTheRunningReader() {
        let control = ChannelSelectionControl()
        let reader = ChannelSelectionReader(StereoFixtureReader(Fixture.leftOnly), control: control)
        var scratch = [Float](repeating: 0, count: 2 * 441)
        func next() -> [Float] {
            let frames = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                reader.read(into: b.baseAddress!, maxFrames: 441)
            }
            return Array(scratch[0..<(frames * 2)])
        }
        let first = next()
        XCTAssertTrue(first.contains { (v: Float) -> Bool in v != 0 }, "Mix: L reaches the left channel")
        control.mode = .right
        let second = next()
        XCTAssertTrue(second.allSatisfy { (v: Float) -> Bool in v == 0 }, "Right on a left-only fixture is silent")
        control.mode = .left
        let third = next()
        XCTAssertTrue(third.contains { (v: Float) -> Bool in v != 0 })
    }

    func testForwardsFrameCountAndGeneration() {
        let raw = StereoFixtureReader(Fixture.leftOnly)
        raw.analysisSessionGeneration = 7
        let reader = ChannelSelectionReader(raw, control: ChannelSelectionControl(mode: .side))
        XCTAssertEqual(reader.analysisSessionGeneration, 7)
        var scratch = [Float](repeating: 0, count: 2 * 5_000)
        let frames = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
            reader.read(into: b.baseAddress!, maxFrames: 5_000)
        }
        XCTAssertEqual(frames, Fixture.frames)
        raw.analysisSessionGeneration = 8
        XCTAssertEqual(reader.analysisSessionGeneration, 8)
    }

    func testControlRoundTripsAndMapsUnknownRawValuesToMix() {
        let control = ChannelSelectionControl()
        XCTAssertEqual(control.mode, .mix, "default")
        for mode in AnalysisChannelMode.allCases {
            control.mode = mode
            XCTAssertEqual(control.mode, mode)
        }
        XCTAssertEqual(AnalysisChannelMode(validating: 200), .mix)
        XCTAssertEqual(AnalysisChannelMode(storedValue: "centre"), .mix)
        XCTAssertEqual(AnalysisChannelMode(storedValue: "side"), .side)
        XCTAssertEqual(AnalysisChannelMode.allCases.map(\.storedValue), ["mix", "left", "right", "mid", "side"])
    }

    /// AUD-009-R5: selection first, then the trim.
    func testCompositionWithTheTrim() {
        let input = Fixture.leftOnly
        let left = Fixture.channel(input, 0)
        let trimmed = readAll(InputTrimReader(ChannelSelectionReader(StereoFixtureReader(input), control: ChannelSelectionControl(mode: .left)),
                                              control: InputTrimControl(decibels: 6.0206)))
        let s = Fixture.channel(trimmed, 0)
        for i in stride(from: 0, to: s.count, by: 37) {
            let doubled: Float = 2 * left[i]
            XCTAssertEqual(s[i], doubled, accuracy: 1e-4, "frame \(i)")
        }
        // Mid of a full-scale correlated tone is √2 over full scale; the trim's soft clip bounds it.
        let loud = Fixture.make(left: { (i: Int) -> Float in Fixture.sine(i) * 10 }, right: { (i: Int) -> Float in Fixture.sine(i) * 10 })
        let midOnly = select(loud, .mid)
        XCTAssertGreaterThan(midOnly.map { (v: Float) -> Float in abs(v) }.max() ?? 0, 1.4, "without a trim Mid can exceed 1")
        let bounded = readAll(InputTrimReader(ChannelSelectionReader(StereoFixtureReader(loud), control: ChannelSelectionControl(mode: .mid)),
                                              control: InputTrimControl(decibels: 1)))
        XCTAssertTrue(bounded.allSatisfy { (v: Float) -> Bool in v.isFinite && abs(v) <= 1 })
    }
}

final class ChannelSelectionSeamTests: XCTestCase {
    /// AUD-009-R1, S5: projectM's ring output is bit-identical whether or not the tap is read through
    /// Side selection and a +24 dB trim. (The audio-state classifier's levels come from the sink before
    /// the ring is written, in `AudioAnalyzer`, so neither can reach them.)
    func testProjectMRingIsBitIdenticalWithSelectionOnTheTap() throws {
        let tone = Fixture.make(left: { (i: Int) -> Float in Fixture.sine(i) * 9 }, right: { (i: Int) -> Float in Fixture.sine(i + 5) * 3 })
        let frames = 1_800

        func run(processed: Bool) throws -> (main: [Float], analysis: [Float]) {
            let ring = NormalizedPCMRing(analysisTapCapacityFrames: 4_096)
            tone.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in ring.write(b.baseAddress!, frames: frames) }
            let tap = try XCTUnwrap(ring.analysisTap)
            let consumer: any NormalizedPCMReader
            if processed {
                let selected = ChannelSelectionReader(tap, control: ChannelSelectionControl(mode: .side))
                consumer = InputTrimReader(selected, control: InputTrimControl(decibels: 24))
            } else {
                consumer = tap
            }
            let analysis = readAll(consumer)
            var main = [Float](repeating: 0, count: frames * 2)
            let read = main.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                ring.readAll(into: b.baseAddress!, maxFrames: frames)
            }
            XCTAssertEqual(read, frames)
            return (main, analysis)
        }

        let written = Array(tone[0..<(frames * 2)])
        let raw = try run(processed: false)
        let processed = try run(processed: true)
        XCTAssertEqual(raw.main.map(\.bitPattern), written.map(\.bitPattern), "projectM reads exactly what was written")
        XCTAssertEqual(processed.main.map(\.bitPattern), raw.main.map(\.bitPattern), "Side + 24 dB leaves projectM's PCM untouched")
        XCTAssertEqual(raw.analysis.map(\.bitPattern), written.map(\.bitPattern))
        XCTAssertNotEqual(processed.analysis, raw.analysis, "the selection acted on the analysis copy")
    }
}
