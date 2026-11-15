// SHD-006-T06, T07, T08 (US1-US3; SHD-006-R2, R3, R4, R6; S1-S3): on the GPU, a fixed seed gives a stable reference
// texture — two renders are byte-identical, a new run matches the stored exact digest of this GPU class, the tolerant
// golden holds on any GPU — different seeds differ, the GPU matches the CPU reference, more octaves add detail, and
// the preview renderer returns the same picture as opaque sRGB. 64 × 64 pictures; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import ParameterGraph
@testable import ProceduralMaterials
import XCTest

final class MaterialNoiseTests: XCTestCase {
    private static let side = 64

    /// A representative setting: name, variant, and parameter overrides.
    private struct Setting {
        let name: String
        let variant: String?
        let values: [String: ParameterValue]
    }

    /// Three representative settings (defaults; everything raised; the Low cost variant with a seed).
    private static let settings: [Setting] = [
        Setting(name: "defaults", variant: nil, values: [:]),
        Setting(name: "detailed", variant: nil,
                values: ["seed": .integer(4242), "octaves": .integer(8), "lacunarity": .continuous(2.5), "gain": .continuous(0.6),
                         "warpAmount": .continuous(2), "warpFrequency": .continuous(1.5)]),
        Setting(name: "lite", variant: "noiseFlowLite", values: ["seed": .integer(7), "octaves": .integer(3)]),
    ]

    /// SHD-006-S1: FNV-1a 64 of the raw half-float readback, per GPU class (`MTLDevice.name`), in `settings` order.
    /// Recorded 2026-11-14 on the build Mac's host GPU ("Apple M5 Max") and on the iOS 27.2 simulator of the same Mac.
    private static let digests: [String: [UInt64]] = [
        "Apple M5 Max": [0xAA38_5390_08A9_C248, 0xF8B5_9524_8754_462B, 0x94FE_4936_FF98_C69D],
    ]

    /// Mean RGB, peak RGB, pixels (32,32), (8,8), (56,16), (16,56) — SHD-001's signature, phase 0. ±0.02 on any GPU.
    /// Recorded 2026-11-14 on the host GPU.
    private static let golden: [String: [Float]] = [
        "defaults": [0.0370, 0.1295, 0.1665, 0.0532, 0.1860, 0.2393, 0.0298, 0.1041, 0.1339,
                     0.0355, 0.1243, 0.1598, 0.0341, 0.1195, 0.1537, 0.0325, 0.1139, 0.1464],
        "detailed": [0.0367, 0.1285, 0.1652, 0.0515, 0.1804, 0.2319, 0.0327, 0.1145, 0.1472,
                     0.0388, 0.1357, 0.1746, 0.0399, 0.1395, 0.1793, 0.0355, 0.1243, 0.1598],
        "lite": [0.0378, 0.1322, 0.1699, 0.0550, 0.1926, 0.2476, 0.0381, 0.1332, 0.1713,
                 0.0388, 0.1360, 0.1748, 0.0369, 0.1290, 0.1659, 0.0420, 0.1471, 0.1891],
    ]

    private func layer(_ setting: Setting) throws -> ProceduralMaterialLayer {
        let layer = ProceduralMaterialLayer(ProceduralMaterialCatalog.definition(.noiseFlow), variant: setting.variant)
        for (name, value) in setting.values { try layer.set(value, for: layer.definition.parameterID(name)) }
        return layer
    }

    private func render(_ setting: Setting, renderer: MaterialPreviewRenderer) throws -> [UInt16] {
        try renderer.renderHalf(try layer(setting), width: Self.side, height: Self.side)
    }

    private func renderer() throws -> MaterialPreviewRenderer {
        guard let renderer = MaterialPreviewRenderer.makeDefault() else {
            throw XCTSkip("No Metal device in this environment; NoiseTextureReferenceTests cover the CPU reference.")
        }
        return renderer
    }

