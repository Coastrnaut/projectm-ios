// ParticleFountainRenderTests.swift — VIS-008-T06: the real Metal pipeline draws the particle fountain offscreen
// (VIS-008-R1, R7): no onset leaves only the background; a burst lights exactly its laid-out squares, above the
// emitter; the loop restart clears the particles. Without a Metal device the tests skip (RenderRig); they never
// fail for that.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class ParticleFountainRenderTests: XCTestCase {
    private let width = 128, height = 96
    private let format: MTLPixelFormat = .bgra8Unorm_srgb

    private func render(_ rig: RenderRig, _ generator: ParticleFountainGenerator, at seconds: Double) throws -> [UInt8] {
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let context = VisualFrameContext(timeNanoseconds: UInt64((seconds * 1e9).rounded()), frameDuration: 1.0 / 60,
                                         reduceFlashing: false)
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

    /// (x, y) of every lit pixel centre.
    private func lit(_ bytes: [UInt8]) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard max(bytes[i], bytes[i + 1], bytes[i + 2]) > 24 else { continue }
                out.append((Double(x) + 0.5, Double(y) + 0.5))
            }
        }
        return out
    }

    func testABurstLightsTheConeAboveTheEmitterAndRestartClearsIt() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try ParticleFountainGenerator(device: rig.device, pixelFormat: format) }
        XCTAssertTrue(lit(try render(rig, generator, at: 10)).isEmpty, "no onset, no particle")
        XCTAssertTrue(generator.enqueueOnset(atNanoseconds: 10_000_000_000, strength: 0.6, threshold: 0.1))
        for f in 1...30 { _ = try render(rig, generator, at: 10 + Double(f) / 60) }
        let pixels = lit(try render(rig, generator, at: 10.5 + 1.0 / 60))
        XCTAssertEqual(generator.simulation.spawnedCount, 24)
        XCTAssertGreaterThan(generator.layout.squareCount, 0)
        XCTAssertFalse(pixels.isEmpty, "the burst is drawn")
        let big = Double(min(width, height)) / 2
        let emitterY = Double(height) - 0.1 * big
        let half = generator.layout.sidePixels / 2 + 1
        let squares = (0..<generator.layout.squareCount).map { (k: Int) -> [Double] in generator.layout.quad(k) }
        for (x, y) in pixels {
            XCTAssertLessThanOrEqual(y, emitterY + half, "no particle below the emitter at 0.5 s")
            XCTAssertTrue(squares.contains { (q: [Double]) -> Bool in
                x >= q[0] - 1 && x <= q[2] + 1 && y >= q[1] - 1 && y <= q[5] + 1
            }, "pixel (\(x), \(y)) belongs to a laid-out square")
        }
        for q in squares where generator.layout.color(squares.firstIndex(of: q)!).alpha > 0.2 {
            let cx = (q[0] + q[2]) / 2, cy = (q[1] + q[5]) / 2
            XCTAssertTrue(pixels.contains { abs($0.0 - cx) <= half && abs($0.1 - cy) <= half }, "square at (\(cx), \(cy)) is drawn")
        }
        generator.restartLoop()
        XCTAssertEqual(generator.simulation.liveCount, 0)
        XCTAssertTrue(lit(try render(rig, generator, at: 11)).isEmpty, "the loop restart clears the particles")
    }
}
#endif
