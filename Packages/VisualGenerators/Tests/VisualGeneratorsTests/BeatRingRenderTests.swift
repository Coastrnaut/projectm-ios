// BeatRingRenderTests.swift — VIS-006-T06: the real Metal pipeline draws beat rings offscreen (VIS-006-R1, R3,
// R7): four rings light pixels only near their four radii, no rings leave the background, and the loop restart
// clears the rings. Without a Metal device the tests skip (RenderRig); they never fail for that.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class BeatRingRenderTests: XCTestCase {
    private let width = 128, height = 96
    private let format: MTLPixelFormat = .bgra8Unorm_srgb

    private func render(_ rig: RenderRig, _ generator: BeatRingGenerator, at seconds: Double) throws -> [UInt8] {
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let context = VisualFrameContext(timeNanoseconds: UInt64(seconds * 1e9), frameDuration: 1.0 / 60, reduceFlashing: false)
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

    /// Distances from the centre of every lit pixel centre.
    private func litDistances(_ bytes: [UInt8]) -> [Double] {
        var out: [Double] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard max(bytes[i], bytes[i + 1], bytes[i + 2]) > 24 else { continue }
                let dx = Double(x) + 0.5 - Double(width) / 2, dy = Double(y) + 0.5 - Double(height) / 2
                out.append((dx * dx + dy * dy).squareRoot())
            }
        }
        return out
    }

    func testFourRingsLightOnlyTheirRadii() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try BeatRingGenerator(device: rig.device, pixelFormat: format) }
        XCTAssertTrue(litDistances(try render(rig, generator, at: 1)).isEmpty, "no beat, no ring")
        for t in [0.0, 0.4, 0.8, 1.2] {
            XCTAssertTrue(generator.emitRing(atNanoseconds: UInt64((10 + t) * 1e9), flashConfiguration: .forReduceFlashing(false)))
        }
        let lit = litDistances(try render(rig, generator, at: 11.3))
        XCTAssertEqual(generator.layout.ringCount, 4)
        let big = Double(min(width, height)) / 2
        let radii = (0..<4).map { (i: Int) -> Double in generator.layout.ring(i).radius * big }
        let slack = generator.layout.thicknessPixels / 2 + 1.5
        XCTAssertFalse(lit.isEmpty)
        for d in lit {
            XCTAssertTrue(radii.contains { abs($0 - d) <= slack }, "lit pixel at \(d) px is on no ring \(radii)")
        }
        for r in radii.dropFirst() {   // the oldest ring is faint (α ≈ 0.01) and may round to dark
            XCTAssertTrue(lit.contains { abs($0 - r) <= slack }, "ring at \(r) px is drawn")
        }
        generator.restartLoop()
        XCTAssertTrue(litDistances(try render(rig, generator, at: 11.3)).isEmpty, "the loop restart clears the rings")
    }
}
#endif
