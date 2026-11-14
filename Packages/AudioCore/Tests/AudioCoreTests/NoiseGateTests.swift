// NoiseGateTests.swift — AUD-011: the analysis-only input noise gate
// (specs/091-aud-011-input-noise-gate, contracts/noise-gate.md C1-C4; spec User Stories 1, 3).
//
// Timing is measured on the sample clock: frame indices of the fixture, read in 512-frame buffers.
import XCTest
import Foundation
@testable import AudioCore

/// Reads a fixed interleaved stereo buffer in chunks; reports a settable session generation.
private final class GateFixtureReader: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    private var samples: [Float]
    private var position = 0   // in frames
    var analysisSessionGeneration: UInt64 = 0

    init(_ samples: [Float]) { self.samples = samples }

    /// Appends more frames (a later part of the same stream).
    func append(_ more: [Float]) { samples += more }

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

private enum GateFixture {
    static let rate: Double = NormalizedPCMRing.sampleRate
    static let buffer = 512

    static func amplitude(dBFS: Double) -> Float {
        let exponent: Double = dBFS / 20
        return Float(pow(10, exponent))
    }

    /// A 1 kHz sine at `dBFS` peak on both channels, `frames` long, phase continuing from `offset`.
    static func tone(dBFS: Double, frames: Int, offset: Int = 0, rightPhase: Int = 0) -> [Float] {
        let a: Float = amplitude(dBFS: dBFS)
        var out = [Float](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            let n: Double = Double(i + offset)
            let phase: Double = 2 * Double.pi * 1_000 * n / rate
            let phaseR: Double = 2 * Double.pi * 1_000 * Double(i + offset + rightPhase) / rate
            out[2 * i] = a * Float(sin(phase))
            out[2 * i + 1] = a * Float(sin(phaseR))
        }
        return out
    }

    static func silence(frames: Int) -> [Float] { [Float](repeating: 0, count: frames * 2) }

    /// Seeded uniform noise with the given RMS (uniform on ±a has RMS a/√3).
    static func noise(rmsDBFS: Double, frames: Int, seed: UInt64 = 0x5EED) -> [Float] {
        let rms: Float = amplitude(dBFS: rmsDBFS)
        let a: Float = rms * Float(3.0.squareRoot())
        var state: UInt64 = seed
        var out = [Float](repeating: 0, count: frames * 2)
        for i in 0..<(frames * 2) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let top: UInt64 = state >> 40                       // 24 bits
            let unit: Float = Float(top) / Float(1 << 24)       // 0 ..< 1
            let centered: Float = unit * 2 - 1
            out[i] = a * centered
        }
        return out
    }

    static func left(_ samples: [Float]) -> [Float] {
        stride(from: 0, to: samples.count, by: 2).map { (i: Int) -> Float in samples[i] }
    }

    static func activeControl(openDecibels: Float = -50) -> NoiseGateControl {
        NoiseGateControl(isEnabled: true, isMicrophoneSource: true, openDecibels: openDecibels)
    }

    /// Per-frame gain on the left channel where the input is large enough to measure (else nil).
    static func gains(input: [Float], output: [Float], minimum: Float) -> [Float?] {
        let inL = left(input)
        let outL = left(output)
        return (0..<inL.count).map { (i: Int) -> Float? in
            let x: Float = inL[i]
            guard abs(x) >= minimum else { return nil }
            return outL[i] / x
        }
    }
}

/// Reads everything from `reader` in 512-frame buffers.
private func readAll(_ reader: any NormalizedPCMReader, chunk: Int = GateFixture.buffer) -> [Float] {
    var out: [Float] = []
    var scratch = [Float](repeating: 0, count: chunk * 2)
    while true {
        let frames = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
            reader.read(into: b.baseAddress!, maxFrames: chunk)
        }
        if frames == 0 { break }
        out.append(contentsOf: scratch[0..<(frames * 2)])
    }
    return out
}

