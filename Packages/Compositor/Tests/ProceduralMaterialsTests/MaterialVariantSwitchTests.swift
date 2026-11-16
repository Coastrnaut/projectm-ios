// SHD-004-T10, T14 (US2, US3; SHD-004-R3, R4, R5; S2, S3, S4): on the GPU, each new variant draws its own
// golden picture; switching keeps every parameter value and the motion and draws the selected variant from
// the next frame without building a pipeline; a GPU without the required family (injected) draws Standard
// with a notice and keeps the selection. 64 × 64 pictures; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import ParameterGraph
import ProceduralMaterials
import ShaderParameterMetadata
import XCTest

final class MaterialVariantSwitchTests: XCTestCase {
    private let family8 = MaterialGPUCapabilities(families: [.apple7, .apple8])

    /// Mean RGB, peak RGB, then pixels (32,32), (8,8), (56,16), (16,56) — SHD-001's signature; frame 30, no music.
    /// Recorded 2026-11-14 on the Mac Studio host GPU.
    private static let golden: [String: [Float]] = [
        "plasmaDetailed": [0.1753, 0.0754, 0.2884, 0.3203, 0.2416, 0.3296, 0.1587, 0.0681, 0.3025,
                           0.1044, 0.1614, 0.3293, 0.1476, 0.0793, 0.3093, 0.1843, 0.0499, 0.2856],
        // SHD-006: re-recorded 2026-11-14 (integer seeded hash; seed 0, defaults).
        "noiseFlowLite": [0.0371, 0.1299, 0.1670, 0.0533, 0.1868, 0.2401, 0.0303, 0.1060, 0.1362,
                          0.0351, 0.1229, 0.1580, 0.0360, 0.1261, 0.1621, 0.0326, 0.1142, 0.1467],
    ]

    private static func signature(_ pixels: [Pixel]) -> [Float] {
        let mean = pixels.reduce(Pixel.zero, +) / Float(pixels.count)
        let peak = pixels.reduce(Pixel.zero) { (m: Pixel, p: Pixel) -> Pixel in pointwiseMax(m, p) }
        var s: [Float] = [mean.x, mean.y, mean.z, peak.x, peak.y, peak.z]
        for (x, y) in [(32, 32), (8, 8), (56, 16), (16, 56)] {
            let p = pixels[y * 64 + x]
            s += [p.x, p.y, p.z]
        }
        return s
    }

    private func layer(_ kind: MaterialKind, _ variant: String?, _ capabilities: MaterialGPUCapabilities = .all) -> ProceduralMaterialLayer {
        ProceduralMaterialLayer(ProceduralMaterialCatalog.definition(kind), variant: variant, capabilities: capabilities)
    }

    /// S2: each non-default variant renders valid pixels, differs from its Standard and matches its golden.
    func testEachVariantMatchesItsGolden() throws {
        let rig = try MaterialGPURig()
        for (kind, variant) in [(MaterialKind.plasma, "plasmaDetailed"), (.noiseFlow, "noiseFlowLite")] {
            let standard = try MaterialGPURig.Driver(rig: rig, layer: layer(kind, nil))
            let other = try MaterialGPURig.Driver(rig: rig, layer: layer(kind, variant))
            XCTAssertEqual(other.layer.resolution, MaterialVariantResolution(drawn: variant))
            for _ in 0...30 {
                try standard.step()
                try other.step()
            }
            let pixels = try other.read()
            XCTAssertEqual(invalidPixelCount(pixels), 0, variant)
            XCTAssertNotEqual(pixels, try standard.read(), "\(variant) differs from Standard")
            let s = Self.signature(pixels)
            let text = s.map { (v: Float) -> String in String(format: "%.4f", v) }.joined(separator: ", ")
            guard let expected = Self.golden[variant] else {
                XCTFail("no golden signature for \(variant): [\(text)]")
                continue
            }
            for (i, (e, v)) in zip(expected, s).enumerated() {
                XCTAssertEqual(v, e, accuracy: 0.02, "\(variant) signature value \(i): [\(text)]")
            }
        }
    }

    /// S3, R4: switching keeps values and motion, builds nothing, and the next frame is the selected variant's
    /// (equal to a layer that drew that variant from the start with the same values); switching back restores
    /// Standard.
    func testSwitchingKeepsValuesAndMotionAndDrawsTheSelection() throws {
        let rig = try MaterialGPURig()
        let switching = layer(.plasma, nil)
        let detailed = layer(.plasma, "plasmaDetailed")
        let standard = layer(.plasma, nil)
        let scale = switching.definition.parameterID("scale")
        for l in [switching, detailed, standard] {
            try l.set(.continuous(3), for: scale)
            try l.set(.continuous(0.8), for: l.definition.parameterID("brightness"))
        }
        let a = try MaterialGPURig.Driver(rig: rig, layer: switching)
        let b = try MaterialGPURig.Driver(rig: rig, layer: detailed)
        let c = try MaterialGPURig.Driver(rig: rig, layer: standard)
        XCTAssertEqual(switching.preparedVariants, ["plasma", "plasmaDetailed"], "prepare built every supported variant")
        let music: [Float] = [0.5, 0.5, 0.5, 0.5]
        for _ in 0..<30 { for d in [a, b, c] { try d.step(bands: music) } }
        let values = switching.parameters
        let motion = switching.motion

        switching.select(variant: "plasmaDetailed")
        XCTAssertEqual(switching.selectedVariant, "plasmaDetailed")
        XCTAssertEqual(switching.resolution, MaterialVariantResolution(drawn: "plasmaDetailed"))
        XCTAssertEqual(switching.parameters, values, "every parameter value is kept")
        XCTAssertEqual(switching.motion, motion, "the motion phase is kept")
        XCTAssertEqual(switching.preparedVariants, ["plasma", "plasmaDetailed"], "no pipeline was built by the switch")
        for d in [a, b, c] { try d.step(bands: music) }
        XCTAssertEqual(try a.read(), try b.read(), "the next frame is Detailed's")

        switching.select(variant: "plasma")
        XCTAssertNil(switching.selectedVariant, "selecting the default stores nothing")
        for d in [a, b, c] { try d.step(bands: music) }
        XCTAssertEqual(try a.read(), try c.read(), "back to Standard")
        XCTAssertEqual(switching.motion, standard.motion)
    }

