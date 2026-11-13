// SHD-001-T10, T11, T13 (US1, US2; SHD-001-R4, R5, R6, R13, R14; S1, S4, S6, S7): every material
// loads and draws a valid picture at its documented defaults, deterministically, at its extremes and
// within its golden signature. 64 × 64 pictures; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import ParameterGraph
import ProceduralMaterials
import XCTest

final class MaterialRenderTests: XCTestCase {
    private let kinds = MaterialKind.allCases
    private let music: [Float] = (0..<32).map { (i: Int) -> Float in 0.3 + 0.4 * Float(i % 5) / 4 }

    private func luminanceSpread(_ pixels: [Pixel]) -> Float {
        let l = pixels.map { (p: Pixel) -> Float in 0.2126 * p.x + 0.7152 * p.y + 0.0722 * p.z }
        return (l.max() ?? 0) - (l.min() ?? 0)
    }

    // MARK: - US1

    func testEveryMaterialLoadsAtDefaults() throws {
        let rig = try MaterialGPURig()
        for kind in kinds {
            let layer = ProceduralMaterialCatalog.makeLayer(kind)
            XCTAssertEqual(layer.layerName, kind.id)
            XCTAssertEqual(layer.fallback, .transparent)
            XCTAssertEqual(layer.parameters.values, ProceduralMaterialCatalog.definition(kind).parameters.map(\.defaultValue))
            let driver = try MaterialGPURig.Driver(rig: rig, layer: layer)
            try driver.step()
            let pixels = try driver.read()
            XCTAssertEqual(invalidPixelCount(pixels), 0, "\(kind.id): finite, opaque, premultiplied-valid")
            let mean = pixels.reduce(Pixel.zero, +) / Float(pixels.count)
            XCTAssertGreaterThan(mean.x + mean.y + mean.z, 0.01, "\(kind.id): not blank")
            XCTAssertGreaterThan(luminanceSpread(pixels), 0.005, "\(kind.id): has structure")
        }
    }

