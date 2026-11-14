// LissajousRenderTests.swift — VIS-004-T06: the real Metal pipeline draws the Lissajous scope offscreen
// (VIS-004-R1, R4, R7, R8): the in-phase fixture lights pixels only near the diagonal, the quadrature
// fixture only near its circle, silence clears to the background, and a persistence ghost fades and
// disappears after 4 half-lives. Without a Metal device the tests skip (RenderRig); they never fail for that.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class LissajousRenderTests: XCTestCase {
    private let width = 128, height = 96
    private let format: MTLPixelFormat = .bgra8Unorm_srgb

    private func render(_ rig: RenderRig, _ generator: LissajousGenerator, _ stereo: [Float]) throws -> [UInt8] {
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let drawn = stereo.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
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

    private func brightness(_ bytes: [UInt8], _ x: Int, _ y: Int) -> Int {
        let i = (y * width + x) * 4
        return Int(max(bytes[i], bytes[i + 1], bytes[i + 2]))
    }

    /// Lit pixels and the largest distance of a lit pixel centre from the shape `distance` describes.
    private func litPixels(_ bytes: [UInt8], distance: (Double, Double) -> Double) -> (count: Int, worst: Double) {
        var count = 0
        var worst = 0.0
        for y in 0..<height {
            for x in 0..<width where brightness(bytes, x, y) > 32 {
                count += 1
                worst = max(worst, distance(Double(x) + 0.5, Double(y) + 0.5))
            }
        }
        return (count, worst)
    }

    func testInPhaseLightsTheDiagonalAndQuadratureTheCircle() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try LissajousGenerator(device: rig.device, pixelFormat: format) }
        let cx = Double(width) / 2, cy = Double(height) / 2
        let r = 0.9 * Double(min(width, height)) / 2
        let slack = generator.layout.thicknessPixels / 2 + 1.5
        let line = litPixels(try render(rig, generator, LissajousFixture.history(.inPhase))) { (x: Double, y: Double) -> Double in
            // The screen diagonal through the centre rising to the right: (x − cx) = −(y − cy).
            abs((x - cx) + (y - cy)) / 2.0.squareRoot()
        }
        XCTAssertGreaterThan(line.count, Int(r))
        XCTAssertLessThanOrEqual(line.worst, slack, "in-phase: lit pixels on the diagonal")
        let circle = litPixels(try render(rig, generator, LissajousFixture.history(.quadrature))) { (x: Double, y: Double) -> Double in
            abs(((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot() - r)
        }
        XCTAssertGreaterThan(circle.count, Int(4 * r))
        XCTAssertLessThanOrEqual(circle.worst, slack + 1, "quadrature: lit pixels on the circle")
        XCTAssertEqual(generator.lastGain, 1, "a thin trace is never limited")
    }

    func testSilenceClearsToTheBackground() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try LissajousGenerator(device: rig.device, pixelFormat: format) }
        let bytes = try render(rig, generator, LissajousFixture.silence())
        XCTAssertEqual(stride(from: 0, to: bytes.count, by: 4).map { (i: Int) -> Int in Int(max(bytes[i], bytes[i + 1], bytes[i + 2])) }.max(), 0)
    }

    func testPersistenceGhostFadesAndDisappears() throws {
        let rig = try RenderRig()
        let configuration = LissajousConfiguration(persistenceHalfLife: 0.2, lineThickness: 0.03, palette: .mono)
        let generator = try rig.build { try LissajousGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
        _ = try render(rig, generator, LissajousFixture.history(.quadrature))   // a circle, then only the diagonal
        // The circle's top (off the diagonal) is then lit by the ghost alone. Its 128 points retrace the
        // circle about 10 times, so the coverage builds up like a phosphor's while the weight is high.
        let top = Int(Double(height) / 2 - 0.9 * Double(min(width, height)) / 2)
        let line = LissajousFixture.history(.inPhase)
        var ghost: [Int] = []
        for _ in 0..<54 {   // 0.9 s: past 4 half-lives
            let bytes = try render(rig, generator, line)
            ghost.append((max(top - 2, 0)...(top + 2)).map { (y: Int) -> Int in brightness(bytes, width / 2, y) }.max() ?? 0)
            XCTAssertGreaterThan(brightness(bytes, width / 2, height / 2), 32, "the trace is drawn (the envelope may dim it)")
        }
        // Frame to frame the envelope's gain moves the ghost a little (a new snapshot adds light); its weight
        // only falls, so it starts bright, ends faint and disappears without a pop.
        XCTAssertGreaterThan(ghost[0], 200, "the ghost is drawn: \(ghost)")
        let lastLit = try XCTUnwrap(ghost.lastIndex { (v: Int) -> Bool in v > 0 }, "\(ghost)")
        XCTAssertLessThan(ghost[lastLit], 100, "faint before it goes (no pop): \(ghost)")
        XCTAssertEqual(ghost.last, 0, "gone after 4 half-lives")
    }
}
#endif
