// SHD-005-T05 (US2; SHD-005-R2, R6; S1, S2, S3): the Gradient Field draws a multi-stop gradient on the GPU. The
// acceptance: sampled exactly at each stop (a 512 × 512 picture at phase 0 maps pixel i to t = (i + 0.5)/512 exactly,
// so stops sit on pixel centres), the colour is the stored 8-bit sRGB colour and the alpha the stored alpha within
// 1/255, in every interpolation mode. Between stops the GPU matches the CPU reference (`GradientRamp.color(at:)`)
// within 2/255. A golden signature pins one ramp; without a ramp the SHD-001 golden still holds (MaterialRenderTests).
// Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import ParameterGraph
import ProceduralMaterials
import VisualGenerators
import XCTest

final class MaterialGradientRampTests: XCTestCase {
    private static let side = 512

    /// Pixel index → its stop position (2k + 1)/1024, exact in float.
    private static func position(_ pixel: Int) -> Float { (Float(pixel) + 0.5) / Float(side) }

    private static let stopPixels: [Int] = [20, 150, 300, 491]
    private static let stops: [GradientRampStop] = [
        GradientRampStop(position: position(20), red: 0xFF, green: 0x40, blue: 0x00, alpha: 1),
        GradientRampStop(position: position(150), red: 0x20, green: 0xC0, blue: 0x80, alpha: 0.5),
        GradientRampStop(position: position(300), red: 0x00, green: 0x10, blue: 0xF0, alpha: 0.75),
        GradientRampStop(position: position(491), red: 0xE8, green: 0xE8, blue: 0x30, alpha: 0.25),
    ]

    /// A Gradient Field layer that stays at phase 0 with brightness 1.
    private func makeLayer(_ ramp: GradientRamp?) throws -> ProceduralMaterialLayer {
        let layer = ProceduralMaterialCatalog.makeLayer(.gradient)
        let d = layer.definition
        try layer.set(.continuous(0), for: d.speedParameter)
        try layer.set(.continuous(0), for: d.reactivityParameter)
        try layer.set(.continuous(1), for: d.parameterID("brightness"))
        layer.setGradient(ramp)
        return layer
    }

    private func row(_ ramp: GradientRamp, rig: MaterialGPURig) throws -> [Pixel] {
        let driver = try MaterialGPURig.Driver(rig: rig, layer: try makeLayer(ramp), width: Self.side, height: Self.side)
        try driver.step()
        XCTAssertEqual(driver.layer.motion.phase, 0)
        let pixels = try driver.read()
        let y = Self.side / 2
        return Array(pixels[(y * Self.side)..<((y + 1) * Self.side)])
    }

    /// Premultiplied linear → (straight 8-bit-scale sRGB colour, alpha × 255), unrounded.
    private func stored(_ p: Pixel) -> (rgb: [Float], alpha: Float) {
        let a: Float = p.w
        let rgb: [Float] = [p.x, p.y, p.z].map { (v: Float) -> Float in
            a > 0 ? SRGB.encode(v / a) * 255 : 0
        }
        return (rgb, a * 255)
    }

    func testEveryStopSampleMatchesTheStoredColourInEveryMode() throws {
        let rig = try MaterialGPURig()
        for mode in GradientInterpolation.allCases {
            let ramp = try XCTUnwrap(GradientRamp(stops: Self.stops, interpolation: mode))
            let pixels = try row(ramp, rig: rig)
            for (k, x) in Self.stopPixels.enumerated() {
                let s: GradientRampStop = Self.stops[k]
                let got = stored(pixels[x])
                let want: [Float] = [Float(s.red), Float(s.green), Float(s.blue)]
                for c in 0..<3 {
                    XCTAssertEqual(got.rgb[c], want[c], accuracy: 1, "\(mode) stop \(k + 1) channel \(c)")
                }
                XCTAssertEqual(got.alpha, s.alpha * 255, accuracy: 1, "\(mode) stop \(k + 1) alpha")
            }
            if mode == .step {   // analysis fix: just before the next stop the previous stop still holds
                let before = stored(pixels[Self.stopPixels[1] - 1])
                XCTAssertEqual(before.rgb[0], Float(Self.stops[0].red), accuracy: 1)
                XCTAssertEqual(before.alpha, 255, accuracy: 1)
            }
        }
    }