    func testEveryMaterialRendersThroughTheCompositor() throws {
        let rig = try MaterialGPURig()
        let layers: [ProceduralMaterialLayer] = kinds.map { (k: MaterialKind) -> ProceduralMaterialLayer in ProceduralMaterialCatalog.makeLayer(k) }
        let compositor = try Compositor(device: rig.device, layers: layers)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 64, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        for i in 0..<3 {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands,
                                               presentationTimeNanoseconds: UInt64(i) * MaterialGPURig.frameNanoseconds,
                                               contentScale: 2, reduceFlashing: true, audio: .empty))
            commands.commit()
            commands.waitUntilCompleted()
        }
        for i in 0..<layers.count { XCTAssertEqual(compositor.outcome(ofLayer: i), .rendered, kinds[i].id) }
        XCTAssertEqual(invalidPixelCount(try rig.read(output)), 0)
    }

    func testOddSizesAndBadBandsDraw() throws {
        let rig = try MaterialGPURig()
        for kind in kinds {
            for (w, h) in [(1, 1), (97, 13)] {
                let driver = try MaterialGPURig.Driver(rig: rig, layer: ProceduralMaterialCatalog.makeLayer(kind), width: w, height: h)
                try driver.step(bands: [.nan, -1, 5, .infinity])
                try driver.step(bands: [.nan, -1, 5, .infinity])
                XCTAssertEqual(invalidPixelCount(try driver.read()), 0, "\(kind.id) at \(w) × \(h)")
            }
        }
    }

    /// S4: two layers over the same 120 frames (with music from frame 30) are bit-identical.
    func testRendersAreDeterministic() throws {
        let rig = try MaterialGPURig()
        for kind in kinds {
            let a = try MaterialGPURig.Driver(rig: rig, layer: ProceduralMaterialCatalog.makeLayer(kind))
            let b = try MaterialGPURig.Driver(rig: rig, layer: ProceduralMaterialCatalog.makeLayer(kind))
            for i in 0..<120 {
                let bands = i >= 30 ? music : []
                try a.step(bands: bands)
                try b.step(bands: bands)
                if i % 40 == 39 {
                    XCTAssertEqual(try a.read(), try b.read(), "\(kind.id) frame \(i)")
                }
            }
            XCTAssertEqual(a.layer.motion, b.layer.motion)
            XCTAssertGreaterThan(a.layer.motion.audioLevel, 0)
        }
    }

    // MARK: - US2

    func testChangedValueChangesTheNextFrame() throws {
        let rig = try MaterialGPURig()
        let layer = ProceduralMaterialCatalog.makeLayer(.tunnel)
        let driver = try MaterialGPURig.Driver(rig: rig, layer: layer)
        try driver.step()
        let before = try driver.read()
        let brightness = layer.definition.parameterID("brightness")
        XCTAssertEqual(try layer.set(.continuous(0.1), for: brightness), .continuous(0.1))
        try driver.step()
        let after = try driver.read()
        let sum = { (p: [Pixel]) -> Float in p.reduce(0) { (s: Float, q: Pixel) -> Float in s + q.x + q.y + q.z } }
        XCTAssertLessThan(sum(after), sum(before) * 0.5)
    }

    func testUpdateFromAParameterStore() throws {
        let store = ParameterStore(registry: try ProceduralMaterialCatalog.makeRegistry())
        let layer = ProceduralMaterialCatalog.makeLayer(.plasma)
        let scale = layer.definition.parameterID("scale")
        try store.setDouble(100, for: scale)
        try store.setDouble(0.5, for: ProceduralMaterialCatalog.definition(.tunnel).speedParameter)
        layer.update(from: store)
        XCTAssertEqual(layer.parameters.double(scale), 8, "the store's clamped value")
        XCTAssertEqual(layer.parameters.double(layer.definition.speedParameter), 0.12, "other materials' values do not leak")
    }

    /// S6: all minimums, then all maximums, with music at full level; every pixel valid.
    func testExtremesStayValid() throws {
        let rig = try MaterialGPURig()
        for kind in kinds {
            for useMaximum in [false, true] {
                let layer = ProceduralMaterialCatalog.makeLayer(kind)
                for d in layer.definition.parameters {
                    switch d.kind {
                    case let .continuous(minimum, maximum, _, _, _):
                        try layer.set(.continuous(useMaximum ? maximum : minimum), for: d.id)
                    case let .integer(minimum, maximum, _, _):
                        try layer.set(.integer(useMaximum ? maximum : minimum), for: d.id)
                    case .color:
                        let v = useMaximum ? 1.0 : 0.0
                        try layer.set(.color(ParameterColor(red: v, green: v, blue: v)), for: d.id)
                    default:
                        XCTFail("\(d.id)")
                    }
                }
                let driver = try MaterialGPURig.Driver(rig: rig, layer: layer)
                for _ in 0..<30 { try driver.step(bands: [1, 1, 1, 1]) }
                XCTAssertEqual(invalidPixelCount(try driver.read()), 0, "\(kind.id) at its \(useMaximum ? "maximums" : "minimums")")
            }
        }
    }

    // MARK: - S7 golden signatures

    /// Mean RGB, peak RGB (catches a blank sparse material such as the starfield), then pixels (32,32), (8,8), (56,16), (16,56), each RGB; frame 30 at 60 Hz, no music.
    /// Recorded 2026-11-13 on the Mac Studio host GPU (Apple silicon); see research SHD-001-D7.
    private static let golden: [MaterialKind: [Float]] = [
        .gradient: [0.0960, 0.0420, 0.1649, 0.1779, 0.0595, 0.2382, 0.0977, 0.0424, 0.1665,
                    0.0257, 0.0269, 0.1022, 0.1633, 0.0564, 0.2251, 0.0523, 0.0326, 0.1260],
        .plasma: [0.1774, 0.0849, 0.2852, 0.3096, 0.2820, 0.3296, 0.1548, 0.0718, 0.3049,
                  0.0975, 0.2712, 0.3164, 0.1766, 0.0544, 0.2908, 0.1570, 0.0697, 0.3037],
        .noiseFlow: [0.0360, 0.1261, 0.1621, 0.0561, 0.1964, 0.2524, 0.0285, 0.0997, 0.1281,
                     0.0290, 0.1014, 0.1304, 0.0391, 0.1368, 0.1759, 0.0443, 0.1552, 0.1995],
        .tunnel: [0.2787, 0.1476, 0.0656, 0.3398, 0.1799, 0.0800, 0.1042, 0.0552, 0.0245,
                  0.2771, 0.1467, 0.0652, 0.2996, 0.1586, 0.0705, 0.2996, 0.1586, 0.0705],
        .starfield: [0.0119, 0.0119, 0.0133, 0.6035, 0.6035, 0.6704, 0.0000, 0.0000, 0.0000,
                     0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000],
    ]
    private static let goldenTolerance: Float = 0.02

    private func signature(_ pixels: [Pixel]) -> [Float] {
        let mean = pixels.reduce(Pixel.zero, +) / Float(pixels.count)
        let peak = pixels.reduce(Pixel.zero) { (m: Pixel, p: Pixel) -> Pixel in pointwiseMax(m, p) }
        var s: [Float] = [mean.x, mean.y, mean.z, peak.x, peak.y, peak.z]
        for (x, y) in [(32, 32), (8, 8), (56, 16), (16, 56)] {
            let p = pixels[y * 64 + x]
            s += [p.x, p.y, p.z]
        }
        return s
    }

    func testGoldenSignatures() throws {
        let rig = try MaterialGPURig()
        for kind in kinds {
            let driver = try MaterialGPURig.Driver(rig: rig, layer: ProceduralMaterialCatalog.makeLayer(kind))
            for _ in 0...30 { try driver.step() }
            let s = signature(try driver.read())
            let text = s.map { (v: Float) -> String in String(format: "%.4f", v) }.joined(separator: ", ")
            guard let expected = Self.golden[kind] else {
                XCTFail("no golden signature for \(kind.id): [\(text)]")
                continue
            }
            XCTAssertEqual(expected.count, s.count)
            for (i, (e, v)) in zip(expected, s).enumerated() {
                XCTAssertEqual(v, e, accuracy: Self.goldenTolerance, "\(kind.id) signature value \(i): [\(text)]")
            }
        }
    }
}
#endif