final class NoiseGateAcceptanceTests: XCTestCase {
    private let withinOneDecibel: Float = Float(pow(10.0, -1.0 / 20.0))   // 0.8913

    /// AUD-011-S1: digital silence, then −70 dBFS RMS noise, stays gated: every output sample is 0.
    func testSilenceFixtureRemainsGated() {
        let second = Int(GateFixture.rate)
        let input = GateFixture.silence(frames: second) + GateFixture.noise(rmsDBFS: -70, frames: second)
        let reader = NoiseGateReader(GateFixtureReader(input), control: GateFixture.activeControl())
        let output = readAll(reader)
        XCTAssertEqual(output.count, input.count)
        XCTAssertTrue(output.allSatisfy { (v: Float) -> Bool in v == 0 }, "the silence fixture stays gated")
        XCTAssertTrue(input.contains { (v: Float) -> Bool in v != 0 }, "the noise part is not empty")
    }

    /// AUD-011-S2: a tone stepping from −80 to −30 dBFS opens to within 1 dB of unity within the
    /// configured attack plus one buffer, measured from the step on the sample clock.
    func testToneCrossingThresholdOpensWithinAttack() {
        let step = 22_050   // 0.5 s at −80 dBFS
        let input = GateFixture.tone(dBFS: -80, frames: step) + GateFixture.tone(dBFS: -30, frames: 22_050, offset: step)
        let reader = NoiseGateReader(GateFixtureReader(input), control: GateFixture.activeControl())
        let output = readAll(reader)
        let before = Array(output[0..<(step * 2)])
        XCTAssertTrue(before.allSatisfy { (v: Float) -> Bool in v == 0 }, "closed below the threshold")

        let gains = GateFixture.gains(input: input, output: output, minimum: 0.005)
        let opened = (step..<gains.count).first { (i: Int) -> Bool in (gains[i] ?? 0) >= withinOneDecibel }
        let openedAt = try? XCTUnwrap(opened)
        let openingFrames: Int = (openedAt ?? Int.max) - step
        let parameters = NoiseGateParameters.default
        XCTAssertEqual(parameters.attackFrames, 221)
        XCTAssertLessThanOrEqual(openingFrames, parameters.attackFrames + GateFixture.buffer)
        print("AUD-011 opening: \(openingFrames) frames to within 1 dB (attack \(parameters.attackFrames) + buffer \(GateFixture.buffer))")
        // Fully open after the attack, and bit-exact pass-through while open.
        let settled = step + parameters.attackFrames + 64
        XCTAssertEqual(output[(2 * settled)..<(2 * step + 4_000)].map(\.bitPattern),
                       input[(2 * settled)..<(2 * step + 4_000)].map(\.bitPattern))
    }
}

