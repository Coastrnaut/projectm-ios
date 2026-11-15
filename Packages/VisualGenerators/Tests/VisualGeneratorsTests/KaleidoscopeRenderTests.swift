// KaleidoscopeRenderTests.swift — VIS-014-T06 (VIS-014-R2 to R6; S1, S2; research VIS-014-D4, D5): the roadmap
// acceptance "Wedge count changes output symmetry without visible seams", measured on frames the real Metal pipeline
// drew (rgba16Float, after 12 frames of a fixture band timeline on an injected 60 Hz clock, so the pattern has turned).
// Symmetry: each pixel inside the inscribed circle is compared with the bilinear sample of its image under a rotation by
// 2π/N and a mirror across a wedge axis; the other wedge count's rotation must not map the frame onto itself. Seams:
// across every wedge boundary and centre line, the two sides and the boundary pixel against its neighbours' mean differ
// no more than neighbouring pixels inside a wedge. Plus GPU vs the CPU fold. Without a Metal device the tests skip.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class KaleidoscopeRenderTests: XCTestCase {
    private static let frames = 12

    private static func bands(frame f: Int) -> [Float] {
        (0..<64).map { (k: Int) -> Float in
            let slope: Float = 1 - Float(k) / 64
            let pulse: Float = (f / 4) % 2 == 0 ? 1 : 0.4
            return slope * pulse
        }
    }

    private struct Frame {
        let image: PixelImage
        let rotation: Float
        let generator: NoiseFieldGenerator

        /// Bilinear sample of the green channel at continuous pixel position (u, v) (pixel centres at i + 0.5).
        func sample(_ u: Float, _ v: Float) -> Float {
            let fx: Float = min(max(u - 0.5, 0), Float(image.width - 1)), fy: Float = min(max(v - 0.5, 0), Float(image.height - 1))
            let x0: Int = min(Int(fx), image.width - 2), y0: Int = min(Int(fy), image.height - 2)
            let tx: Float = fx - Float(x0), ty: Float = fy - Float(y0)
            let a: Float = image[x0, y0].y, b: Float = image[x0 + 1, y0].y
            let c: Float = image[x0, y0 + 1].y, d: Float = image[x0 + 1, y0 + 1].y
            return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty
        }

        /// The sample at polar (radius in pixels, angle) about the centre, in the shader's frame (y down).
        func polar(_ r: Float, _ angle: Float) -> Float {
            sample(0.5 * Float(image.width) + r * cos(angle), 0.5 * Float(image.height) + r * sin(angle))
        }
    }

    private func render(_ rig: RenderRig, _ configuration: NoiseFieldConfiguration, width: Int, height: Int) throws -> Frame {
        let format: MTLPixelFormat = .rgba16Float
        let generator = try rig.build { try NoiseFieldGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for f in 0..<Self.frames {
            let context = VisualFrameContext(timeNanoseconds: UInt64(f) * 1_000_000_000 / 60, frameDuration: 1.0 / 60, reduceFlashing: false)
            let drawn: Bool = Self.bands(frame: f).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: texture, commandBuffer: commands, bands: b, context: context)
            }
            XCTAssertTrue(drawn)
        }
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        let image: PixelImage = rig.decode(RenderRig.bytes(of: buffer), width: width, height: height, format: format)
        return Frame(image: image, rotation: Float(generator.drive.rotation), generator: generator)
    }

    /// Mean |I(p) − I(T p)| over pixels with 0.08 ≤ r ≤ 0.45 of the shorter side, T given in polar form.
    private func meanError(_ frame: Frame, _ transform: (Float) -> Float) -> Float {
        let w: Int = frame.image.width, h: Int = frame.image.height
        let short = Float(min(w, h))
        var sum: Float = 0
        var count = 0
        for y in 0..<h {
            for x in 0..<w {
                let dx: Float = Float(x) + 0.5 - 0.5 * Float(w), dy: Float = Float(y) + 0.5 - 0.5 * Float(h)
                let r: Float = (dx * dx + dy * dy).squareRoot()
                guard r >= 0.08 * short, r <= 0.45 * short else { continue }
                let mapped: Float = frame.polar(r, transform(atan2(dy, dx)))
                sum += abs(frame.image[x, y].y - mapped)
                count += 1
            }
        }
        return sum / Float(max(count, 1))
    }

    private static func configuration(wedges: Int) -> NoiseFieldConfiguration {
        NoiseFieldConfiguration(frequency: 2, octaves: 1, seed: 1301, palette: .mono, wedges: wedges)
    }

    func testWedgeCountSetsTheRotationAndMirrorSymmetry() throws {
        let rig = try RenderRig()
        var report: [String] = ["VIS-014 symmetry (mean |Δ| of linear green, 128 × 128):"]
        for (n, other) in [(5, 6), (6, 5)] {
            let frame = try render(rig, Self.configuration(wedges: n), width: 128, height: 128)
            XCTAssertNotEqual(frame.rotation, 0, "the pattern has turned")
            let step: Float = 2 * Float.pi / Float(n)
            let rotation: Float = meanError(frame) { (a: Float) -> Float in a + step }
            let axis: Float = frame.rotation + step / 2   // a wedge's centre line
            let mirror: Float = meanError(frame) { (a: Float) -> Float in 2 * axis - a }
            let boundaryMirror: Float = meanError(frame) { (a: Float) -> Float in 2 * frame.rotation - a }
            let wrong: Float = meanError(frame) { (a: Float) -> Float in a + 2 * Float.pi / Float(other) }
            report.append("N \(n): rotation \(rotation), mirror \(mirror) / \(boundaryMirror), \(other)-fold rotation \(wrong)")
            XCTAssertLessThanOrEqual(rotation, 1.0 / 255, "N \(n): 2π/N rotation")
            XCTAssertLessThanOrEqual(mirror, 1.0 / 255, "N \(n): mirror across a wedge centre line")
            XCTAssertLessThanOrEqual(boundaryMirror, 1.0 / 255, "N \(n): mirror across a wedge boundary")
            XCTAssertGreaterThanOrEqual(wrong, 4 * max(rotation, 1.0 / 255), "N \(n): the \(other)-fold rotation is not a symmetry")
        }
        print(report.joined(separator: "\n"))
    }

    /// Means over every boundary and centre line α_k = rotation + k·π/N and radii 0.2…0.45 of the shorter side.
    private func seams(_ frame: Frame, wedges n: Int) -> (side: Float, centre: Float, interior: Float) {
        let short = Float(min(frame.image.width, frame.image.height))
        var side: Float = 0, centre: Float = 0, interior: Float = 0
        var count: Float = 0
        for k in 0..<(2 * n) {
            let alpha: Float = frame.rotation + Float(k) * Float.pi / Float(n)
            let inside: Float = alpha + Float.pi / Float(2 * n)
            var r: Float = 0.2 * short
            while r <= 0.45 * short {
                let delta: Float = 1.5 / r
                let plus: Float = frame.polar(r, alpha + delta), minus: Float = frame.polar(r, alpha - delta)
                side += abs(plus - minus)
                centre += abs(frame.polar(r, alpha) - 0.5 * (plus + minus))
                interior += abs(frame.polar(r, inside + delta) - frame.polar(r, inside - delta))
                count += 1
                r += 2
            }
        }
        return (side / count, centre / count, interior / count)
    }

    func testNoSeamAtAnyWedgeBoundary() throws {
        let rig = try RenderRig()
        var report: [String] = ["VIS-014 seams (mean |Δ| across boundaries vs inside wedges):"]
        for (n, w, h) in [(3, 128, 128), (8, 128, 128), (7, 160, 96)] {
            let frame = try render(rig, NoiseFieldConfiguration(frequency: 4, octaves: 3, seed: 1301, palette: .mono, wedges: n), width: w, height: h)
            let s = seams(frame, wedges: n)
            report.append("N \(n) \(w)×\(h): side \(s.side), centre \(s.centre), interior \(s.interior)")
            XCTAssertGreaterThan(s.interior, 0, "N \(n): the field is not flat")
            XCTAssertLessThanOrEqual(s.side, s.interior, "N \(n) \(w)×\(h): no step across a boundary")
            XCTAssertLessThanOrEqual(s.centre, s.interior, "N \(n) \(w)×\(h): no line on a boundary")
        }
        print(report.joined(separator: "\n"))
    }

    func testTheGPUFoldAgreesWithTheCPUMirrorAndChangesThePicture() throws {
        let rig = try RenderRig()
        let c = NoiseFieldConfiguration.kaleidoscope(wedges: 7, palette: .ice)
        let frame = try render(rig, c, width: 64, height: 64)
        let g = frame.generator
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in c.palette.color(bar: k, of: 16).clamped }
        let lit: Float = Float(g.drive.brightness) * g.lastGain
        let fold = KaleidoscopeFold(wedges: 7, rotation: frame.rotation)
        var worst: Float = 0
        for (x, y) in [(3, 5), (20, 40), (32, 32), (50, 10), (60, 60), (8, 57)] {
            let q: SIMD2<Float> = NoiseFieldFlashAreas.foldedDomainPoint(SIMD2(Float(x) + 0.5, Float(y) + 0.5), width: 64, height: 64,
                                                                         scale: Float(c.frequency), phase: Float(g.drive.phase), fold: fold)
            let n: Float = SeededNoise.warped(q, octaves: c.octaves, lacunarity: NoiseFieldConfiguration.lacunarity,
                                              gain: NoiseFieldConfiguration.gain, seed: UInt32(c.seed), warpAmount: Float(g.drive.warp),
                                              warpFrequency: 1)
            let base: LinearColor = stops.withUnsafeBufferPointer { (p: UnsafeBufferPointer<LinearColor>) -> LinearColor in
                NoiseFieldFlashAreas.paletteColor(n, stops: p.baseAddress!)
            }
            let s: Float = (0.25 + 0.75 * n) * lit
            let px: Pixel = frame.image[x, y]
            worst = max(worst, abs(px.x - base.red * s), abs(px.y - base.green * s), abs(px.z - base.blue * s))
        }
        XCTAssertLessThan(worst, 0.02, "GPU vs CPU fold")
        let plain = try render(rig, NoiseFieldConfiguration(palette: .ice), width: 64, height: 64)
        var differing = 0
        for i in 0..<plain.image.pixels.count where abs(plain.image.pixels[i].y - frame.image.pixels[i].y) > 0.01 { differing += 1 }
        XCTAssertGreaterThan(differing, plain.image.pixels.count / 4, "the fold changes the picture")
    }
}
#endif
