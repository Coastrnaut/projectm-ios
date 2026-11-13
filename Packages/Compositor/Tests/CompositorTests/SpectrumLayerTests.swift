// CMP-001-T14 (US6: existing visuals as layers; CMP-001-S6). The circular (VIS-001) and linear
// (VIS-002) spectra as `SpectrumLayerSource`s, fed a reference band vector through the audio
// context, composited at 64 × 64 over a transparent background: every lit pixel lies inside the
// generator's own layout prediction grown by 1 pixel. GPU; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import SpectrumLayers
import VisualEffects
import VisualGenerators
import XCTest

final class SpectrumLayerTests: XCTestCase {
    private let transparent = LinearColor(red: 0, green: 0, blue: 0, alpha: 0)
    private let reference: [Float] = (0..<16).map { Float($0 + 1) / 16 }

    private func compose(_ layer: SpectrumLayerSource, rig: GPURig, bands: [Float]) throws -> [Pixel] {
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output()
        let audio = LayerAudioBuffer()
        audio.set(frame: nil, bands: bands, events: [])
        try rig.frame(compositor, into: output, time: 1, audio: audio.context)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        return try rig.read(output)
    }

    func testLinearSpectrumLayerLightsOnlyItsBars() throws {
        let rig = try GPURig()
        let generator = try LinearSpectrumGenerator(device: rig.device, pixelFormat: .rgba16Float,
                                                    configuration: LinearSpectrumConfiguration(barCount: .b16, background: transparent))
        let layer = try SpectrumLayerSource(device: rig.device, generator: generator)
        XCTAssertEqual(layer.fallback, .lastGoodFrame)
        let pixels = try compose(layer, rig: rig, bands: reference)
        var rects: [PixelRect] = []
        for k in 0..<16 {
            let r = generator.layout.rectangles(ofBar: k)
            if let bar = r.bar { rects.append(bar) }
            if let cap = r.cap { rects.append(cap) }
        }
        XCTAssertFalse(rects.isEmpty)
        var lit = 0
        for y in 0..<64 {
            for x in 0..<64 where pixels[y * 64 + x].w > 0.01 {
                lit += 1
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                XCTAssertTrue(rects.contains { px >= $0.minX - 1 && px <= $0.maxX + 1 && py >= $0.minY - 1 && py <= $0.maxY + 1 },
                              "lit pixel (\(x), \(y)) outside every predicted rectangle")
            }
        }
        XCTAssertGreaterThan(lit, 100, "the bars are drawn")
    }

    func testCircularSpectrumLayerStaysInsideItsRing() throws {
        let rig = try GPURig()
        let generator = try CircularSpectrumGenerator(device: rig.device, pixelFormat: .rgba16Float,
                                                      configuration: CircularSpectrumConfiguration(barCount: .b16, background: transparent))
        let layer = try SpectrumLayerSource(device: rig.device, generator: generator)
        let pixels = try compose(layer, rig: rig, bands: reference)
        let outer = (0..<16).map { generator.layout.bar($0).outerRadius }.max() ?? 0
        var lit = 0
        for y in 0..<64 {
            for x in 0..<64 where pixels[y * 64 + x].w > 0.01 {
                lit += 1
                let d = ((Double(x) + 0.5 - generator.layout.centerX).magnitudeSquared + (Double(y) + 0.5 - generator.layout.centerY).magnitudeSquared).squareRoot()
                XCTAssertLessThanOrEqual(d, outer + 1.5, "lit pixel (\(x), \(y)) beyond the ring")
            }
        }
        XCTAssertGreaterThan(lit, 50)
    }

    func testEmptyAudioDrawsOnlyTheBackground() throws {
        let rig = try GPURig()
        let generator = try LinearSpectrumGenerator(device: rig.device, pixelFormat: .rgba16Float,
                                                    configuration: LinearSpectrumConfiguration(barCount: .b16, background: transparent))
        let layer = try SpectrumLayerSource(device: rig.device, generator: generator)
        assertAll(try compose(layer, rig: rig, bands: []), equal: .zero, "silence: transparent")
    }

    func testGlowRunsAndBoundsTheGeneratorsFlashes() throws {
        let rig = try GPURig()
        let generator = try LinearSpectrumGenerator(device: rig.device, pixelFormat: .rgba16Float,
                                                    configuration: LinearSpectrumConfiguration(barCount: .b16, background: transparent))
        let layer = try SpectrumLayerSource(device: rig.device, generator: generator, glow: BloomParameters(enabled: true))
        XCTAssertTrue(layer.glowActive)
        XCTAssertNotNil(generator.downstreamLuminance, "the envelope bounds the glowing frame (FX-001-R10)")
        let pixels = try compose(layer, rig: rig, bands: reference)
        XCTAssertGreaterThan(pixels.filter { $0.w > 0.01 }.count, 100)
        layer.glow = BloomParameters(enabled: false)
        XCTAssertFalse(layer.glowActive)
        XCTAssertNil(generator.downstreamLuminance)
    }

    func testWrongGeneratorFormatIsRejected() throws {
        let rig = try GPURig()
        let generator = try LinearSpectrumGenerator(device: rig.device, pixelFormat: .bgra8Unorm_srgb)
        XCTAssertThrowsError(try SpectrumLayerSource(device: rig.device, generator: generator))
    }
}
#endif