final class NoiseGateTimingTests: XCTestCase {
    /// AUD-011-S3: after the level drops below the close threshold the gain stays 1 for the hold, then
    /// ramps to 0 over the release. The tone drops to −70 dBFS rather than to digital silence so the
    /// gain stays measurable (out / in) on every frame.
    func testHoldAndRelease() {
        let loud = 22_050
        let quiet = 22_050
        let input = GateFixture.tone(dBFS: -30, frames: loud) + GateFixture.tone(dBFS: -70, frames: quiet, offset: loud)
        let reader = NoiseGateReader(GateFixtureReader(input), control: GateFixture.activeControl())
        let output = readAll(reader)
        let gains = GateFixture.gains(input: input, output: output, minimum: 0.0001)
        let parameters = NoiseGateParameters.default
        XCTAssertEqual(parameters.holdFrames, 4_410)
        XCTAssertEqual(parameters.releaseFrames, 6_615)
        // The detector's fall from −30 to −56 dBFS: ⌈441 · ln(10^(26/20))⌉.
        let fallExponent: Double = 26.0 / 20.0 * log(10.0)
        let fall = Int((441.0 * fallExponent).rounded(.up))
        XCTAssertEqual(fall, 1_321)

        let firstBelowUnity = (loud..<gains.count).first { (i: Int) -> Bool in
            guard let g = gains[i] else { return false }
            return g < 1
        }
        let lastNonZero = (loud..<gains.count).last { (i: Int) -> Bool in
            guard let g = gains[i] else { return false }
            return g != 0
        }
        let start: Int = (firstBelowUnity ?? loud) - loud
        let end: Int = (lastNonZero ?? Int.max) - loud
        print("AUD-011 closing: gain below 1 after \(start) frames, last non-zero gain at \(end) frames (fall \(fall) + hold \(parameters.holdFrames) + release \(parameters.releaseFrames))")
        XCTAssertGreaterThanOrEqual(start, fall + parameters.holdFrames - GateFixture.buffer)
        XCTAssertLessThanOrEqual(start, fall + parameters.holdFrames + GateFixture.buffer)
        XCTAssertLessThanOrEqual(end, fall + parameters.holdFrames + parameters.releaseFrames + GateFixture.buffer)
        XCTAssertGreaterThanOrEqual(end, fall + parameters.holdFrames + parameters.releaseFrames - GateFixture.buffer)
        // The release ramps (no hard switch): consecutive measured gains differ by ≤ 1 / releaseFrames + ε.
        let ramp: [Float] = gains[(loud + start)...(loud + end)].compactMap { (g: Float?) -> Float? in g }
        let maximumStep: Float = 1 / Float(parameters.releaseFrames) * 25 + 1e-4   // ≤ 25 frames between measured points
        for i in 1..<ramp.count { XCTAssertLessThanOrEqual(abs(ramp[i] - ramp[i - 1]), maximumStep) }
    }

    /// AUD-011-S4: a tone between the close (−56) and open (−50) thresholds neither opens a closed
    /// gate nor closes an open one over 2 s.
    func testHysteresisPreventsChatter() {
        let twoSeconds = 88_200
        // Closed stays closed.
        let hovering = GateFixture.tone(dBFS: -53, frames: twoSeconds)
        let closedReader = NoiseGateReader(GateFixtureReader(hovering), control: GateFixture.activeControl())
        XCTAssertTrue(readAll(closedReader).allSatisfy { (v: Float) -> Bool in v == 0 }, "a closed gate stays closed")

        // Open stays open: a −30 dBFS burst opens it, then the tone hovers at −53 dBFS.
        let burst = 8_820
        let input = GateFixture.tone(dBFS: -30, frames: burst) + GateFixture.tone(dBFS: -53, frames: twoSeconds, offset: burst)
        let reader = NoiseGateReader(GateFixtureReader(input), control: GateFixture.activeControl())
        let output = readAll(reader)
        let hover = Array(output[(2 * burst)...])
        let expected = Array(input[(2 * burst)...])
        XCTAssertEqual(hover.map(\.bitPattern), expected.map(\.bitPattern), "an open gate stays fully open: zero transitions")
    }

    /// AUD-011-R6: the configured attack and threshold are the ones used.
    func testConfiguredAttackAndThreshold() {
        let parameters = NoiseGateParameters(openDecibels: -40, attackSeconds: 0.020)
        XCTAssertEqual(parameters.attackFrames, 882)
        XCTAssertEqual(parameters.closeDecibels, -46)
        let step = 22_050
        let input = GateFixture.tone(dBFS: -45, frames: step) + GateFixture.tone(dBFS: -30, frames: 22_050, offset: step)
        let control = GateFixture.activeControl(openDecibels: -40)
        let reader = NoiseGateReader(GateFixtureReader(input), control: control, parameters: parameters)
        let output = readAll(reader)
        XCTAssertTrue(output[0..<(2 * step)].allSatisfy { (v: Float) -> Bool in v == 0 }, "−45 dBFS stays below a −40 dBFS gate")
        let gains = GateFixture.gains(input: input, output: output, minimum: 0.005)
        let threshold: Float = Float(pow(10.0, -1.0 / 20.0))
        let opened = (step..<gains.count).first { (i: Int) -> Bool in (gains[i] ?? 0) >= threshold } ?? Int.max
        let openingFrames: Int = opened - step
        XCTAssertGreaterThan(openingFrames, 221 + GateFixture.buffer, "slower than the default attack")
        XCTAssertLessThanOrEqual(openingFrames, parameters.attackFrames + GateFixture.buffer)
    }
}

