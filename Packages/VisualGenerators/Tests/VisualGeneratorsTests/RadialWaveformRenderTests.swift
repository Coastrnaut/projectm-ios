// RadialWaveformRenderTests.swift — VIS-005-T05: the real Metal pipeline draws the radial waveform offscreen
// (VIS-005-R1, R2, R5, R7): a sine ring lights pixels only within its band around the base circle, silence
// lights only the base circle, and the loop restart resets the gain. Without a Metal device the tests skip
// (RenderRig); they never fail for that.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class RadialWaveformRenderTests: XCTestCase {
    private let width = 128, height = 96
    private let format: MTLPixelFormat = .bgra8Unorm_srgb

    private func render(_ rig: RenderRig, _ generator: RadialWaveformGenerator, _ history: [Float]) throws -> [UInt8] {
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let drawn = history.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: texture, commandBuffer: commands, bands: b,
                             context: VisualFrameContext(timeNanoseconds: 0, frameDuration: 1.0 / 60, reduceFlashing: false))
        }
        XCTAssertTrue(drawn)
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return RenderRig.bytes(of: buffer)
    }

    /// Lit pixels and the smallest and largest distance of a lit pixel centre from the picture's centre.
    private func litRing(_ bytes: [UInt8]) -> (count: Int, nearest: Double, farthest: Double) {
        var count = 0
        var nearest = Double.infinity, farthest = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard max(bytes[i], bytes[i + 1], bytes[i + 2]) > 32 else { continue }
                count += 1
                let dx = Double(x) + 0.5 - Double(width) / 2, dy = Double(y) + 0.5 - Double(height) / 2
                let d = (dx * dx + dy * dy).squareRoot()
                nearest = min(nearest, d)
                farthest = max(farthest, d)
            }
        }
        return (count, nearest, farthest)
    }

    func testSineRingAndSilenceCircle() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try RadialWaveformGenerator(device: rig.device, pixelFormat: format) }
        let big = Double(min(width, height)) / 2
        let c = generator.configuration
        let slack = generator.layout.thicknessPixels / 2 + 1.5
        let circle = litRing(try render(rig, generator, RadialFixture.silence()))
        XCTAssertGreaterThan(circle.count, Int(4 * c.baseRadius * big), "silence draws the base circle")
        XCTAssertGreaterThanOrEqual(circle.nearest, c.baseRadius * big - slack)
        XCTAssertLessThanOrEqual(circle.farthest, c.baseRadius * big + slack)
        let ring = litRing(try render(rig, generator, RadialFixture.sine(97)))
        XCTAssertGreaterThanOrEqual(ring.nearest, (c.baseRadius - c.amplitude) * big - slack)
        XCTAssertLessThanOrEqual(ring.farthest, (c.baseRadius + c.amplitude) * big + slack)
        XCTAssertGreaterThan(ring.farthest - ring.nearest, c.amplitude * big, "the wave moves the ring both ways")
        XCTAssertEqual(generator.lastGain, 1, "a thin ring is never limited")
        generator.restartLoop()
        XCTAssertEqual(generator.layout.autoGain.level, LissajousAutoGain.floor)
    }
}
#endif
