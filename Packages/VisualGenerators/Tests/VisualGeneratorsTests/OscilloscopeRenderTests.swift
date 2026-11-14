// OscilloscopeRenderTests.swift — VIS-003-T08: the real Metal pipeline draws the oscilloscope offscreen
// (VIS-003-R1, R7, R8, S1): lit pixels lie on the predicted line, the line has its palette color, and
// a 440 Hz sine advanced by 700…770 samples per frame (as the capture delivers it) draws the same
// picture every frame. Without a Metal device the tests skip (RenderRig); they never fail for that.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class OscilloscopeRenderTests: XCTestCase {
    private let width = 128, height = 96
    private let format: MTLPixelFormat = .bgra8Unorm_srgb

    private func render(_ rig: RenderRig, _ generator: OscilloscopeGenerator, _ samples: [Float]) throws -> [UInt8] {
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let drawn = samples.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
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

    private func lit(_ bytes: [UInt8], _ x: Int, _ y: Int) -> Bool {
        let i = (y * width + x) * 4
        return max(bytes[i], bytes[i + 1], bytes[i + 2]) > 32
    }

    /// Distance from (px, py) to the segment a–b.
    private static func distance(_ px: Double, _ py: Double, _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let t = max(0, min(1, ((px - a.x) * dx + (py - a.y) * dy) / (dx * dx + dy * dy)))
        let cx = a.x + t * dx - px, cy = a.y + t * dy - py
        return (cx * cx + cy * cy).squareRoot()
    }

    func testLitPixelsLieOnTheLineInItsColors() throws {
        let rig = try RenderRig()
        let configuration = OscilloscopeConfiguration(lineThickness: 0.05)
        let generator = try rig.build { try OscilloscopeGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
        let samples = WaveformSignal(shape: .sine, frequency: 440).history(endingAt: 60_000)
        let bytes = try render(rig, generator, samples)
        XCTAssertEqual(generator.lastGain, 1, "a thin line is never limited")
        let layout = generator.layout
        let reach = layout.thicknessPixels / 2 + 1
        var litPixels = 0
        for y in 0..<height {
            for x in 0..<width where lit(bytes, x, y) {
                litPixels += 1
                let cx = Double(x) + 0.5, cy = Double(y) + 0.5
                // Only segments near this column can be close.
                var nearest = Double.infinity
                for k in 0..<layout.segmentCount where abs(layout.point(k).x - cx) <= reach + 2 {
                    nearest = min(nearest, Self.distance(cx, cy, layout.point(k), layout.point(k + 1)))
                }
                XCTAssertLessThanOrEqual(nearest, reach, "lit pixel (\(x), \(y)) off the line")
            }
        }
        XCTAssertGreaterThan(litPixels, width * 4, "the line is drawn across the width")
        // Every column has the line, in its segment's palette color (within 2/255).
        for x in [2, 40, 64, 100, 125] {
            let row = try XCTUnwrap((0..<height).first { lit(bytes, x, $0) && lit(bytes, x, min($0 + 1, height - 1)) }, "column \(x)")
            let k = min(Int(Double(x) + 0.5) * layout.segmentCount / width, layout.segmentCount - 1)
            let i = (row * width + x) * 4
            let observed = [Int(bytes[i + 2]), Int(bytes[i + 1]), Int(bytes[i])]
            // A thick, steep line puts segments up to T/2 + 1 px left or right of the column in it
            // (about ±25 segments at this size): the pixel has one of their colors.
            let span = Int((reach + 1) * Double(layout.segmentCount) / Double(width)) + 1
            let near = (max(k - span, 0)...min(k + span, layout.segmentCount - 1)).map { (s: Int) -> [Int] in
                let c = layout.flashRegionColor(s)
                return [c.red, c.green, c.blue].map { (v: Float) -> Int in Int((SRGB.encode(v) * 255).rounded()) }
            }
            let best = near.map { (e: [Int]) -> Int in zip(e, observed).map { (p: (Int, Int)) -> Int in abs(p.0 - p.1) }.max()! }.min()!
            XCTAssertLessThanOrEqual(best, 2, "column \(x) color \(observed)")
        }
    }

    /// VIS-003-S1 in pixels: ten frames of a 440 Hz sine with irregular advances draw the same picture.
    func testSineDrawsTheSamePictureEveryFrame() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try OscilloscopeGenerator(device: rig.device, pixelFormat: format) }
        let signal = WaveformSignal(shape: .sine, frequency: 440)
        var end: Int64 = 60_000
        var first: [UInt8]?
        var worst = 0
        for f in 0..<10 {
            end += WaveformFrames.advance(frame: f)
            let bytes = try render(rig, generator, signal.history(endingAt: end))
            XCTAssertEqual(generator.layout.lastTrigger.mode, .triggered)
            guard let reference = first else { first = bytes; continue }
            var differing = 0
            for p in 0..<(width * height) {
                let i = p * 4
                if abs(Int(bytes[i]) - Int(reference[i])) > 2 || abs(Int(bytes[i + 1]) - Int(reference[i + 1])) > 2
                    || abs(Int(bytes[i + 2]) - Int(reference[i + 2])) > 2 { differing += 1 }
            }
            worst = max(worst, differing)
        }
        // QA-002's rule: at most 0.1 % of pixels may differ by more than 2/255.
        XCTAssertLessThanOrEqual(worst, width * height / 1_000, "frames differ in \(worst) pixels")
        print("VIS-003 render: 10 frames of a 440 Hz sine, worst differing pixels vs frame 0: \(worst) of \(width * height)")
    }

    func testRejectsOtherPixelFormatsAndSkipsMismatchedTargets() throws {
        let rig = try RenderRig()
        XCTAssertThrowsError(try OscilloscopeGenerator(device: rig.device, pixelFormat: .r8Unorm))
        let generator = try rig.build { try OscilloscopeGenerator(device: rig.device, pixelFormat: format) }
        let other = try rig.makeTexture(width: 8, height: 8, format: .rgba16Float)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let drawn = [Float](repeating: 0, count: 16).withUnsafeBufferPointer {
            generator.encode(into: other, commandBuffer: commands, bands: $0,
                             context: VisualFrameContext(timeNanoseconds: 0, frameDuration: 1.0 / 60, reduceFlashing: false))
        }
        XCTAssertFalse(drawn, "a target of another pixel format is skipped")
    }
}
#endif
