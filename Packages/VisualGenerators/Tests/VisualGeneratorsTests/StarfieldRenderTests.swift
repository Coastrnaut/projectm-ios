// StarfieldRenderTests.swift — VIS-016-T07: the real Metal pipeline draws the starfield offscreen (VIS-016-R1, R4, R5;
// S3): two generators from scratch give identical bytes; every lit pixel lies inside a laid-out star square; the loop
// restart gives the first frame again, byte for byte. Without a Metal device the tests skip (RenderRig); they never
// fail for that.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class StarfieldRenderTests: XCTestCase {
    private let width = 128, height = 96
    private let format: MTLPixelFormat = .bgra8Unorm_srgb
    private let bands: [Float] = (0..<64).map { (k: Int) -> Float in k < 21 ? 0.8 : 0.1 }

    private func render(_ rig: RenderRig, _ generator: StarfieldGenerator, frame n: Int) throws -> [UInt8] {
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let context = VisualFrameContext(timeNanoseconds: UInt64(n) * 1_000_000_000 / 60, frameDuration: 1.0 / 60,
                                         reduceFlashing: false)
        let drawn = bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: texture, commandBuffer: commands, bands: b, context: context)
        }
        XCTAssertTrue(drawn)
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return RenderRig.bytes(of: buffer)
    }

    private func run(_ rig: RenderRig, _ generator: StarfieldGenerator, frames: ClosedRange<Int>) throws -> [UInt8] {
        var last: [UInt8] = []
        for n in frames { last = try render(rig, generator, frame: n) }
        return last
    }

    func testFramesAreDeterministicLitPixelsAreStarsAndRestartReplays() throws {
        let rig = try RenderRig()
        let configuration = StarfieldConfiguration(density: 2000, speed: .fast)
        let a = try rig.build { try StarfieldGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
        let b = try rig.build { try StarfieldGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
        let first = try render(rig, a, frame: 0)
        let frameA = try run(rig, a, frames: 1...20)
        let frameB = try run(rig, b, frames: 0...20)
        XCTAssertEqual(frameA, frameB, "two generators from scratch draw the same bytes")
        XCTAssertEqual(a.simulation.stepsRun, 80)
        XCTAssertEqual(a.lastVertexCount, 6 * a.layout.squareCount)
        XCTAssertGreaterThan(a.layout.squareCount, 100)
        // Every lit pixel is inside some laid-out square (1 px slack for rasterization).
        var inside = [Bool](repeating: false, count: width * height)
        for k in 0..<a.layout.squareCount {
            let c = a.layout.center(k), half = a.layout.side(k) / 2 + 1
            let x0 = max(Int((c.x - half).rounded(.down)), 0), x1 = min(Int((c.x + half).rounded(.up)), width - 1)
            let y0 = max(Int((c.y - half).rounded(.down)), 0), y1 = min(Int((c.y + half).rounded(.up)), height - 1)
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 { inside[y * width + x] = true } }
        }
        var lit = 0
        for p in 0..<(width * height) where max(frameA[p * 4], frameA[p * 4 + 1], frameA[p * 4 + 2]) > 8 {
            lit += 1
            XCTAssertTrue(inside[p], "lit pixel \(p % width), \(p / width) belongs to a star")
        }
        XCTAssertGreaterThan(lit, 50, "stars were drawn")
        a.restartLoop()
        XCTAssertEqual(try render(rig, a, frame: 100), first, "restart replays the first frame")
    }
}
#endif
