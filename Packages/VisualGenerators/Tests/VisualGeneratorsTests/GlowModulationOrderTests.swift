// GlowModulationOrderTests.swift — MOD-011-T05: two bindings on the glow intensity combine in the documented
// order on the real visual catalog, and ACC-012 applies last (contract mix-order O1 steps 2 to 4; MOD-011-S4).
import FlashSafety
import ParameterGraph
import VisualEffects
import VisualParameters
import XCTest

final class GlowModulationOrderTests: XCTestCase {
    static let intensity: ParameterID = VisualParameterIDs.bloomIntensity
    /// band 0 → 0.2…0.8, replace
    static let audioReplace = AudioFeatureBinding(source: .band(0), target: intensity, outputStart: 0.2, outputEnd: 0.8, mixMode: .replace)
    /// LFO 0 → 0…0.3, add
    static let lfoAdd = AudioFeatureBinding(source: .lfo(0), target: intensity, outputStart: 0, outputEnd: 0.3, mixMode: .add)
    /// band 1 → 0.5…1, multiply
    static let audioMultiply = AudioFeatureBinding(source: .band(1), target: intensity, outputStart: 0.5, outputEnd: 1, mixMode: .multiply)

    static func clamp(_ preset: SensorySafetyPreset) -> SafetyClamp {
        SafetyClamp(profile: SensorySafetyProfile(preset: preset), reduceFlashingSetting: false)
    }

    func modulator(_ layers: [AudioFeatureBinding], bands: [Float], lfo: Double) throws -> AudioFeatureModulator {
        let modulator = AudioFeatureModulator(registry: try VisualParameterCatalog.makeRegistry())
        for layer in layers { try modulator.addLayer(layer) }
        let lfos: [Double] = [lfo]
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            lfos.withUnsafeBufferPointer { (l: UnsafeBufferPointer<Double>) -> Void in
                modulator.advance(frame: AudioFeatureFrame(bands: b, lfos: l), timeNanoseconds: 1_000)
            }
        }
        return modulator
    }

    func testTwoBindingsThenSafetyClampLast() throws {
        let base = BloomParameters(enabled: true, intensity: 0.1)
        // Layers: replace 0.5, then + 0.3 = 0.8 (band 0 = 0.5, LFO = 1).
        let m = try modulator([Self.audioReplace, Self.lfoAdd], bands: [0.5, 0], lfo: 1)
        let rows: [(SensorySafetyPreset, Float)] = [
            (.standard, 0.8),    // no ACC-012 change
            (.reduced, 0.45),    // 0.1 + (0.8 − 0.1) × 0.5 = 0.45, under the cap 0.5
            (.strict, 0.25),     // 0.1 + 0.7 × 0.25 = 0.275, then the cap 0.25 × 1 wins
        ]
        for (preset, expected) in rows {
            let glow = GlowModulationOrder.resolve(base: base, modulator: m, clamp: Self.clamp(preset))
            XCTAssertEqual(glow.intensity, expected, accuracy: 1e-6, "\(preset)")
            XCTAssertEqual(glow.radius, base.radius, "only the intensity is modulated")
        }
    }

    func testListOrderAndIntermediateClampOnTheGlow() throws {
        let base = BloomParameters(enabled: true, intensity: 0.9)
        // add then multiply: 0.9 + 0.3 = 1.2 → 1 (the intensity's maximum) → × 0.5 = 0.5
        let addFirst = try modulator([Self.lfoAdd, Self.audioMultiply], bands: [0, 0], lfo: 1)
        XCTAssertEqual(GlowModulationOrder.resolve(base: base, modulator: addFirst, clamp: Self.clamp(.standard)).intensity, 0.5, accuracy: 1e-6)
        // multiply then add: 0.9 × 0.5 = 0.45 → + 0.3 = 0.75
        let multiplyFirst = try modulator([Self.audioMultiply, Self.lfoAdd], bands: [0, 0], lfo: 1)
        XCTAssertEqual(GlowModulationOrder.resolve(base: base, modulator: multiplyFirst, clamp: Self.clamp(.standard)).intensity, 0.75, accuracy: 1e-6)
    }

    func testUnboundIsTheCapOnly() throws {
        let base = BloomParameters(enabled: true, intensity: 0.7)
        let none = try modulator([], bands: [], lfo: 0)
        XCTAssertEqual(GlowModulationOrder.resolve(base: base, modulator: none, clamp: Self.clamp(.standard)), base, "Standard: bit identity")
        XCTAssertEqual(GlowModulationOrder.resolve(base: base, modulator: nil, clamp: Self.clamp(.reduced)).intensity, 0.5)
    }
}
