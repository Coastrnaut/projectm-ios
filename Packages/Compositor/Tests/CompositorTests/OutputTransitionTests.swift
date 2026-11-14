// XFADE-T02, T03 (specs/167-cue-transitions-on-screen): the frozen-frame transition in the compositor's output path on
// the GPU. 64 × 64 rgba16Float outputs; frames on an injected 60 Hz clock (16 666 667 ns apart), so a 1 s transition is
// at progress 0.5 on its 30th frame after the start and ends on its 60th. Scene A is solid red, B solid blue; the blend
// is in linear light (the composite is linear premultiplied), so 50/50 is (0.5, 0, 0.5, 1). Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import ParameterGraph
import XCTest

final class OutputTransitionTests: XCTestCase {
    private static let start: UInt64 = 1_000_000_000
    private static let step: UInt64 = 16_666_667
    private let red = Pixel(1, 0, 0, 1)
    private let blue = Pixel(0, 0, 1, 1)
    private let white = Pixel(1, 1, 1, 1)
    private let black = Pixel(0, 0, 0, 1)

    private static func time(_ k: Int) -> UInt64 { start + UInt64(k) * step }

    private func spec(_ style: SceneTransitionStyle, seconds: Double = 1, curve: MappingCurve = .linear) throws -> SceneTransitionSpec {
        try SceneTransitionSpec(style: style, durationSeconds: seconds, easing: .linear, curve: curve)
    }

