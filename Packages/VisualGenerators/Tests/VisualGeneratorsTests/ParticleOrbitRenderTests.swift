// ParticleOrbitRenderTests.swift — VIS-009-T08: the real Metal pipeline draws the particle orbit offscreen (VIS-009-R1,
// R3, R7): every lit pixel belongs to a laid-out square (the centre or a particle on the ring at the drawn radius); a
// bigger target radius draws a bigger ring; the loop restart returns the radius to the base. Without a Metal device
// the tests skip (RenderRig); they never fail for that.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class ParticleOrbitRenderTests: XCTestCase {
    private let width = 128, height = 96
    private let format: MTLPixelFormat = .bgra8Unorm_srgb

    private func render(_ rig: RenderRig, _ generator: ParticleOrbitGenerator, frame n: Int) throws -> [UInt8] {
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let context = VisualFrameContext(timeNanoseconds: UInt64(n) * 1_000_000_000 / 60, frameDuration: 1.0 / 60,
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

    /// Distances from the centre (R units) of every lit pixel outside the centre square.
    private func ringDistances(_ bytes: [UInt8], core: Double) -> [Double] {
        let big = Double(min(width, height)) / 2
        var out: [Double] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard max(bytes[i], bytes[i + 1], bytes[i + 2]) > 24 else { continue }
                let dx = Double(x) + 0.5 - Double(width) / 2, dy = Double(y) + 0.5 - Double(height) / 2
                guard max(abs(dx), abs(dy)) > core / 2 + 1 else { continue }
                out.append((dx * dx + dy * dy).squareRoot() / big)
            }
        }
        return out
    }

    private func drive(_ rig: RenderRig, _ g: ParticleOrbitGenerator, bass: Double, frames: Range<Int>) throws -> [UInt8] {
        var last: [UInt8] = []
        for n in frames {
            g.drive(base: 0.5, bass: bass)
            last = try render(rig, g, frame: n)
        }
        return last
    }

    func testTheRingIsDrawnAtTheDrawnRadiusAndGrowsWithTheBass() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try ParticleOrbitGenerator(device: rig.device, pixelFormat: format) }
        let quiet = try drive(rig, generator, bass: 0, frames: 0..<31)
        let core = generator.layout.side(0)
        let quietRing = ringDistances(quiet, core: core)
        XCTAssertFalse(quietRing.isEmpty, "the ring is drawn")
        let big = Double(min(width, height)) / 2
        let slack = (generator.layout.side(1) / 2 + 1.5) / big
        let r0 = generator.layout.drawnRadius
        XCTAssertEqual(r0, 0.5, accuracy: 0.01)
        for d in quietRing {   // offsets are 0.9…1.1
            XCTAssertGreaterThanOrEqual(d, r0 * 0.9 - slack)
            XCTAssertLessThanOrEqual(d, r0 * 1.1 + slack)
        }
        XCTAssertEqual(generator.lastVertexCount, 6 * (generator.simulation.count + 1))
        let loud = ringDistances(try drive(rig, generator, bass: 1, frames: 31..<62), core: core)
        XCTAssertEqual(generator.layout.drawnRadius, 0.7, accuracy: 0.01)
        let mean: ([Double]) -> Double = { (v: [Double]) -> Double in v.reduce(0, +) / Double(max(v.count, 1)) }
        XCTAssertGreaterThan(mean(loud), mean(quietRing) + 0.1, "full bass draws a bigger ring")
        generator.restartLoop()
        XCTAssertEqual(generator.simulation.radius, 0.5)
        XCTAssertEqual(generator.simulation.stepsRun, 0)
    }
}
#endif
