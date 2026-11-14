// LFOBindingAppTests.swift — MOD-007-T09 (US3; MOD-007-R5, R6, R9, S3, S5): in the app, a binding from a scene
// oscillator (`audio.lfo.0`) drives the glow intensity along the closed-form waveform through `NativeSpectrumHost`'s
// frame evaluation, and Reduce flashing caps a fast oscillator at 3 Hz. Deterministic: frame times are passed in.
// Needs a Metal device (the simulator renders with the host GPU); skips without one. Also: the scene carry writes the
// stored `lfos` list back unchanged.
import Foundation
import Metal
import ParameterGraph
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
}
