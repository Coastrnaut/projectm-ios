// AudioFeatureModulatorTests.swift — MOD-002-T04: a band level drives a test opacity and unbind
// restores manual control (roadmap acceptance; MOD-002-R5, R7 to R9, R13; contract C3, C4).
// Deterministic: frames and timestamps are passed in; no clock, no sleep.
import Foundation
import ParameterGraph
import XCTest

final class AudioFeatureModulatorTests: XCTestCase {
    static let opacity: ParameterID = "test.layer.opacity"
    static let count: ParameterID = "test.layer.count"
    static let group = ParameterGroup(id: "test.layer", displayName: "Layer")
    static let frame: UInt64 = 16_666_667   // 1/60 s in nanoseconds

    static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: opacity, displayName: "Opacity", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.25), modulation: .continuousDefault),
            ParameterDescriptor(id: count, displayName: "Count", group: group, unit: .count,
                                kind: .integer(minimum: 0, maximum: 10, defaultValue: 4, step: 2), modulation: .continuousDefault),
        ])
    }

    private func advance(_ modulator: AudioFeatureModulator, band: Float, at time: UInt64) {
        let bands: [Float] = [band]
        bands.withUnsafeBufferPointer { modulator.advance(frame: AudioFeatureFrame(bands: $0), timeNanoseconds: time) }
    }

    private func binding(_ target: ParameterID = opacity, inputMinimum: Double = 0, inputMaximum: Double = 1,
                         output: (Double, Double) = (0, 1), mixMode: ModulationMixMode = .replace,
                         envelope: AudioFeatureEnvelope = .none) -> AudioFeatureBinding {
        AudioFeatureBinding(source: .band(0), target: target, inputMinimum: inputMinimum, inputMaximum: inputMaximum,
                            outputStart: output.0, outputEnd: output.1, mixMode: mixMode, envelope: envelope)
    }

    // (a) The roadmap acceptance.
    func testBandLevelDrivesTestOpacityAndUnbindRestoresManualControl() throws {
        let registry = try Self.registry()
        let store = ParameterStore(registry: registry)
        let modulator = AudioFeatureModulator(registry: registry)
        try modulator.bind(binding())
        var time: UInt64 = 1_000
        for level: Float in [0, 0.5, 1] {
            advance(modulator, band: level, at: time)
            time += Self.frame
            XCTAssertEqual(modulator.value(for: Self.opacity, in: store), .continuous(Double(level)))
        }
        XCTAssertEqual(store.double(Self.opacity), 0.25, "modulation never writes the manual value")
        try store.setDouble(0.8, for: Self.opacity)   // a manual change while bound
        XCTAssertEqual(modulator.value(for: Self.opacity, in: store), .continuous(1))
        XCTAssertTrue(modulator.unbind(Self.opacity))
        XCTAssertEqual(modulator.value(for: Self.opacity, in: store), .continuous(0.8), "unbind restores the manual value")
        XCTAssertFalse(modulator.isBound(Self.opacity))
        XCTAssertFalse(modulator.unbind(Self.opacity), "unbinding again has no effect")
        XCTAssertFalse(modulator.hasBindings)
    }

    // ANL-010-T09: a Centroid binding follows the frame's normalized centroid (ANL-010-R8).
    func testCentroidBindingFollowsTheCentroid() throws {
        let registry = try Self.registry()
        let store = ParameterStore(registry: registry)
        let modulator = AudioFeatureModulator(registry: registry)
        try modulator.bind(AudioFeatureBinding(source: .centroid, target: Self.opacity, outputStart: 0, outputEnd: 1))
        var time: UInt64 = 1_000
        let bands: [Float] = [0]
        for centroid: Float in [0.25, 0.75, 0.5] {
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                modulator.advance(frame: AudioFeatureFrame(bands: buffer, centroid: centroid), timeNanoseconds: time)
            }
            time += Self.frame
            XCTAssertEqual(modulator.value(for: Self.opacity, in: store), .continuous(Double(centroid)))
        }
    }

    // ANL-014-T08: a Loudness binding follows the frame's loudness envelope (ANL-014-R8).
    func testLoudnessBindingFollowsTheEnvelope() throws {
        let registry = try Self.registry()
        let store = ParameterStore(registry: registry)
        let modulator = AudioFeatureModulator(registry: registry)
        try modulator.bind(AudioFeatureBinding(source: .loudness, target: Self.opacity, outputStart: 0, outputEnd: 1))
        var time: UInt64 = 1_000
        let bands: [Float] = [0]
        for loudness: Float in [0.25, 0.75, 0.5] {
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                modulator.advance(frame: AudioFeatureFrame(bands: buffer, loudness: loudness), timeNanoseconds: time)
            }
            time += Self.frame
            XCTAssertEqual(modulator.value(for: Self.opacity, in: store), .continuous(Double(loudness)))
        }
    }

    // ANL-008-T07: a Mid transient binding follows the frame's mid transient value (ANL-008-R8).
    func testMidTransientBindingFollowsTheValue() throws {
        let registry = try Self.registry()
        let store = ParameterStore(registry: registry)
        let modulator = AudioFeatureModulator(registry: registry)
        try modulator.bind(AudioFeatureBinding(source: .midTransient, target: Self.opacity, outputStart: 0, outputEnd: 1))
        var time: UInt64 = 1_000
        let bands: [Float] = [0]
        for value: Float in [0.75, 0.5, 0.125] {
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                modulator.advance(frame: AudioFeatureFrame(bands: buffer, midTransient: value), timeNanoseconds: time)
            }
            time += Self.frame
            XCTAssertEqual(modulator.value(for: Self.opacity, in: store), .continuous(Double(value)))
        }
    }

    // ANL-007-T09: a Kick binding follows the frame's kick envelope (ANL-007-R11).
    func testKickBindingFollowsTheKickEnvelope() throws {
        let registry = try Self.registry()
        let store = ParameterStore(registry: registry)
        let modulator = AudioFeatureModulator(registry: registry)
        try modulator.bind(AudioFeatureBinding(source: .kick, target: Self.opacity, outputStart: 0, outputEnd: 1))
        var time: UInt64 = 1_000
        let bands: [Float] = [0]
        for envelope: Float in [1, 0.5, 0] {
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                modulator.advance(frame: AudioFeatureFrame(bands: buffer, kick: envelope), timeNanoseconds: time)
            }
            time += Self.frame
            XCTAssertEqual(modulator.value(for: Self.opacity, in: store), .continuous(Double(envelope)))
        }
    }

    // (b) Exact endpoints and an inverted output range.
    func testEndpointsAreExactAndInputIsClamped() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        try modulator.bind(binding(inputMinimum: 0.25, inputMaximum: 0.75, output: (0.9, 0.1)))
        let cases: [(Float, Double)] = [(0, 0.9), (0.25, 0.9), (0.75, 0.1), (1, 0.1)]
        for (index, (level, expected)) in cases.enumerated() {
            advance(modulator, band: level, at: UInt64(index) * Self.frame)
            XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.5), expected, "band \(level)")
        }
    }

    // (c) Add and multiply, clamped to the range.
    func testAddAndMultiplyModes() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        try modulator.bind(binding(output: (-0.2, 0.2), mixMode: .add))
        advance(modulator, band: 0, at: 0)
        XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.5), 0.3, accuracy: 1e-12)
        advance(modulator, band: 1, at: Self.frame)
        XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.5), 0.7, accuracy: 1e-12)
        XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.95), 1, "clamped to the maximum")

        try modulator.bind(binding(output: (0.5, 1), mixMode: .multiply))
        advance(modulator, band: 0, at: 2 * Self.frame)
        XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.8), 0.4)
        advance(modulator, band: 1, at: 3 * Self.frame)
        XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.8), 0.8)
        XCTAssertEqual(modulator.bindings.count, 1, "rebinding replaced the add binding")
    }

    // (d) Integer targets round, then snap like the store.
    func testIntegerTargetRoundsAndSnaps() throws {
        let registry = try Self.registry()
        let store = ParameterStore(registry: registry)
        let modulator = AudioFeatureModulator(registry: registry)
        try modulator.bind(binding(Self.count, output: (0, 10)))
        advance(modulator, band: 0.33, at: 0)   // 3.3 → 3 → nearest step 2 from 0, ties up → 4
        XCTAssertEqual(modulator.value(for: Self.count, in: store), .integer(4))
        advance(modulator, band: 1, at: Self.frame)
        XCTAssertEqual(modulator.value(for: Self.count, manual: .integer(2)), .integer(10))
    }

    // (e) Attack and release follow their time constants, identically on every run.
    func testEnvelopeFollowsTimeConstantsDeterministically() throws {
        func run() throws -> [Double] {
            let modulator = AudioFeatureModulator(registry: try Self.registry())
            try modulator.bind(binding(envelope: AudioFeatureEnvelope(attackSeconds: 0.1, releaseSeconds: 0.4)))
            var trace: [Double] = []
            var time: UInt64 = 5_000_000_000
            advance(modulator, band: 1, at: time)   // first advance: no elapsed time
            trace.append(modulator.signal(for: Self.opacity) ?? -1)
            for _ in 0..<6 { time += Self.frame; advance(modulator, band: 1, at: time); trace.append(modulator.signal(for: Self.opacity) ?? -1) }
            for _ in 0..<24 { time += Self.frame; advance(modulator, band: 0, at: time); trace.append(modulator.signal(for: Self.opacity) ?? -1) }
            return trace
        }
        let trace = try run()
        XCTAssertEqual(trace[0], 0, "a new binding starts at 0 and the first advance has no elapsed time")
        let risen = trace[6]
        XCTAssertEqual(risen, 1 - exp(-1.0), accuracy: 0.01 * (1 - exp(-1.0)), "one attack constant")
        let fallen = trace[30]
        XCTAssertEqual(fallen, risen * exp(-1.0), accuracy: 0.01 * risen * exp(-1.0), "one release constant")
        XCTAssertEqual(try run(), trace, "bit-identical on a second run")
    }

    // (f) The clock: repeated or backwards time adds nothing; long gaps are capped.
    func testClockIgnoresRepeatedOrBackwardsTimeAndCapsGaps() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        try modulator.bind(binding(envelope: AudioFeatureEnvelope(attackSeconds: 1, releaseSeconds: 1)))
        advance(modulator, band: 1, at: 10_000_000_000)
        XCTAssertEqual(modulator.signal(for: Self.opacity), 0)
        advance(modulator, band: 1, at: 10_000_000_000)
        advance(modulator, band: 1, at: 9_000_000_000)
        XCTAssertEqual(modulator.signal(for: Self.opacity), 0, "no elapsed time")
        advance(modulator, band: 1, at: 19_000_000_000)   // 9 s after the latest time counts as 0.25 s
        XCTAssertEqual(modulator.signal(for: Self.opacity) ?? -1, 1 - exp(-0.25), accuracy: 1e-12)
    }

    // (g) Rebinding resets the envelope.
    func testRebindingRestartsTheSignal() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        let smooth = binding(envelope: AudioFeatureEnvelope(attackSeconds: 0.1, releaseSeconds: 0.1))
        try modulator.bind(smooth)
        advance(modulator, band: 1, at: 0)
        advance(modulator, band: 1, at: Self.frame)
        XCTAssertGreaterThan(modulator.signal(for: Self.opacity) ?? 0, 0)
        try modulator.bind(smooth)
        XCTAssertEqual(modulator.signal(for: Self.opacity), 0)
    }

    // (h) Inspection, and unbound targets pass the manual value through unchanged.
    func testInspectionAndUnboundPassThrough() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        XCTAssertNil(modulator.signal(for: Self.opacity))
        XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.123456789), 0.123456789)
        XCTAssertEqual(modulator.value(for: Self.count, manual: .integer(6)), .integer(6))
        let b = binding()
        try modulator.bind(b)
        XCTAssertTrue(modulator.isBound(Self.opacity))
        XCTAssertTrue(modulator.hasBindings)
        XCTAssertEqual(modulator.bindings, [b])
        XCTAssertEqual(modulator.signal(for: Self.opacity), 0)
        XCTAssertEqual(modulator.value(for: Self.count, manual: .integer(6)), .integer(6), "another target is unaffected")
        modulator.unbindAll()
        XCTAssertFalse(modulator.hasBindings)
    }
}
