// MandalaRenderTests.swift — VIS-007-T06: the real Metal pipeline draws the mandala offscreen (VIS-007-R1, R3,
// R4, R7): silence still draws the base shape inside its radius, the lit pixels repeat with the symmetry (a
// 4-fold picture equals itself turned a quarter turn about the centre, up to edge pixels), and the loop restart
// keeps the rotation anchor. Without a Metal device the tests skip (RenderRig); they never fail for that.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class MandalaRenderTests: XCTestCase {
    private let side = 128
    private let format: MTLPixelFormat = .bgra8Unorm_srgb

    private func render(_ rig: RenderRig, _ generator: MandalaGenerator, bands: [Float], at seconds: Double) throws -> [UInt8] {
        let texture = try rig.makeTexture(width: side, height: side, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let context = VisualFrameContext(timeNanoseconds: UInt64(seconds * 1e9), frameDuration: 1.0 / 60, reduceFlashing: false)
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

    private func lit(_ bytes: [UInt8], _ x: Int, _ y: Int) -> Bool {
        let i = (y * side + x) * 4
        return max(bytes[i], bytes[i + 1], bytes[i + 2]) > 24
    }

    func testSilenceDrawsTheBaseShapeInsideItsRadius() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try MandalaGenerator(device: rig.device, pixelFormat: format) }
        let bytes = try render(rig, generator, bands: [Float](repeating: 0, count: 32), at: 0)
        var count = 0
        let limit = MandalaConfiguration.baseLength * Double(side) / 2 + 1.5
        for y in 0..<side {
            for x in 0..<side where lit(bytes, x, y) {
                count += 1
                let dx = Double(x) + 0.5 - Double(side) / 2, dy = Double(y) + 0.5 - Double(side) / 2
                XCTAssertLessThanOrEqual((dx * dx + dy * dy).squareRoot(), limit, "lit pixel beyond the base tip")
            }
        }
        XCTAssertGreaterThan(count, 50, "silence still draws the base shape")
    }

    func testFourFoldPictureRepeatsEveryQuarterTurn() throws {
        let rig = try RenderRig()
        let generator = try rig.build {
            try MandalaGenerator(device: rig.device, pixelFormat: format, configuration: MandalaConfiguration(symmetry: 4))
        }
        let bands: [Float] = [Float](repeating: 0.8, count: 8) + [Float](repeating: 0.7, count: 8) + [Float](repeating: 0.9, count: 8)
        let bytes = try render(rig, generator, bands: bands, at: 0)
        var total = 0, mismatched = 0
        for y in 0..<side {
            for x in 0..<side where lit(bytes, x, y) {
                total += 1
                // A quarter turn clockwise about the centre (pixel grid: (x, y) → (side − 1 − y, x)).
                if !lit(bytes, side - 1 - y, x) { mismatched += 1 }
            }
        }
        XCTAssertGreaterThan(total, 200)
        XCTAssertLessThanOrEqual(Double(mismatched), 0.03 * Double(total), "\(mismatched) of \(total) lit pixels differ")
        generator.restartLoop()
        _ = try render(rig, generator, bands: bands, at: 10)
        XCTAssertEqual(generator.layout.angle, 2 * Double.pi * 0.25, accuracy: 1e-9, "the turn continues from the clock")
    }
}
#endif
