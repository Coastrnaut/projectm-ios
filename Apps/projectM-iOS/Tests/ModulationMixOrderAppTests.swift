// ModulationMixOrderAppTests.swift — MOD-011-T09: bindings layered on the glow intensity combine in the documented
// order in the app's native spectrum host, ACC-012 applies last, and the inspector numbers the layers
// (MOD-011-R2 to R6, R8; S4; contract mix-order O1). Deterministic: features and frame times are passed in.
// Needs a Metal device (the simulator renders with the host GPU); skips without one.
import FlashSafety
import Metal
import ParameterGraph
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ModulationMixOrderAppTests: XCTestCase {
    static let intensity: ParameterID = VisualParameterIDs.bloomIntensity
    /// band 0 → 0.2…0.8, replace
    static let audioReplace = AudioFeatureBinding(source: .band(0), target: intensity, outputStart: 0.2, outputEnd: 0.8, mixMode: .replace)
    /// kick → 0…0.3, add
    static let kickAdd = AudioFeatureBinding(source: .kick, target: intensity, outputStart: 0, outputEnd: 0.3, mixMode: .add)
    /// band 1 → 0.5…1, multiply
    static let audioMultiply = AudioFeatureBinding(source: .band(1), target: intensity, outputStart: 0.5, outputEnd: 1, mixMode: .multiply)

    private func makeHost(intensity: Float) throws -> NativeSpectrumHost {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                           glow: BloomParameters(enabled: true, intensity: intensity))
    }

    /// Band 0 = 0.5 (replace → 0.5), kick = 1 (add 0.3), band 1 = 0 (multiply × 0.5).
    private func apply(_ host: NativeSpectrumHost) {
        let bands: [Float] = [0.5, 0]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            host.applyModulation(bands: buffer, kick: 1, timeNanoseconds: 1_000_000)
        }
    }

    func testTwoBindingsOnTheGlowCombineAsDocumented() throws {
        let host = try makeHost(intensity: 0.1)
        try host.addLayer(Self.audioReplace)
        try host.addLayer(Self.kickAdd)
        apply(host)
        // 0.1 → replace 0.5 → + 0.3 = 0.8
        XCTAssertEqual(host.effectiveGlow.intensity, 0.8, accuracy: 1e-6)
        XCTAssertEqual(host.bloomParameters?.intensity ?? -1, 0.8, accuracy: 1e-6, "the bloom renders the combined value")
        XCTAssertEqual(host.glow.intensity, 0.1, "modulation never writes the base")
        // A third layer: × 0.5 → 0.4; the same layers with replace last → 0.5.
        try host.addLayer(Self.audioMultiply)
        apply(host)
        XCTAssertEqual(host.effectiveGlow.intensity, 0.4, accuracy: 1e-6)
        XCTAssertTrue(host.unbind(Self.intensity), "unbind removes every layer")
        XCTAssertEqual(host.bindings, [])
        for layer in [Self.audioMultiply, Self.kickAdd, Self.audioReplace] { try host.addLayer(layer) }
        apply(host)
        XCTAssertEqual(host.effectiveGlow.intensity, 0.5, accuracy: 1e-6, "0.1 × 0.5 + 0.3 = 0.35, then replace 0.5")
    }

    func testSafetyClampAppliesLast() throws {
        let host = try makeHost(intensity: 0.1)
        for layer in [Self.audioReplace, Self.kickAdd, Self.audioMultiply] { try host.addLayer(layer) }
        let rows: [(SensorySafetyPreset, Float)] = [
            (.standard, 0.4),    // the layers alone
            (.reduced, 0.25),    // 0.1 + (0.4 − 0.1) × 0.5 = 0.25, under the cap 0.5
            (.strict, 0.175),    // 0.1 + 0.3 × 0.25 = 0.175, under the cap 0.25
        ]
        for (preset, expected) in rows {
            let clamp = SafetyClamp(profile: SensorySafetyProfile(preset: preset), reduceFlashingSetting: false)
            AppCoordinator.applySafety(clamp, renderer: nil, native: host, compositors: [])
            apply(host)
            XCTAssertEqual(host.bloomParameters?.intensity ?? -1, expected, accuracy: 1e-6, preset.rawValue)
        }
    }

    func testInspectorNumbersTheLayers() throws {
        let host = try makeHost(intensity: 0.1)
        try host.addLayer(Self.audioReplace)
        try host.addLayer(Self.kickAdd)
        apply(host)
        let descriptor = try XCTUnwrap(ParameterInspectorCatalog.descriptor(Self.intensity))
        let manual: Double = 0.1
        let reading = try XCTUnwrap(ParameterModulationReader.reading(
            descriptor, manual: manual, bindings: host.bindings, external: nil,
            modulated: host.modulatorValue(for: Self.intensity, manual: manual), rendered: Double(host.effectiveGlow.intensity)))
        XCTAssertEqual(reading.sources.map { (s: String) -> String in String(s.prefix(3)) }, ["1. ", "2. "])
        XCTAssertTrue(reading.sources[0].hasSuffix("(replace)"), reading.sources[0])
        XCTAssertTrue(reading.sources[1].hasPrefix("2. Kick"), reading.sources[1])
        XCTAssertEqual(reading.order, ParameterModulationReader.orderNote)
        XCTAssertEqual(reading.effective, 0.8, accuracy: 1e-6)
        // One binding: unchanged (no number, no order line).
        XCTAssertTrue(host.unbind(Self.intensity))
        try host.bind(Self.audioReplace)
        let single = try XCTUnwrap(ParameterModulationReader.reading(descriptor, manual: manual, bindings: host.bindings, external: nil,
                                                                     modulated: 0.5, rendered: nil))
        XCTAssertFalse(single.sources[0].hasPrefix("1. "))
        XCTAssertNil(single.order)
    }
}
