// ParticleEmitterRenderTests.swift — SHD-007-T06: the real Metal pipeline draws a configured emitter offscreen
// (SHD-007 US3). After 2 s of a seeded rectangle emitter with box bounce: every lit pixel belongs to a laid-out
// square inside the box; two generators give byte-identical frames; the frame matches its golden signature (lit
// pixels and mean level, within 2 %). Without a Metal device the tests skip (RenderRig); they never fail for that.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class ParticleEmitterRenderTests: XCTestCase {
    private let width = 128, height = 96
    private let format: MTLPixelFormat = .bgra8Unorm_srgb
    /// Golden signature on the host GPU (recorded 2026-11-14).
    private static let goldenLitPixels = 432
    private static let goldenMean = 2.9557

    private static let settings = ParticleEmitterSettings(shape: .rectangle, shapeWidth: 0.6, shapeHeight: 0.2, rate: 60,
                                                          minimumSpeed: 1.5, maximumSpeed: 2.5, spread: 35,
                                                          minimumLifetime: 1.5, maximumLifetime: 3, gravity: 2,
                                                          bounds: .box, boxHalfWidth: 0.6, boxHeight: 1.2, seed: 2026)

    private func frame(_ rig: RenderRig, _ generator: ParticleFountainGenerator, at seconds: UInt64) throws -> [UInt8] {
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let context = VisualFrameContext(timeNanoseconds: seconds * 1_000_000_000, frameDuration: 1.0 / 60, reduceFlashing: false)
        let drawn = [Float]().withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: texture, commandBuffer: commands, bands: b, context: context)
        }
        XCTAssertTrue(drawn)
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return RenderRig.bytes(of: buffer)
    }

    /// 2 s of the emitter: frames at 10, 11 and 12 s (each advance runs 240 steps).
    private func render(_ rig: RenderRig) throws -> (ParticleFountainGenerator, [UInt8]) {
        let configuration = ParticleFountainConfiguration(emitter: Self.settings)
        let generator = try rig.build { try ParticleFountainGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
        _ = try frame(rig, generator, at: 10)
        _ = try frame(rig, generator, at: 11)
        return (generator, try frame(rig, generator, at: 12))
    }

    func testConfiguredEmitterDrawsInsideItsBoxAndMatchesTheGolden() throws {
        let rig = try RenderRig()
        let (generator, bytes) = try render(rig)
        let (_, again) = try render(rig)
        XCTAssertEqual(bytes, again, "the same seed draws the same frame")
        XCTAssertEqual(generator.simulation.spawnAttempts, 120, "⌊60 × 2⌋")
        let big = Double(min(width, height)) / 2
        let half = generator.layout.sidePixels / 2 + 1
        let left = Double(width) / 2 - 0.6 * big - half, right = Double(width) / 2 + 0.6 * big + half
        let bottom = Double(height) + half, top = Double(height) - 1.2 * big - half
        let squares = (0..<generator.layout.squareCount).map { (k: Int) -> [Double] in generator.layout.quad(k) }
        var lit = 0
        var sum = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                sum += Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])
                guard max(bytes[i], bytes[i + 1], bytes[i + 2]) > 24 else { continue }
                lit += 1
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                XCTAssertTrue(px >= left && px <= right && py >= top && py <= bottom, "pixel (\(px), \(py)) inside the box")
                XCTAssertTrue(squares.contains { (q: [Double]) -> Bool in
                    px >= q[0] - 1 && px <= q[2] + 1 && py >= q[1] - 1 && py <= q[5] + 1
                }, "pixel (\(px), \(py)) belongs to a laid-out square")
            }
        }
        let mean = Double(sum) / Double(width * height * 3)
        XCTAssertGreaterThan(lit, 50, "the emitter is drawn")
        XCTAssertEqual(Double(lit), Double(Self.goldenLitPixels), accuracy: Double(Self.goldenLitPixels) * 0.02 + 1)
        XCTAssertEqual(mean, Self.goldenMean, accuracy: Self.goldenMean * 0.02 + 0.01)
    }
}
#endif