final class NoiseGateBehaviourTests: XCTestCase {
    private static var oddSamples: [Float] {
        var samples = GateFixture.noise(rmsDBFS: -70, frames: 2_000)
        samples[10] = .nan
        samples[11] = 1.5
        samples[12] = -.infinity
        return samples
    }

    /// AUD-011-S5: off, or on with a non-microphone source, is bit-exact pass-through.
    func testInactiveIsBitExact() {
        let input = Self.oddSamples
        let off = NoiseGateControl(isEnabled: false, isMicrophoneSource: true, openDecibels: -20)
        let notMic = NoiseGateControl(isEnabled: true, isMicrophoneSource: false, openDecibels: -20)
        for control in [off, notMic] {
            let output = readAll(NoiseGateReader(GateFixtureReader(input), control: control))
            XCTAssertEqual(output.map(\.bitPattern), input.map(\.bitPattern))
        }
        XCTAssertFalse(off.isActive)
        XCTAssertFalse(notMic.isActive)
        XCTAssertTrue(GateFixture.activeControl().isActive)
    }

    /// AUD-011-R6: every parameter is bounded; NaN reads as the default.
    func testParameterBounds() {
        let nan = NoiseGateParameters(openDecibels: .nan, hysteresisDecibels: .nan, attackSeconds: .nan,
                                      holdSeconds: .nan, releaseSeconds: .nan)
        XCTAssertEqual(nan, NoiseGateParameters.default)
        let low = NoiseGateParameters(openDecibels: -200, hysteresisDecibels: -5, attackSeconds: 0,
                                      holdSeconds: -1, releaseSeconds: 0)
        XCTAssertEqual(low.openDecibels, -80)
        XCTAssertEqual(low.hysteresisDecibels, 0)
        XCTAssertEqual(low.attackSeconds, 0.0005)
        XCTAssertEqual(low.holdSeconds, 0)
        XCTAssertEqual(low.holdFrames, 0)
        XCTAssertEqual(low.releaseSeconds, 0.010)
        let high = NoiseGateParameters(openDecibels: 10, hysteresisDecibels: 99, attackSeconds: 9,
                                       holdSeconds: 9, releaseSeconds: 9)
        XCTAssertEqual(high.openDecibels, -20)
        XCTAssertEqual(high.hysteresisDecibels, 20)
        XCTAssertEqual(high.attackSeconds, 0.050)
        XCTAssertEqual(high.holdSeconds, 1)
        XCTAssertEqual(high.releaseSeconds, 2)
        let control = NoiseGateControl(isEnabled: true, isMicrophoneSource: true, openDecibels: .nan)
        XCTAssertEqual(control.openDecibels, -50)
        control.openDecibels = -100
        XCTAssertEqual(control.openDecibels, -80)
        control.openDecibels = 0
        XCTAssertEqual(control.openDecibels, -20)
    }