    /// S4, R5: without family 9 Detailed is not built; the layer draws Standard with the notice and keeps the
    /// selection. An unknown variant does the same with its own notice; a variant without a requirement runs.
    func testUnsupportedOrUnknownVariantFallsBackToStandard() throws {
        let rig = try MaterialGPURig()
        let unsupported = layer(.plasma, "plasmaDetailed", family8)
        let unknown = layer(.plasma, "plasmaUltra", family8)
        let standard = layer(.plasma, nil, family8)
        let a = try MaterialGPURig.Driver(rig: rig, layer: unsupported)
        let b = try MaterialGPURig.Driver(rig: rig, layer: unknown)
        let c = try MaterialGPURig.Driver(rig: rig, layer: standard)
        XCTAssertEqual(unsupported.preparedVariants, ["plasma"], "an unsupported variant is never built")
        for _ in 0...30 { for d in [a, b, c] { try d.step() } }
        XCTAssertEqual(unsupported.resolution,
                       MaterialVariantResolution(drawn: "plasma", notice: .unsupported(variant: "plasmaDetailed", requires: .apple9)))
        XCTAssertEqual(unsupported.selectedVariant, "plasmaDetailed", "the stored choice is kept")
        XCTAssertEqual(unknown.resolution, MaterialVariantResolution(drawn: "plasma", notice: .unknownVariant("plasmaUltra")))
        XCTAssertEqual(unknown.selectedVariant, "plasmaUltra")
        let expected = try c.read()
        XCTAssertEqual(try a.read(), expected, "Standard's picture")
        XCTAssertEqual(try b.read(), expected, "Standard's picture")
        XCTAssertEqual(invalidPixelCount(expected), 0)

        let lite = layer(.noiseFlow, "noiseFlowLite", .none)
        let driver = try MaterialGPURig.Driver(rig: rig, layer: lite)
        try driver.step()
        XCTAssertEqual(lite.resolution, MaterialVariantResolution(drawn: "noiseFlowLite"))
        XCTAssertEqual(invalidPixelCount(try driver.read()), 0)
    }

    /// The device's own families decide when none are injected (the host GPU is an Apple GPU).
    func testCapabilitiesComeFromTheDevice() throws {
        let rig = try MaterialGPURig()
        let l = ProceduralMaterialLayer(ProceduralMaterialCatalog.definition(.plasma), variant: "plasmaDetailed")
        XCTAssertNil(l.capabilities)
        _ = try MaterialGPURig.Driver(rig: rig, layer: l)
        let gpu = try XCTUnwrap(l.capabilities)
        XCTAssertEqual(gpu, MaterialGPUCapabilities(device: rig.device))
        XCTAssertEqual(l.resolution.drawn, gpu.families.contains(.apple9) ? "plasmaDetailed" : "plasma")
        // SHD-004-T20 evidence line: which variant this device's GPU draws for Plasma Detailed.
        print("SHD004-DEVICE \(rig.device.name): apple9=\(gpu.families.contains(.apple9)) drawn=\(l.resolution.drawn)")
    }

    /// S6 (SHD-001-R9 for variants): extremes stay valid.
    func testVariantExtremesStayValid() throws {
        let rig = try MaterialGPURig()
        for (kind, variant) in [(MaterialKind.plasma, "plasmaDetailed"), (.noiseFlow, "noiseFlowLite")] {
            for useMaximum in [false, true] {
                let l = layer(kind, variant)
                for d in l.definition.parameters {
                    switch d.kind {
                    case let .continuous(minimum, maximum, _, _, _): try l.set(.continuous(useMaximum ? maximum : minimum), for: d.id)
                    case let .integer(minimum, maximum, _, _): try l.set(.integer(useMaximum ? maximum : minimum), for: d.id)
                    case .color:
                        let v = useMaximum ? 1.0 : 0.0
                        try l.set(.color(ParameterColor(red: v, green: v, blue: v)), for: d.id)
                    default: break
                    }
                }
                let driver = try MaterialGPURig.Driver(rig: rig, layer: l)
                for _ in 0..<10 { try driver.step(bands: [1, 1, 1, 1]) }
                XCTAssertEqual(invalidPixelCount(try driver.read()), 0, "\(variant) at its \(useMaximum ? "maximums" : "minimums")")
            }
        }
    }
}
#endif
