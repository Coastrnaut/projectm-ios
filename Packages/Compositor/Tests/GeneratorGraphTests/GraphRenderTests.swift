// SHD-002-T13, T15 (US1, US2; SHD-002-R8, R9, R14; S1, S2): every example draws a valid picture, alone
// and through the compositor, at odd sizes and with bad bands; drawing is deterministic; one shared
// interpreter pipeline draws different graphs; golden signatures. GPU at 64 × 64; skipped without a
// Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import GeneratorGraph
import Metal
import XCTest

final class GraphRenderTests: XCTestCase {
    func testExamplesDrawValidFrames() throws {
        let rig = try GraphGPURig()
        for document in GeneratorGraphExamples.all {
            let driver = try GraphGPURig.Driver(rig: rig, layer: rig.layer(document))
            try driver.step()
            let pixels = try driver.read()
            XCTAssertEqual(invalidGraphPixelCount(pixels), 0, document.name)
            let peak = pixels.reduce(Float(0)) { (m: Float, p: GPixel) -> Float in max(m, p.x, p.y, p.z) }
            XCTAssertGreaterThan(peak, 0.05, "\(document.name) is not blank")
        }
    }

    func testExamplesRenderThroughTheCompositor() throws {
        let rig = try GraphGPURig()
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 64, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        for document in GeneratorGraphExamples.all {
            let compositor = try Compositor(device: rig.device, layers: [rig.layer(document)])
            for i in 0..<3 {
                let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
                XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands,
                                                   presentationTimeNanoseconds: UInt64(i) * GraphGPURig.frameNanoseconds,
                                                   contentScale: 2, reduceFlashing: true, audio: .empty))
                commands.commit()
                commands.waitUntilCompleted()
            }
            XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered, document.name)
            XCTAssertEqual(invalidGraphPixelCount(try rig.read(output)), 0, document.name)
        }
    }

    func testOddSizesAndBadBandsDraw() throws {
        let rig = try GraphGPURig()
        for document in GeneratorGraphExamples.all {
            for (w, h) in [(1, 1), (97, 13)] {
                let driver = try GraphGPURig.Driver(rig: rig, layer: rig.layer(document), width: w, height: h)
                try driver.step(bands: [.nan, -1, 5, .infinity])
                try driver.step(bands: [.nan, -1, 5, .infinity])
                XCTAssertEqual(invalidGraphPixelCount(try driver.read()), 0, "\(document.name) \(w)×\(h)")
            }
        }
    }

    func testRendersAreDeterministic() throws {
        let rig = try GraphGPURig()
        for document in GeneratorGraphExamples.all {
            let a = try GraphGPURig.Driver(rig: rig, layer: rig.layer(document))
            let b = try GraphGPURig.Driver(rig: rig, layer: GeneratorGraphLayer(document: document))   // own pipeline
            for i in 0..<60 {
                let bands = [Float](repeating: Float(i % 7) / 7, count: 8)
                try a.step(bands: bands)
                try b.step(bands: bands)
            }
            XCTAssertEqual(try a.read(), try b.read(), "\(document.name): bit-identical after 60 frames")
        }
    }

    func testOneSharedPipelineDrawsDifferentGraphs() throws {
        let rig = try GraphGPURig()
        let ember = try GraphGPURig.Driver(rig: rig, layer: rig.layer(GeneratorGraphExamples.emberDrift))
        let rings = try GraphGPURig.Driver(rig: rig, layer: rig.layer(GeneratorGraphExamples.hueRings))
        try ember.step()
        try rings.step()
        XCTAssertNotEqual(try ember.read(), try rings.read())
        XCTAssertTrue(ember.layer.compiled != rings.layer.compiled)
    }

    func testSpeedIsClampedToTheCap() throws {
        let layer = try GeneratorGraphLayer(document: GeneratorGraphExamples.softOrbs)
        XCTAssertEqual(layer.setSpeed(1), layer.compiled.speedCap)
        XCTAssertEqual(layer.setSpeed(-0.05), -0.05)
    }

    // MARK: Golden signatures (SHD-002-R14)

    struct Signature {
        var mean: SIMD3<Float>
        var peak: SIMD3<Float>
        var pixels: [SIMD3<Float>]   // (32,32), (8,8), (56,16), (16,56)
    }

    static let samplePoints: [(Int, Int)] = [(32, 32), (8, 8), (56, 16), (16, 56)]

    static func signature(_ pixels: [GPixel]) -> Signature {
        var sum = SIMD3<Float>(0, 0, 0)
        var peak = SIMD3<Float>(0, 0, 0)
        for p in pixels {
            let c = SIMD3(p.x, p.y, p.z)
            sum += c
            peak = SIMD3(max(peak.x, c.x), max(peak.y, c.y), max(peak.z, c.z))
        }
        let samples = samplePoints.map { (pt: (Int, Int)) -> SIMD3<Float> in
            let p = pixels[pt.1 * 64 + pt.0]
            return SIMD3(p.x, p.y, p.z)
        }
        return Signature(mean: sum / Float(pixels.count), peak: peak, pixels: samples)
    }

    /// Recorded on the host GPU (Apple silicon), frame 30 at 60 Hz, no music.
    static let golden: [String: Signature] = [
        "Ember Drift": Signature(mean: SIMD3(0.4611, 0.1693, 0.0345), peak: SIMD3(0.7720, 0.2971, 0.0455),
                                 pixels: [SIMD3(0.3008, 0.1033, 0.0288), SIMD3(0.1921, 0.0585, 0.0250),
                                          SIMD3(0.6919, 0.2642, 0.0426), SIMD3(0.5200, 0.1936, 0.0366)]),
        "Hue Rings": Signature(mean: SIMD3(0.3682, 0.3891, 0.4423), peak: SIMD3(0.7998, 0.7998, 0.7998),
                               pixels: [SIMD3(0.7939, 0.2620, 0.1438), SIMD3(0.0001, 0.5942, 0.6055),
                                        SIMD3(0.2798, 0.1296, 0.7900), SIMD3(0.2798, 0.1296, 0.7900)]),
        "Soft Orbs": Signature(mean: SIMD3(0.1102, 0.0833, 0.1037), peak: SIMD3(0.6050, 0.4038, 0.2048),
                               pixels: [SIMD3(0.2177, 0.1528, 0.1256), SIMD3(0.0312, 0.0321, 0.0875),
                                        SIMD3(0.0140, 0.0210, 0.0840), SIMD3(0.0585, 0.0498, 0.0931)]),
    ]

    func testGoldenSignatures() throws {
        let rig = try GraphGPURig()
        for document in GeneratorGraphExamples.all {
            let driver = try GraphGPURig.Driver(rig: rig, layer: rig.layer(document))
            for _ in 0..<30 { try driver.step() }
            let s = Self.signature(try driver.read())
            guard let expected = Self.golden[document.name] else {
                XCTFail("no golden for \(document.name): mean \(s.mean) peak \(s.peak) pixels \(s.pixels)")
                continue
            }
            let tolerance: Float = 0.02
            func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
                abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.z - b.z) <= tolerance
            }
            XCTAssertTrue(near(s.mean, expected.mean), "\(document.name) mean \(s.mean) vs \(expected.mean)")
            XCTAssertTrue(near(s.peak, expected.peak), "\(document.name) peak \(s.peak) vs \(expected.peak)")
            for (i, p) in s.pixels.enumerated() {
                XCTAssertTrue(near(p, expected.pixels[i]), "\(document.name) pixel \(Self.samplePoints[i]) \(p) vs \(expected.pixels[i])")
            }
        }
    }
}
#endif