    static func fnv1a(_ halves: [UInt16]) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for h in halves {
            for byte in [UInt8(h & 0xFF), UInt8(h >> 8)] {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        return hash
    }

    private func pixels(_ halves: [UInt16]) -> [Pixel] {
        stride(from: 0, to: halves.count, by: 4).map { (i: Int) -> Pixel in
            Pixel(MaterialGPURig.half(halves[i]), MaterialGPURig.half(halves[i + 1]), MaterialGPURig.half(halves[i + 2]),
                  MaterialGPURig.half(halves[i + 3]))
        }
    }

    private func signature(_ p: [Pixel]) -> [Float] {
        let mean = p.reduce(Pixel.zero, +) / Float(p.count)
        let peak = p.reduce(Pixel.zero) { (m: Pixel, q: Pixel) -> Pixel in pointwiseMax(m, q) }
        var s: [Float] = [mean.x, mean.y, mean.z, peak.x, peak.y, peak.z]
        for (x, y) in [(32, 32), (8, 8), (56, 16), (16, 56)] {
            let q = p[y * Self.side + x]
            s += [q.x, q.y, q.z]
        }
        return s
    }

    private func text(_ values: [Float]) -> String {
        values.map { (v: Float) -> String in String(format: "%.4f", v) }.joined(separator: ", ")
    }

    // MARK: - S1 the acceptance

    /// Two renders of each setting — the same layer twice and a second layer — are byte-identical.
    func testAFixedSeedRendersBitIdentically() throws {
        let renderer = try renderer()
        for setting in Self.settings {
            let layer = try layer(setting)
            let first = try renderer.renderHalf(layer, width: Self.side, height: Self.side)
            let again = try renderer.renderHalf(layer, width: Self.side, height: Self.side)
            let other = try render(setting, renderer: renderer)
            XCTAssertEqual(first, again, setting.name)
            XCTAssertEqual(first, other, setting.name)
            XCTAssertEqual(invalidPixelCount(pixels(first)), 0, setting.name)
        }
    }

    /// A new run matches the stored exact digest on the same GPU class; another class has no reference (skipped).
    func testExactReferenceDigestOnThisGPUClass() throws {
        let renderer = try renderer()
        let computed: [UInt64] = try Self.settings.map { (s: Setting) -> UInt64 in Self.fnv1a(try render(s, renderer: renderer)) }
        let listing = computed.map { (d: UInt64) -> String in String(format: "0x%016llX", d) }.joined(separator: ", ")
        let name: String = renderer.device.name
        guard let expected = Self.digests[name] else {
            throw XCTSkip("No exact reference for GPU class \"\(name)\" (digests [\(listing)]); the tolerant golden applies.")
        }
        XCTAssertEqual(computed, expected, "\(name): [\(listing)]")
    }

    /// The tolerant golden signature of each setting (any GPU).
    func testGoldenSignatures() throws {
        let renderer = try renderer()
        for setting in Self.settings {
            let s = signature(pixels(try render(setting, renderer: renderer)))
            guard let expected = Self.golden[setting.name] else {
                XCTFail("no golden for \(setting.name): [\(text(s))]")
                continue
            }
            for (i, (e, v)) in zip(expected, s).enumerated() {
                XCTAssertEqual(v, e, accuracy: 0.02, "\(setting.name) value \(i): [\(text(s))]")
            }
        }
    }

    // MARK: - S2, S3

    func testDifferentSeedsDiffer() throws {
        let renderer = try renderer()
        let a = pixels(try render(Setting(name: "a", variant: nil, values: ["seed": .integer(1)]), renderer: renderer))
        let b = pixels(try render(Setting(name: "b", variant: nil, values: ["seed": .integer(2)]), renderer: renderer))
        let differing: Int = zip(a, b).filter { (p: (Pixel, Pixel)) -> Bool in abs(p.0.y - p.1.y) > 1.0 / 255 }.count
        XCTAssertGreaterThan(Double(differing) / Double(a.count), 0.25)
    }

    /// The GPU picture equals the CPU reference: with a white tint and brightness 1, colour = 0.25 + 0.75 n.
    func testGPUMatchesTheCPUReference() throws {
        let renderer = try renderer()
        for setting in Self.settings {
            var values = setting.values
            values["tint"] = .color(ParameterColor(red: 1, green: 1, blue: 1))
            values["brightness"] = .continuous(1)
            let layer = try layer(Setting(name: setting.name, variant: setting.variant, values: values))
            let gpu = pixels(try renderer.renderHalf(layer, width: Self.side, height: Self.side))
            let settings = NoiseTextureSettings(values: layer.parameters)
            let cpu = NoiseTextureReference.field(width: Self.side, height: Self.side, settings: settings, lite: setting.variant != nil)
            var worst: Float = 0
            for (g, n) in zip(gpu, cpu) { worst = max(worst, abs(g.x - (0.25 + 0.75 * n))) }
            XCTAssertLessThanOrEqual(worst, 2.0 / 255, setting.name)
        }
    }

    /// S3 on the GPU: octaves 1 → 2 → 4 → 8 strictly add high-frequency energy (no warp).
    func testMoreOctavesAddDetailOnTheGPU() throws {
        let renderer = try renderer()
        var energies: [Double] = []
        for octaves in [1, 2, 4, 8] {
            let p = pixels(try render(Setting(name: "o", variant: nil,
                                              values: ["octaves": .integer(octaves), "warpAmount": .continuous(0)]), renderer: renderer))
            let green: [Float] = p.map { (q: Pixel) -> Float in q.y }
            energies.append(NoiseTextureReference.highFrequencyEnergy(green, width: Self.side, height: Self.side))
        }
        for i in 1..<energies.count { XCTAssertGreaterThan(energies[i], energies[i - 1], "\(energies)") }
    }

    // MARK: - The preview (R6)

    func testPreviewIsTheSamePictureAsOpaqueSRGB() throws {
        let renderer = try renderer()
        let layer = try layer(Self.settings[0])
        let image = try renderer.render(layer, width: Self.side, height: Self.side)
        XCTAssertEqual(image.width, Self.side)
        XCTAssertEqual(image.height, Self.side)
        XCTAssertEqual(image.rgba.count, Self.side * Self.side * 4)
        let linear = pixels(try renderer.renderHalf(layer, width: Self.side, height: Self.side))[32 * Self.side + 32]
        let shown = image.pixel(x: 32, y: 32)
        XCTAssertEqual(shown.a, 255)
        let expected: UInt8 = UInt8((FrameColorConversionMirror.srgb(linear.y) * 255).rounded())
        XCTAssertEqual(Int(shown.g), Int(expected), accuracy: 1)
    }
}

/// The sRGB transfer (the test's own copy, so the check does not reuse the code under test).
private enum FrameColorConversionMirror {
    static func srgb(_ c: Float) -> Float {
        let v: Float = min(max(c, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * powf(v, 1 / 2.4) - 0.055
    }
}
#endif
