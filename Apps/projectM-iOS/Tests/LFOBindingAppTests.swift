// LFOBindingAppTests.swift — MOD-007-T09 (US3; MOD-007-R5, R6, R9, S3, S5): in the app, a binding from a scene
// oscillator (`audio.lfo.0`) drives the glow intensity along the closed-form waveform through `NativeSpectrumHost`'s
// frame evaluation, and Reduce flashing caps a fast oscillator at 3 Hz. Deterministic: frame times are passed in.
// Needs a Metal device (the simulator renders with the host GPU); skips without one. Also: the scene carry writes the
// stored `lfos` list back unchanged.
// MOD-009-T09 (MOD-009-R9, S6): a 1-beat synced oscillator on the glow follows the tap tempo (120 BPM: a 0.5 s cycle)
// read from `TempoCoordinator.snapshot` each frame, and after Reset continues smoothly at its stored rate.
// MOD-008-T10 (MOD-008-R3, S5): a seeded sample-and-hold oscillator on the glow holds its seeded level for each step.
import Foundation
import Metal
import ParameterGraph
import PerformanceControl
import SceneFormat
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class LFOBindingAppTests: XCTestCase {
    private static let frame: UInt64 = 16_666_667   // 60 fps
    private static let origin: UInt64 = 1_000_000_000
    private static let second: UInt64 = 1_000_000_000

    private func makeHost(_ lfo: LFO) throws -> NativeSpectrumHost {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.5))
        try host.setLFOs([lfo])
        try host.bind(AudioFeatureBinding(source: .lfo(0), target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1))
        return host
    }

    private func apply(_ host: NativeSpectrumHost, at time: UInt64) {
        let bands: [Float] = [0.1, 0.1, 0.1]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            host.applyModulation(bands: buffer, timeNanoseconds: time)
        }
    }

    func testLFOBindingDrivesTheGlowAlongTheWaveform() throws {
        let lfo = try LFO(shape: .sine, rateHz: 0.5)   // 2 s period, full swing around 0.5
        let host = try makeHost(lfo)
        XCTAssertEqual(host.lfos, [lfo])
        var samples: [(elapsed: UInt64, glow: Double)] = []
        for index in 0...120 {   // 2 s at 60 fps
            let elapsed = UInt64(index) * Self.frame
            apply(host, at: Self.origin + elapsed)
            samples.append((elapsed, Double(host.effectiveGlow.intensity)))
            XCTAssertEqual(Double(host.effectiveGlow.intensity), lfo.value(elapsedNanoseconds: elapsed), accuracy: 1e-6,
                           "frame \(index)")
        }
        XCTAssertEqual(samples[0].glow, 0.5, accuracy: 1e-6, "the first frame is the origin: phase 0, the centre")
        XCTAssertEqual(samples[30].glow, 1, accuracy: 1e-3, "¼ period (0.5 s): the peak")
        XCTAssertEqual(samples[90].glow, 0, accuracy: 1e-3, "¾ period (1.5 s): the trough")
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual intensity is unchanged")
        XCTAssertEqual(host.bloomParameters?.intensity, host.effectiveGlow.intensity, "the bloom renders the effective intensity")
    }

    func testReduceFlashingCapsTheOscillatorAtThreeHertz() throws {
        let fast = try LFO(shape: .triangle, rateHz: 10, phaseOffset: 0.1)
        let three = try LFO(shape: .triangle, rateHz: 3, phaseOffset: 0.1)
        let host = try makeHost(fast)
        host.reduceFlashing = true
        var crossings = 0
        var previous: Double?
        for index in 0...120 {
            let elapsed = UInt64(index) * Self.frame
            apply(host, at: Self.origin + elapsed)
            let glow = Double(host.effectiveGlow.intensity)
            XCTAssertEqual(glow, three.value(elapsedNanoseconds: elapsed), accuracy: 1e-6, "frame \(index) runs at 3 Hz")
            if let previous, previous < 0.5, glow >= 0.5 { crossings += 1 }
            previous = glow
        }
        XCTAssertEqual(crossings, 6, "3 cycles per second for 2 s")
    }

    func testSceneCarryWritesLFOsBackUnchanged() throws {
        let entry = SceneLFOEntry(fields: ["shape": .string("sine"), "rate": .double(0.5), "note": .string("kept")])
        var carry = SceneAutosaveFixtures.carry
        carry.lfos = [entry]
        let document = SceneAutosaveCapture.document(SceneAutosaveFixtures.inputs(), carry: carry, liveBindings: nil).document
        XCTAssertEqual(document.lfos, [entry])
        XCTAssertEqual(document.lfoOscillators, [try LFO(shape: .sine, rateHz: 0.5)])
        let plain = SceneAutosaveCapture.document(SceneAutosaveFixtures.inputs(), carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertNil(plain.lfos, "a scene without oscillators stays without the field")
    }

    func testSyncedLFOFollowsTapTempo() throws {
        let lfo = try LFO(shape: .sine, rateHz: 0.25, sync: LFOSync(beatsPerCycle: 1))
        let host = try makeHost(lfo)
        let tempo = TempoCoordinator(clock: TempoCoordinator.syntheticClock(stepMilliseconds: 500), announce: { (_: String) -> Void in })
        host.lfoTempoBPM = { [weak tempo] () -> Double? in tempo?.snapshot.lfoTempoBPM }   // as AppCoordinator.connectLFOs
        for _ in 0..<4 { tempo.tap() }
        XCTAssertEqual(tempo.snapshot.origin, .manual)
        XCTAssertEqual(try XCTUnwrap(tempo.snapshot.bpm), 120, accuracy: 1e-9)
        var glow: [Double] = []
        for index in 0...60 {   // 1 s at 60 fps: two 0.5 s cycles
            let elapsed = UInt64(index) * Self.frame
            apply(host, at: Self.origin + elapsed)
            glow.append(Double(host.effectiveGlow.intensity))
            XCTAssertEqual(glow[index], lfo.value(elapsedNanoseconds: elapsed, tempoBPM: 120), accuracy: 1e-6, "frame \(index) at 2 Hz")
        }
        XCTAssertEqual(glow[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(glow[30], glow[0], accuracy: 1e-5, "0.5 s later the cycle repeats")
        XCTAssertEqual(lfo.value(elapsedNanoseconds: Self.second / 8, tempoBPM: 120), 1, accuracy: 1e-9, "peak at 0.125 s")

        tempo.reset()   // no estimate: the stored 0.25 Hz from the reached phase
        XCTAssertNil(tempo.snapshot.lfoTempoBPM)
        let resetTime = Self.origin + 61 * Self.frame
        let reached: Double = 2 * Double(61 * Self.frame) / 1e9
        var previous: Double = glow[60]
        for index in 61...120 {
            let time = Self.origin + UInt64(index) * Self.frame
            apply(host, at: time)
            let value = Double(host.effectiveGlow.intensity)
            let cycles: Double = reached + 0.25 * Double(time - resetTime) / 1e9
            XCTAssertEqual(value, lfo.value(atPhase: cycles - cycles.rounded(.down)), accuracy: 1e-6, "frame \(index) at 0.25 Hz")
            XCTAssertLessThanOrEqual(abs(value - previous), 2 * Double.pi * 0.5 * 2 / 60 + 1e-6, "no jump at frame \(index)")
            previous = value
        }
    }

    func testSampleAndHoldBindingHoldsItsLevelsOnTheGlow() throws {
        let lfo = try LFO(shape: .sampleHold, rateHz: 2, seed: 2_026)   // 0.5 s steps
        let host = try makeHost(lfo)
        var held: [Int64: Double] = [:]
        for index in 0...120 {   // 2 s at 60 fps: steps 0…4
            let elapsed = UInt64(index) * Self.frame
            apply(host, at: Self.origin + elapsed)
            let glow = Double(host.effectiveGlow.intensity)
            let step: Int64 = lfo.cycle(elapsedNanoseconds: elapsed, rateHz: 2).step
            XCTAssertEqual(glow, SteppedRandom.level(seed: 2_026, step: step), accuracy: 1e-6, "frame \(index): the seeded level")
            if let level = held[step] { XCTAssertEqual(glow, level, "frame \(index) holds step \(step)") } else { held[step] = glow }
        }
        XCTAssertEqual(held.count, 5)
        XCTAssertGreaterThan(Set(held.values).count, 1, "the level changes between steps")
    }
}