    /// AUD-011-R9: a new session generation, or switching the gate back on, starts closed; a
    /// threshold change reaches a live reader at its next read; the generation is forwarded.
    func testRestartsClosedAndFollowsTheControl() {
        let loud = GateFixture.tone(dBFS: -30, frames: 4_410)
        let quiet = GateFixture.tone(dBFS: -53, frames: 4_410, offset: 4_410)
        let fixture = GateFixtureReader(loud)
        let control = GateFixture.activeControl()
        let reader = NoiseGateReader(fixture, control: control)
        _ = readAll(reader)   // open
        fixture.analysisSessionGeneration = 7
        XCTAssertEqual(reader.analysisSessionGeneration, 7)
        fixture.append(quiet)
        XCTAssertTrue(readAll(reader).allSatisfy { (v: Float) -> Bool in v == 0 }, "a new session starts closed")

        // Re-activation: open it, switch off then on, and it starts closed again.
        fixture.append(loud)
        _ = readAll(reader)
        control.isEnabled = false
        fixture.append(quiet)
        let passed = readAll(reader)
        XCTAssertEqual(passed.map(\.bitPattern), quiet.map(\.bitPattern), "off: pass-through")
        control.isEnabled = true
        fixture.append(quiet)
        XCTAssertTrue(readAll(reader).allSatisfy { (v: Float) -> Bool in v == 0 }, "switched on again: closed")

        // The threshold follows the control: at −60 dBFS the −53 dBFS tone opens the gate.
        control.openDecibels = -60
        fixture.append(GateFixture.tone(dBFS: -53, frames: 4_410))
        XCTAssertTrue(readAll(reader).contains { (v: Float) -> Bool in v != 0 }, "a lower threshold opens it")
    }

    /// AUD-011-R1 (contract C5): the gate sits after the trim, so it measures post-trim levels.
    func testGateSeesTheTrimmedLevel() {
        let tone = GateFixture.tone(dBFS: -58, frames: 8_820)
        func gatedOutput(trim: Float) -> [Float] {
            let selected = ChannelSelectionReader(GateFixtureReader(tone), control: ChannelSelectionControl(mode: .mix))
            let trimmed = InputTrimReader(selected, control: InputTrimControl(decibels: trim))
            return readAll(NoiseGateReader(trimmed, control: GateFixture.activeControl()))
        }
        XCTAssertTrue(gatedOutput(trim: 0).allSatisfy { (v: Float) -> Bool in v == 0 }, "−58 dBFS stays gated at 0 dB")
        XCTAssertTrue(gatedOutput(trim: 12).contains { (v: Float) -> Bool in v != 0 }, "+12 dB lifts it to −46 dBFS: open")
    }
}

final class NoiseGateSeamTests: XCTestCase {
    /// AUD-011-R1, S6: projectM's ring output is bit-identical whether or not the tap is read through
    /// channel selection (Side), a +24 dB trim and a closed gate, while the gated analysis copy is all
    /// zeros. (The classifier's levels come from the sink before the ring is written.)
    func testProjectMRingIsBitIdenticalWithAllThreeReadersOnTheTap() throws {
        let tone = GateFixture.tone(dBFS: -60, frames: 1_800, rightPhase: 7)   // L ≠ R
        let frames = 1_800

        func run(processed: Bool) throws -> (main: [Float], analysis: [Float]) {
            let ring = NormalizedPCMRing(analysisTapCapacityFrames: 4_096)
            tone.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in ring.write(b.baseAddress!, frames: frames) }
            let tap = try XCTUnwrap(ring.analysisTap)
            let consumer: any NormalizedPCMReader
            if processed {
                let selected = ChannelSelectionReader(tap, control: ChannelSelectionControl(mode: .side))
                let trimmed = InputTrimReader(selected, control: InputTrimControl(decibels: 24))
                consumer = NoiseGateReader(trimmed, control: GateFixture.activeControl(openDecibels: -20))
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

        let raw = try run(processed: false)
        let processed = try run(processed: true)
        XCTAssertEqual(raw.main.map(\.bitPattern), tone.map(\.bitPattern), "projectM reads exactly what was written")
        XCTAssertEqual(processed.main.map(\.bitPattern), raw.main.map(\.bitPattern), "selection, trim and gate leave projectM's PCM untouched")
        XCTAssertEqual(raw.analysis.map(\.bitPattern), tone.map(\.bitPattern))
        XCTAssertEqual(processed.analysis.count, raw.analysis.count)
        XCTAssertTrue(processed.analysis.allSatisfy { (v: Float) -> Bool in v == 0 }, "the closed gate muted the analysis copy")
    }
}