    /// The texture's raw half floats (equality is bit for bit).
    private func raw(_ rig: GPURig, _ texture: MTLTexture) throws -> [UInt16] {
        let rowBytes = texture.width * 8
        let buffer = try XCTUnwrap(rig.device.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared))
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * texture.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let count = texture.width * texture.height * 4
        let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: count)
        return Array(UnsafeBufferPointer(start: halves, count: count))
    }

    /// Frame `last` of `color` alone (a compositor that never transitioned), fed frames `first...last`.
    private func alone(_ rig: GPURig, _ color: Pixel, first: Int = 0, last: Int) throws -> [UInt16] {
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("alone", color: color)])
        let output = try rig.output()
        for k in first...last { try rig.frame(compositor, into: output, time: Self.time(k)) }
        return try raw(rig, output)
    }

    /// Freezes `compositor`'s shown frame on `queue` (another queue than the frames' when given).
    private func freeze(_ rig: GPURig, _ compositor: Compositor, queue: MTLCommandQueue? = nil) throws -> FrozenOutputFrame {
        let commands = try XCTUnwrap((queue ?? rig.queue).makeCommandBuffer())
        let frame = try XCTUnwrap(compositor.freezeShownFrame(commandBuffer: commands))
        commands.commit()
        return frame
    }

    private func mean(_ pixels: [Pixel]) -> Pixel {
        pixels.reduce(Pixel.zero, +) / Float(pixels.count)
    }

    // MARK: - XFADE-S1: the acceptance

    /// A red → B blue, 1 s linear crossfade at 60 Hz, across two compositors (the freeze on another queue).
    func testCrossfadeFromAFrozenFrameReachesExactStartMidpointAndEnd() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let a = try Compositor(device: rig.device, layers: [SolidLayer("A", color: red)], texturePool: pool)
        let b = try Compositor(device: rig.device, layers: [SolidLayer("B", color: blue)], texturePool: pool)
        let output = try rig.output()
        try rig.frame(a, into: output, time: Self.time(0))
        let aLast = try raw(rig, output)
        let freezeQueue = try XCTUnwrap(rig.device.makeCommandQueue())
        let frozen = try freeze(rig, a, queue: freezeQueue)
        let frozenTexture: MTLTexture = frozen.texture

        b.beginOutputTransition(from: frozen, spec: try spec(.crossfade), reduceMotion: false)
        XCTAssertTrue(b.isOutputTransitioning)
        try rig.frame(b, into: output, time: Self.time(1))
        XCTAssertEqual(b.outputTransitionProgress, 0)
        XCTAssertEqual(try raw(rig, output), aLast, "t = 0: A byte for byte")
        for k in 2...31 { try rig.frame(b, into: output, time: Self.time(k)) }
        XCTAssertEqual(b.outputTransitionProgress, 0.5, accuracy: 1e-6)
        assertAll(try rig.read(output), equal: Pixel(0.5, 0, 0.5, 1), tolerance: 0.002, "t = 0.5 s: 50/50 in linear light")
        XCTAssertTrue(b.holdsOutputTransitionTextures)
        for k in 32...60 { try rig.frame(b, into: output, time: Self.time(k)) }
        XCTAssertEqual(b.outputTransitionProgress, 0.98333, accuracy: 1e-4, "t = 59/60 s: still blending")
        try rig.frame(b, into: output, time: Self.time(61))
        XCTAssertEqual(b.outputTransitionProgress, 1)
        XCTAssertFalse(b.isOutputTransitioning)
        XCTAssertFalse(b.holdsOutputTransitionTextures, "both textures released at the end")
        XCTAssertEqual(try raw(rig, output), try alone(rig, blue, first: 1, last: 61), "t = 1 s: B byte for byte")
        XCTAssertEqual(b.outputTransitionBlendedFrames, 59, "frames 1/60 … 59/60 are blends")
        XCTAssertFalse(pool.isCheckedOut(frozenTexture), "the frozen frame is back in the pool")
        print("XFADE acceptance: blended frames \(b.outputTransitionBlendedFrames), progress at 0.5 s exact, ends at frame 60")
    }

    func testEaseInCurveShapesTheMix() throws {
        let rig = try GPURig()
        let layer = SolidLayer("scene", color: red)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: Self.time(0))
        let frozen = try freeze(rig, compositor)
        layer.color = blue   // the same compositor shows the next scene (Text → Text)
        compositor.beginOutputTransition(from: frozen, spec: try spec(.crossfade, curve: .easeIn(exponent: 2)), reduceMotion: false)
        for k in 1...31 { try rig.frame(compositor, into: output, time: Self.time(k)) }
        let eased = Float(MappingCurve.easeIn(exponent: 2).apply(0.5))
        XCTAssertEqual(eased, 0.25, accuracy: 1e-6)
        assertAll(try rig.read(output), equal: Pixel(1 - eased, 0, eased, 1), tolerance: 0.002, "t = 0.5 s: the curve's mix")
    }

    func testDipToBlackPassesThroughBlackAtTheMidpoint() throws {
        let rig = try GPURig()
        let layer = SolidLayer("scene", color: red)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: Self.time(0))
        let frozen = try freeze(rig, compositor)
        layer.color = blue
        compositor.beginOutputTransition(from: frozen, spec: try spec(.dipToBlack), reduceMotion: false)
        for k in 1...16 { try rig.frame(compositor, into: output, time: Self.time(k)) }
        let quarter = mean(try rig.read(output))
        XCTAssertEqual(quarter.x, 0.5, accuracy: 0.002, "t = 0.25 s: A at half")
        XCTAssertEqual(quarter.z, 0, accuracy: 0.002)
        for k in 17...31 { try rig.frame(compositor, into: output, time: Self.time(k)) }
        let midpoint = try rig.read(output)
        assertAll(midpoint.map { (p: Pixel) -> Pixel in Pixel(p.x, p.y, p.z, 0) }, equal: .zero, tolerance: 0.002, "t = 0.5 s: black")
        for k in 32...46 { try rig.frame(compositor, into: output, time: Self.time(k)) }
        let threeQuarters = mean(try rig.read(output))
        XCTAssertEqual(threeQuarters.z, 0.5, accuracy: 0.002, "t = 0.75 s: B at half")
        XCTAssertEqual(threeQuarters.x, 0, accuracy: 0.002)
    }

    // MARK: - XFADE-S2: cut and Reduce Motion

    func testACutAndReduceMotionChangeNothingOnTheOutputPath() throws {
        let rig = try GPURig()
        for (style, reduceMotion) in [(SceneTransitionStyle.cut, false), (.crossfade, true)] {
            let pool = TexturePool(device: rig.device)
            let layer = SolidLayer("scene", color: red)
            let compositor = try Compositor(device: rig.device, layers: [layer], texturePool: pool)
            let output = try rig.output()
            try rig.frame(compositor, into: output, time: Self.time(0))
            let frozen = try freeze(rig, compositor)
            layer.color = blue
            compositor.beginOutputTransition(from: frozen, spec: try spec(style), reduceMotion: reduceMotion)
            XCTAssertFalse(compositor.isOutputTransitioning, "\(style), Reduce Motion \(reduceMotion): a cut")
            try rig.frame(compositor, into: output, time: Self.time(1))
            XCTAssertEqual(try raw(rig, output), try alone(rig, blue, first: 1, last: 1), "the next frame is B alone, byte for byte")
            XCTAssertEqual(compositor.outputTransitionBlendedFrames, 0)
            XCTAssertFalse(compositor.holdsOutputTransitionTextures)
        }
        // A compositor that never froze takes nothing for transitions.
        let plain = try Compositor(device: rig.device, layers: [SolidLayer("plain", color: red)])
        XCTAssertFalse(plain.holdsOutputTransitionTextures)
        XCTAssertEqual(plain.outputTransitionProgress, 1)
    }

    // MARK: - XFADE-R7: a cue during a transition

    func testACueDuringATransitionRestartsFromTheBlendedFrame() throws {
        let rig = try GPURig()
        let layer = SolidLayer("scene", color: red)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: Self.time(0))
        compositor.beginOutputTransition(from: try freeze(rig, compositor), spec: try spec(.crossfade), reduceMotion: false)
        layer.color = blue
        for k in 1...31 { try rig.frame(compositor, into: output, time: Self.time(k)) }
        let blended = try raw(rig, output)   // (0.5, 0, 0.5)
        compositor.beginOutputTransition(from: try freeze(rig, compositor), spec: try spec(.crossfade), reduceMotion: false)
        layer.color = white
        try rig.frame(compositor, into: output, time: Self.time(32))
        XCTAssertEqual(compositor.outputTransitionProgress, 0, "restarted")
        XCTAssertEqual(try raw(rig, output), blended, "no jump: the new transition starts at the blended frame")
        XCTAssertEqual(compositor.outputTransitionsStarted, 2)
        for k in 33...62 { try rig.frame(compositor, into: output, time: Self.time(k)) }
        assertAll(try rig.read(output), equal: Pixel(0.75, 0.5, 0.75, 1), tolerance: 0.002, "halfway from the blend to white")
    }

    // MARK: - XFADE-S3: no leaks

    func testTwentyTransitionsLeakNoTexture() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let layer = SolidLayer("scene", color: red)
        let compositor = try Compositor(device: rig.device, layers: [layer], texturePool: pool)
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: Self.time(0))
        let idle = pool.counters.checkedOutTextures
        var k = 1
        var peak = idle
        for n in 0..<20 {
            compositor.beginOutputTransition(from: try freeze(rig, compositor), spec: try spec(.crossfade, seconds: 0.05),
                                             reduceMotion: false)
            layer.color = n % 2 == 0 ? blue : red
            for _ in 0..<5 {
                try rig.frame(compositor, into: output, time: Self.time(k))
                peak = max(peak, pool.counters.checkedOutTextures)
                k += 1
            }
            XCTAssertFalse(compositor.isOutputTransitioning, "transition \(n) ended")
        }
        // A frozen frame no transition took goes back by itself.
        _ = try freeze(rig, compositor)
        try rig.frame(compositor, into: output, time: Self.time(k))
        XCTAssertEqual(peak, idle + 2, "while transitioning: the frozen frame and the blend target")
        XCTAssertEqual(pool.counters.checkedOutTextures, idle, "after 20 transitions: nothing leaked")
        XCTAssertEqual(compositor.outputTransitionsStarted, 20)
        print("XFADE leaks: idle \(idle), peak \(peak), after \(pool.counters.checkedOutTextures), live \(pool.counters.liveTextures)")
    }

    // MARK: - XFADE-S4, R3: the flash guard and the other outputs see the blend

    func testTheFlashGuardLimitsAStrobingTransitionSequence() throws {
        let rig = try GPURig()
        let layer = SolidLayer("scene", color: black)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: Self.time(0))
        var minimum: Float = 1
        var brightFrames = 0
        for k in 1...90 {
            if k % 3 == 1 {   // a cue every 3 frames, alternating white and black, each a 2-frame crossfade
                compositor.beginOutputTransition(from: try freeze(rig, compositor), spec: try spec(.crossfade, seconds: 2.0 / 60),
                                                 reduceMotion: false)
                layer.color = (k / 3) % 2 == 0 ? white : black
            }
            try rig.frame(compositor, into: output, time: Self.time(k))
            minimum = min(minimum, compositor.lastFlashGain)
            if mean(try rig.read(output)).x > 0.05 { brightFrames += 1 }
        }
        XCTAssertGreaterThan(compositor.outputTransitionBlendedFrames, 0, "the sequence blended")
        XCTAssertLessThan(minimum, 1, "the guard limited the blended frames")
        XCTAssertGreaterThan(brightFrames, 0, "not simply blacked out")
        print("XFADE strobe: minimum gain \(minimum), blended \(compositor.outputTransitionBlendedFrames)")
    }

    func testRecordingOutputRepeatsTheBlend() throws {
        let rig = try GPURig()
        let layer = SolidLayer("scene", color: red)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output()
        let recording = try rig.output(width: 32, height: 32)
        try rig.frame(compositor, into: output, time: Self.time(0))
        compositor.beginOutputTransition(from: try freeze(rig, compositor), spec: try spec(.crossfade), reduceMotion: false)
        layer.color = blue
        for k in 1...30 { try rig.frame(compositor, into: output, time: Self.time(k)) }
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: Self.time(31),
                                           contentScale: 2, reduceFlashing: false, audio: .empty))
        XCTAssertTrue(compositor.encodeOutput(into: recording, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        assertAll(try rig.read(recording), equal: Pixel(0.5, 0, 0.5, 1), tolerance: 0.002, "the recording shows the blend")
    }

    func testFreezeNeedsAShownFrame() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("scene", color: red)])
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertNil(compositor.freezeShownFrame(commandBuffer: commands), "nothing shown yet")
        commands.commit()
    }
}
#endif