    func testBetweenStopsTheGPUMatchesTheCPUReference() throws {
        let rig = try MaterialGPURig()
        let samples: [Int] = [0, 5, 85, 200, 250, 400, 511]
        for mode in GradientInterpolation.allCases {
            let ramp = try XCTUnwrap(GradientRamp(stops: Self.stops, interpolation: mode))
            let pixels = try row(ramp, rig: rig)
            for x in samples {
                let reference: LinearColor = ramp.color(at: Self.position(x))
                let want = stored(Pixel(reference.red * reference.alpha, reference.green * reference.alpha,
                                        reference.blue * reference.alpha, reference.alpha))
                let got = stored(pixels[x])
                for c in 0..<3 { XCTAssertEqual(got.rgb[c], want.rgb[c], accuracy: 2, "\(mode) pixel \(x) channel \(c)") }
                XCTAssertEqual(got.alpha, want.alpha, accuracy: 2, "\(mode) pixel \(x) alpha")
            }
        }
    }

    func testClearingTheRampRestoresTheTwoColourPicture() throws {
        let rig = try MaterialGPURig()
        let plain = try MaterialGPURig.Driver(rig: rig, layer: try makeLayer(nil))
        let cleared = try MaterialGPURig.Driver(rig: rig, layer: try makeLayer(GradientRamp(stops: Self.stops)))
        cleared.layer.setGradient(nil)
        try plain.step()
        try cleared.step()
        XCTAssertEqual(try plain.read(), try cleared.read())
        XCTAssertEqual(invalidPixelCount(try plain.read()), 0, "opaque without a ramp")
    }

    /// Mean RGBA, then pixels (8,32), (32,32), (56,32), (32,8) RGBA; 64 × 64, smooth ramp, radial, frame 30 at 60 Hz
    /// with the default speed. Recorded 2026-11-14 on the Mac Studio host GPU.
    private static let golden: [Float] = [0.1009, 0.1110, 0.0881, 0.4111, 0.1353, 0.1356, 0.0704, 0.4045,
                                          0.5996, 0.0307, 0.0000, 1.0000, 0.1357, 0.1360, 0.0447, 0.3564,
                                          0.1353, 0.1356, 0.0704, 0.4045]

    func testGoldenSignature() throws {
        let rig = try MaterialGPURig()
        let layer = ProceduralMaterialCatalog.makeLayer(.gradient)
        try layer.set(.enumeration("radial"), for: layer.definition.parameterID("shape"))
        layer.setGradient(try XCTUnwrap(GradientRamp(stops: Self.stops)))
        let driver = try MaterialGPURig.Driver(rig: rig, layer: layer)
        for _ in 0...30 { try driver.step() }
        let pixels = try driver.read()
        let mean = pixels.reduce(Pixel.zero, +) / Float(pixels.count)
        var s: [Float] = [mean.x, mean.y, mean.z, mean.w]
        for (x, y) in [(8, 32), (32, 32), (56, 32), (32, 8)] {
            let p = pixels[y * 64 + x]
            s += [p.x, p.y, p.z, p.w]
        }
        let text = s.map { (v: Float) -> String in String(format: "%.4f", v) }.joined(separator: ", ")
        XCTAssertEqual(Self.golden.count, s.count, "signature: [\(text)]")
        for (i, (e, v)) in zip(Self.golden, s).enumerated() {
            XCTAssertEqual(v, e, accuracy: 0.02, "signature value \(i): [\(text)]")
        }
    }
}
#endif
