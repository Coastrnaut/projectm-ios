// WaterfallRenderTests.swift — VIS-020-T06 (VIS-020-R2 to R5, R13; S2, S3; contract C2): the waterfall on the real
// Metal pipeline with an injected clock. After 60 s of a step-per-second input (band ⌊t⌋ of 64 lit) the GPU's history
// texture holds exactly the CPU ring, and the picture shows the rows newest at the top in time order, each sampled
// pixel within 0.02 of the CPU mirror; over 60 s of frames into three output sizes the texture, its size and the ring's
// storage never change; switching modes in place gives a fresh generator's frames. Without a Metal device the tests skip.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class WaterfallRenderTests: XCTestCase {
    private static let format: MTLPixelFormat = .rgba16Float

    private static func bands(at t: UInt64) -> [Float] {
        var b = [Float](repeating: 0, count: 64)
        b[Int(t / 1_000_000_000) % 64] = 1
        return b
    }

    /// Encodes frames 0…`frames` at `fps` (time 0 at frame 0), committing every 100 frames; returns the last command
    /// buffer, uncommitted, with frame `frames` encoded into `targets[frames % targets.count]`.
    private func run(_ rig: RenderRig, _ generator: NoiseFieldGenerator, frames: Int, fps: UInt64, targets: [MTLTexture],
                     every: ((Int) -> Void)? = nil) throws -> MTLCommandBuffer {
        var commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for f in 0...frames {
            let t: UInt64 = UInt64(f) * 1_000_000_000 / fps
            let context = VisualFrameContext(timeNanoseconds: t, frameDuration: 1.0 / Double(fps), reduceFlashing: false)
            let drawn: Bool = Self.bands(at: t).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: targets[f % targets.count], commandBuffer: commands, bands: b, context: context)
            }
            XCTAssertTrue(drawn)
            every?(f)
            if f % 100 == 99 && f < frames {
                commands.commit()
                commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            }
        }
        return commands
    }

    private func finish(_ commands: MTLCommandBuffer) {
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
    }

    func testSixtySecondsRenderNewestAtTheTopInTimeOrder() throws {
        let rig = try RenderRig()
        let c = NoiseFieldConfiguration.waterfall(palette: .ice)
        let generator = try rig.build { try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: c) }
        let (width, height) = (64, 128)
        let target = try rig.makeTexture(width: width, height: height, format: Self.format)
        let commands = try run(rig, generator, frames: 60 * 20, fps: 20, targets: [target])
        let image = try rig.encodeReadBack(target, commands: commands)
        let history = try XCTUnwrap(rig.device.makeBuffer(length: SpectrumWaterfallHistory.byteCount, options: .storageModeShared))
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: generator.historyTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: 256, height: 512, depth: 1), to: history, destinationOffset: 0,
                  destinationBytesPerRow: 256, destinationBytesPerImage: SpectrumWaterfallHistory.byteCount)
        blit.endEncoding()
        finish(commands)
        let h: SpectrumWaterfallHistory = generator.waterfallHistory
        XCTAssertEqual(h.rowsWritten, 512, "60 s fill the ring exactly")
        let gpuLevels = UnsafeBufferPointer(start: history.contents().bindMemory(to: UInt8.self, capacity: SpectrumWaterfallHistory.byteCount),
                                            count: SpectrumWaterfallHistory.byteCount)
        XCTAssertTrue(gpuLevels.elementsEqual(UnsafeBufferPointer(start: h.levels, count: SpectrumWaterfallHistory.byteCount)),
                      "the texture holds exactly the CPU ring")
        let frame: PixelImage = rig.decode(RenderRig.bytes(of: image), width: width, height: height, format: Self.format)
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in c.palette.color(bar: k, of: 16).clamped }
        let lit: Float = 0.8 * generator.lastGain
        var worst: Float = 0
        var previousColumn = Int.max
        for y in stride(from: 1, to: height, by: 4) {   // top (newest) to bottom (oldest)
            var brightest = 0
            var brightestLevel: Float = -1
            for x in 0..<width {
                let v: Float = h.level(atX: Float(x) + 0.5, y: Float(y) + 0.5, width: width, height: height)
                let expected: LinearColor = stops.withUnsafeBufferPointer { (s: UnsafeBufferPointer<LinearColor>) -> LinearColor in
                    SpectrumWaterfallHistory.color(v, stops: s.baseAddress!)
                }
                let px: Pixel = frame[x, y]
                worst = max(worst, abs(px.x - expected.red * lit), abs(px.y - expected.green * lit), abs(px.z - expected.blue * lit))
                if px.y > brightestLevel { brightestLevel = px.y; brightest = x }
            }
            XCTAssertLessThanOrEqual(brightest, previousColumn, "row \(y): the lit band moves left (earlier) going down")
            previousColumn = brightest
        }
        XCTAssertLessThan(worst, 0.02, "GPU vs CPU mirror")
        // The newest row (top) shows second 59 (column ≈ 59/63 of the width), the oldest (bottom) second 0 (left).
        let top: Int = (0..<width).max { (a: Int, b: Int) -> Bool in frame[a, 0].y < frame[b, 0].y } ?? 0
        let bottom: Int = (0..<width).max { (a: Int, b: Int) -> Bool in frame[a, height - 1].y < frame[b, height - 1].y } ?? 0
        XCTAssertEqual(Double(top), 59.0 / 63 * Double(width), accuracy: 2)
        XCTAssertLessThanOrEqual(bottom, 1)
    }

    func testStorageNeverGrowsOverSixtySecondsAndResizes() throws {
        let rig = try RenderRig()
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .waterfall())
        }
        let texture = ObjectIdentifier(generator.historyTexture)
        let bytes: Int = generator.historyTexture.allocatedSize
        let storage = UnsafeMutableRawPointer(generator.waterfallHistory.levels)
        let targets: [MTLTexture] = try [(32, 32), (64, 128), (200, 100)].map { (s: (Int, Int)) -> MTLTexture in
            try rig.makeTexture(width: s.0, height: s.1, format: Self.format)
        }
        var checks = 0
        let commands = try run(rig, generator, frames: 60 * 10, fps: 10, targets: targets) { (f: Int) -> Void in
            guard f % 50 == 0 else { return }
            checks += 1
            XCTAssertEqual(ObjectIdentifier(generator.historyTexture), texture)
            XCTAssertEqual(generator.historyTexture.allocatedSize, bytes)
            XCTAssertEqual(UnsafeMutableRawPointer(generator.waterfallHistory.levels), storage)
        }
        finish(commands)
        XCTAssertEqual(checks, 13)
        XCTAssertEqual(generator.waterfallHistory.rowsWritten, 512)
        XCTAssertEqual(generator.historyTexture.width, 256)
        XCTAssertEqual(generator.historyTexture.height, 512)
        XCTAssertEqual(generator.historyTexture.pixelFormat, .r8Unorm)
        XCTAssertEqual(SpectrumWaterfallHistory.byteCount, 131_072)
        generator.restartLoop()
        XCTAssertEqual(generator.waterfallHistory.rowsWritten, 0, "a restart clears the history")
        XCTAssertEqual(ObjectIdentifier(generator.historyTexture), texture, "and keeps the texture")
    }

    private func render(_ rig: RenderRig, _ configuration: NoiseFieldConfiguration, builtAs initial: NoiseFieldConfiguration? = nil,
                        warmUp: NoiseFieldConfiguration? = nil) throws -> PixelImage {
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: initial ?? configuration)
        }
        let target = try rig.makeTexture(width: 48, height: 48, format: Self.format)
        if let warmUp {   // frames in another mode first (the waterfall's history must not survive the switch)
            generator.configuration = warmUp
            finish(try run(rig, generator, frames: 20, fps: 10, targets: [target]))
        }
        generator.configuration = configuration
        let commands = try run(rig, generator, frames: 20, fps: 10, targets: [target])
        let buffer = try rig.encodeReadBack(target, commands: commands)
        finish(commands)
        return rig.decode(RenderRig.bytes(of: buffer), width: 48, height: 48, format: Self.format)
    }

    func testSwitchingModesInPlaceGivesFreshFrames() throws {
        let rig = try RenderRig()
        let waterfall = NoiseFieldConfiguration.waterfall(palette: .ice)
        let plain = NoiseFieldConfiguration(palette: .ice)
        let fresh = try render(rig, waterfall)
        XCTAssertEqual(try render(rig, waterfall, builtAs: plain), fresh, "plain → waterfall")
        XCTAssertEqual(try render(rig, waterfall, builtAs: plain, warmUp: waterfall).pixels.count, fresh.pixels.count)
        XCTAssertEqual(try render(rig, waterfall, builtAs: waterfall, warmUp: plain), fresh, "waterfall → plain → waterfall: history cleared")
        XCTAssertEqual(try render(rig, plain, builtAs: waterfall), try render(rig, plain), "waterfall → plain")
        let tunnel = NoiseFieldConfiguration.tunnel(palette: .ice)
        XCTAssertEqual(try render(rig, tunnel, builtAs: waterfall), try render(rig, tunnel), "waterfall → tunnel")
    }
}
#endif
