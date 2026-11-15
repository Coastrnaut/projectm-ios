// TunnelRenderTests.swift — VIS-015-T06 (VIS-015-R1 to R5, R13; contract T3, T5): the tunnel on the real Metal pipeline
// (rgba16Float, an injected 60 Hz clock and tempo). The GPU frame agrees with the CPU mirror; two renders are identical;
// the centre is dark and no pixel is NaN; at 120 BPM the rings have moved twice as far as at 60 BPM (phase) and the
// pictures differ; switching an existing generator between the field, the kaleidoscope and the tunnel gives a fresh
// generator's frames. Without a Metal device the tests skip.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class TunnelRenderTests: XCTestCase {
    private static let frames = 12

    private func render(_ rig: RenderRig, _ configuration: NoiseFieldConfiguration, tempo: TunnelTempo = TunnelTempo(bpm: 120, confidence: 1),
                        width: Int = 64, height: Int = 64, builtAs initial: NoiseFieldConfiguration? = nil)
        throws -> (image: PixelImage, generator: NoiseFieldGenerator) {
        let format: MTLPixelFormat = .rgba16Float
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: format, configuration: initial ?? configuration)
        }
        generator.configuration = configuration
        generator.tempo = tempo
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let bands = [Float](repeating: 0.4, count: 64)
        for f in 0..<Self.frames {
            let context = VisualFrameContext(timeNanoseconds: UInt64(f) * 1_000_000_000 / 60, frameDuration: 1.0 / 60, reduceFlashing: false)
            let drawn: Bool = bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: texture, commandBuffer: commands, bands: b, context: context)
            }
            XCTAssertTrue(drawn)
        }
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return (rig.decode(RenderRig.bytes(of: buffer), width: width, height: height, format: format), generator)
    }

    func testTheGPUTunnelAgreesWithTheCPUMirror() throws {
        let rig = try RenderRig()
        let c = NoiseFieldConfiguration.tunnel(palette: .ice)
        let frame = try render(rig, c)
        let g = frame.generator
        XCTAssertEqual(g.tunnelDrive.phase, 2 * 11.0 / 60, accuracy: 1e-9, "2 rings/s for 11 frame steps")
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in c.palette.color(bar: k, of: 16).clamped }
        let lit: Float = Float(g.tunnelDrive.brightness) * g.lastGain
        var worst: Float = 0
        for (x, y) in [(3, 5), (20, 40), (40, 30), (50, 10), (60, 60), (8, 57), (33, 2)] {
            let p = SIMD2<Float>((Float(x) + 0.5 - 32) / 64, (Float(y) + 0.5 - 32) / 64)
            let s: (t: Float, light: Float) = TunnelMapping.sample(p, phase: Float(g.tunnelDrive.phase), seed: UInt32(c.seed))
            let base: LinearColor = stops.withUnsafeBufferPointer { (b: UnsafeBufferPointer<LinearColor>) -> LinearColor in
                NoiseFieldFlashAreas.paletteColor(s.t, stops: b.baseAddress!)
            }
            let scale: Float = s.light * lit
            let px: Pixel = frame.image[x, y]
            worst = max(worst, abs(px.x - base.red * scale), abs(px.y - base.green * scale), abs(px.z - base.blue * scale))
        }
        XCTAssertLessThan(worst, 0.02, "GPU vs CPU mirror")
        let centre: Pixel = frame.image[32, 32]
        XCTAssertLessThan(centre.x + centre.y + centre.z, 0.02, "dark at the centre")
        XCTAssertFalse(frame.image.pixels.contains { (p: Pixel) -> Bool in !(p.x.isFinite && p.y.isFinite && p.z.isFinite) })
        XCTAssertEqual(try render(rig, c).image, frame.image, "deterministic")
    }

    func testTempoChangesHowFarTheRingsMove() throws {
        let rig = try RenderRig()
        let c = NoiseFieldConfiguration.tunnel(palette: .mono)
        let slow = try render(rig, c, tempo: TunnelTempo(bpm: 60, confidence: 1))
        let fast = try render(rig, c, tempo: TunnelTempo(bpm: 120, confidence: 1))
        XCTAssertEqual(fast.generator.tunnelDrive.phase, 2 * slow.generator.tunnelDrive.phase, accuracy: 1e-9)
        var differing = 0
        for i in 0..<slow.image.pixels.count where abs(slow.image.pixels[i].y - fast.image.pixels[i].y) > 0.005 { differing += 1 }
        XCTAssertGreaterThan(differing, slow.image.pixels.count / 4, "the faster tunnel has moved further")
        let none = try render(rig, c, tempo: .none)
        XCTAssertEqual(none.generator.tunnelDrive.phase, 1.5 * 11.0 / 60, accuracy: 1e-9, "no tempo: base speed")
    }

    func testSwitchingModesInPlaceGivesFreshFrames() throws {
        let rig = try RenderRig()
        let tunnel = NoiseFieldConfiguration.tunnel(palette: .ice)
        let plain = NoiseFieldConfiguration(palette: .ice)
        let kaleidoscope = NoiseFieldConfiguration.kaleidoscope(wedges: 5, palette: .ice)
        let freshTunnel = try render(rig, tunnel)
        XCTAssertEqual(try render(rig, tunnel, builtAs: plain).image, freshTunnel.image, "plain → tunnel")
        XCTAssertEqual(try render(rig, tunnel, builtAs: kaleidoscope).image, freshTunnel.image, "kaleidoscope → tunnel")
        XCTAssertEqual(try render(rig, plain, builtAs: tunnel).image, try render(rig, plain).image, "tunnel → plain")
        XCTAssertEqual(try render(rig, kaleidoscope, builtAs: tunnel).image, try render(rig, kaleidoscope).image, "tunnel → kaleidoscope")
    }
}
#endif
