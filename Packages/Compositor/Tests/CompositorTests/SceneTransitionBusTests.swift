// CMP-014-T06 to T10, T12: the transition bus on the GPU (the roadmap acceptance "Crossfade reaches exact
// start/end states with no leaked textures"). 64 × 64 rgba16Float outputs read back byte for byte; frames are
// 25 ms apart (injected presentation times) so a 0.1 s transition is exactly four frames: progress 0, 0.25,
// 0.5, 0.75, then 1. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import XCTest

/// A still layer that opts into CMP-013 caching (its picture never changes).
private final class TransitionStillLayer: LayerSource, LayerRenderCaching {
    let layerName: String
    let fallback = LayerFallback.transparent
    let color: Pixel
    private(set) var renders = 0

    init(_ name: String, color: Pixel) {
        layerName = name
        self.color = color
    }

    var renderDependencies: LayerRenderDependencies { .still(content: 1) }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        renders += 1
        SolidLayer.clear(picture, to: color, commandBuffer: commandBuffer)
    }
}

final class SceneTransitionBusTests: XCTestCase {
    private static let start: UInt64 = 1_000_000_000
    private static let step: UInt64 = 25_000_000
    private let red = Pixel(1, 0, 0, 1)
    private let blue = Pixel(0, 0, 1, 1)
    private let green = Pixel(0, 1, 0, 1)
    private let white = Pixel(1, 1, 1, 1)
    private let black = Pixel(0, 0, 0, 1)

    private static func time(_ k: Int) -> UInt64 { start + UInt64(k) * step }

    private func tenth(_ style: SceneTransitionStyle = .crossfade, _ easing: SceneTransitionEasing = .easeInOut) throws -> SceneTransitionSpec {
        try SceneTransitionSpec(style: style, durationSeconds: 0.1, easing: easing)
    }

    private func scene(_ rig: GPURig, _ color: Pixel, pool: TexturePool, still: Bool = false) throws -> Compositor {
        let layer: any LayerSource = still ? TransitionStillLayer("still", color: color) : SolidLayer("solid", color: color)
        return try Compositor(device: rig.device, layers: [layer], texturePool: pool)
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

    /// One bus frame, committed and waited for; `extra` also receives `encodeOutput`.
    @discardableResult
    private func frame(_ rig: GPURig, _ bus: SceneTransitionBus, _ k: Int, into output: MTLTexture, extra: MTLTexture? = nil,
                       reduceFlashing: Bool = false) throws -> Bool {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let ok = bus.encodeFrame(into: output, commandBuffer: commands, presentationTimeNanoseconds: Self.time(k),
                                 contentScale: 2, reduceFlashing: reduceFlashing, audio: .empty)
        if let extra { XCTAssertTrue(bus.encodeOutput(into: extra, commandBuffer: commands)) }
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        return ok
    }

    /// Frame `last` of `color` alone through `Compositor.composite(into:)`, fed frames `first...last`.
    private func alone(_ rig: GPURig, _ color: Pixel, first: Int = 0, last: Int, size: Int = 64) throws -> [UInt16] {
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("alone", color: color)])
        let output = try rig.output(width: size, height: size)
        for k in first...last { try rig.frame(compositor, into: output, time: Self.time(k)) }
        return try raw(rig, output)
    }

    private func assertNear(_ pixels: [Pixel], _ expected: Pixel, tolerance: Float = 0.002, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        var worst: Float = 0
        for p in pixels {
            let d: Pixel = p - expected
            let channel: Float = max(max(abs(d.x), abs(d.y)), max(abs(d.z), abs(d.w)))
            worst = max(worst, channel)
        }
        XCTAssertLessThanOrEqual(worst, tolerance, "\(message): worst channel error \(worst)", file: file, line: line)
    }

    // MARK: - US1: the acceptance

    func testCrossfadeReachesExactStartAndEndWithNoLeakedTextures() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let output = try rig.output()
        bus.show(try scene(rig, red, pool: pool))
        try frame(rig, bus, 0, into: output)
        let before = pool.counters.checkedOutTextures

        bus.transition(to: try scene(rig, blue, pool: pool), spec: try tenth(), reduceMotion: false)
        XCTAssertTrue(bus.isTransitioning)
        try frame(rig, bus, 1, into: output)
        XCTAssertEqual(bus.lastProgress, 0)
        XCTAssertEqual(try raw(rig, output), try alone(rig, red, last: 1), "progress 0 is byte-identical to A alone")
        try frame(rig, bus, 2, into: output)
        try frame(rig, bus, 3, into: output)
        XCTAssertEqual(bus.lastProgress, 0.5)
        assertNear(try rig.read(output), Pixel(0.5, 0, 0.5, 1), "the midpoint is the reference blend")
        XCTAssertTrue(bus.holdsBlendTarget)
        let during = pool.counters.checkedOutTextures
        XCTAssertEqual(during, before * 2 + 1, "during: both scenes plus the blend target")
        try frame(rig, bus, 4, into: output)
        try frame(rig, bus, 5, into: output)
        XCTAssertEqual(bus.lastProgress, 1)
        XCTAssertFalse(bus.isTransitioning, "the outgoing scene is released at progress 1")
        XCTAssertFalse(bus.holdsBlendTarget)
        XCTAssertEqual(try raw(rig, output), try alone(rig, blue, last: 5), "progress 1 is byte-identical to B alone")
        try frame(rig, bus, 6, into: output)
        XCTAssertEqual(try raw(rig, output), try alone(rig, blue, last: 6), "and after")
        XCTAssertEqual(bus.blendedFrames, 3)
        XCTAssertEqual(pool.counters.checkedOutTextures, before, "no leaked textures")
        print("CMP-014 acceptance: pool checked out before \(before), during \(during), after \(pool.counters.checkedOutTextures)")
    }

    func testCancelReturnsToTheOutgoingSceneWithNoLeakedTextures() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let output = try rig.output()
        bus.show(try scene(rig, red, pool: pool))
        try frame(rig, bus, 0, into: output)
        let before = pool.counters.checkedOutTextures
        bus.transition(to: try scene(rig, blue, pool: pool), spec: try tenth(), reduceMotion: false)
        for k in 1...3 { try frame(rig, bus, k, into: output) }
        bus.cancel()
        XCTAssertFalse(bus.isTransitioning)
        XCTAssertFalse(bus.holdsBlendTarget)
        try frame(rig, bus, 4, into: output)
        XCTAssertEqual(try raw(rig, output), try alone(rig, red, last: 4), "after cancel the output is A alone")
        XCTAssertEqual(pool.counters.checkedOutTextures, before, "no leaked textures after cancel")
        print("CMP-014 cancel: pool checked out before \(before), after \(pool.counters.checkedOutTextures)")
    }

    func testInterruptionSnapsThenStartsWithNoLeakedTextures() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let output = try rig.output()
        bus.show(try scene(rig, red, pool: pool))
        try frame(rig, bus, 0, into: output)
        let before = pool.counters.checkedOutTextures
        bus.transition(to: try scene(rig, blue, pool: pool), spec: try tenth(), reduceMotion: false)
        for k in 1...3 { try frame(rig, bus, k, into: output) }
        // Mid-transition: a new cue. A is released, B (the old incoming) is the one left.
        bus.transition(to: try scene(rig, green, pool: pool), spec: try tenth(), reduceMotion: false)
        XCTAssertTrue(bus.isTransitioning)
        try frame(rig, bus, 4, into: output)
        XCTAssertEqual(bus.lastProgress, 0)
        XCTAssertEqual(try raw(rig, output), try alone(rig, blue, last: 4), "the new transition starts exactly at B")
        for k in 5...8 { try frame(rig, bus, k, into: output) }
        XCTAssertFalse(bus.isTransitioning)
        XCTAssertEqual(try raw(rig, output), try alone(rig, green, last: 8), "and ends exactly at C")
        XCTAssertEqual(pool.counters.checkedOutTextures, before, "no leaked textures after an interruption")
        print("CMP-014 interruption: pool checked out before \(before), after \(pool.counters.checkedOutTextures)")
    }

    func testDipToBlackMidpointIsBlackAndExtraOutputMatches() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let output = try rig.output()
        let extra = try rig.output()
        bus.show(try scene(rig, red, pool: pool))
        try frame(rig, bus, 0, into: output)
        bus.transition(to: try scene(rig, blue, pool: pool), spec: try tenth(.dipToBlack, .linear), reduceMotion: false)
        try frame(rig, bus, 1, into: output)
        try frame(rig, bus, 2, into: output, extra: extra)
        assertNear(try rig.read(output), Pixel(0.5, 0, 0, 0.5), "a quarter in: A at half")
        XCTAssertEqual(try raw(rig, extra), try raw(rig, output), "encodeOutput gives the shown frame (recording, a second display)")
        try frame(rig, bus, 3, into: output)
        XCTAssertTrue(try raw(rig, output).allSatisfy { $0 == 0 }, "the midpoint is black")
        try frame(rig, bus, 4, into: output)
        assertNear(try rig.read(output), Pixel(0, 0, 0.5, 0.5), "three quarters in: B at half")
    }

    func testSizeChangeMidTransitionLeaksNothing() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let large = try rig.output()
        let small = try rig.output(width: 32, height: 32)
        bus.show(try scene(rig, red, pool: pool))
        try frame(rig, bus, 0, into: large)
        let before = pool.counters.checkedOutTextures
        bus.transition(to: try scene(rig, blue, pool: pool), spec: try tenth(), reduceMotion: false)
        for k in 1...2 { try frame(rig, bus, k, into: large) }
        for k in 3...6 { try frame(rig, bus, k, into: small) }
        XCTAssertFalse(bus.isTransitioning)
        XCTAssertEqual(pool.counters.checkedOutTextures, before, "same number of textures checked out (at the new size)")
    }

    // MARK: - US2: one clock

    func testBusClockPausesAndEndsAtTheDuration() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let output = try rig.output()
        bus.show(try scene(rig, red, pool: pool))
        try frame(rig, bus, 0, into: output)
        bus.transition(to: try scene(rig, blue, pool: pool), spec: try tenth(.crossfade, .linear), reduceMotion: false)
        try frame(rig, bus, 1, into: output)
        try frame(rig, bus, 2, into: output)
        XCTAssertEqual(bus.lastProgress, 0.25)
        bus.pause()
        try frame(rig, bus, 400, into: output)   // 10 s later
        XCTAssertEqual(bus.lastProgress, 0.25, "a pause of any length leaves progress where it was")
        try frame(rig, bus, 401, into: output)
        XCTAssertEqual(bus.lastProgress, 0.5)
        try frame(rig, bus, 402, into: output)
        XCTAssertEqual(bus.lastProgress, 0.75)
        XCTAssertTrue(bus.isTransitioning)
        try frame(rig, bus, 403, into: output)
        XCTAssertEqual(bus.lastProgress, 1)
        XCTAssertFalse(bus.isTransitioning, "finished exactly at the duration of shown frame time")
    }

    // MARK: - US3: Reduce Motion, CMP-013, flash safety

    func testReduceMotionGivesAnInstantSwitch() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let output = try rig.output()
        bus.show(try scene(rig, red, pool: pool))
        try frame(rig, bus, 0, into: output)
        bus.transition(to: try scene(rig, blue, pool: pool), spec: .defaultCrossfade, reduceMotion: true)
        XCTAssertFalse(bus.isTransitioning)
        try frame(rig, bus, 1, into: output)
        XCTAssertEqual(bus.blendedFrames, 0)
        XCTAssertEqual(try raw(rig, output), try alone(rig, blue, last: 1), "the next frame is B alone")
    }

    func testRenderCachingNeverFreezesATransition() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let output = try rig.output()
        bus.show(try scene(rig, red, pool: pool, still: true))
        for k in 0...2 { try frame(rig, bus, k, into: output) }
        XCTAssertEqual(bus.liveScene?.compositeReused, true, "a static scene reuses its composite")
        bus.transition(to: try scene(rig, blue, pool: pool, still: true), spec: try tenth(.crossfade, .linear), reduceMotion: false)
        try frame(rig, bus, 3, into: output)
        var previous = try raw(rig, output)
        for k in 4...6 {
            try frame(rig, bus, k, into: output)
            XCTAssertEqual(bus.outgoingScene?.compositeReused, true, "frame \(k): A reuses its composite")
            XCTAssertEqual(bus.liveScene?.compositeReused, true, "frame \(k): B reuses its composite")
            let now = try raw(rig, output)
            XCTAssertNotEqual(now, previous, "frame \(k): the blended frame is drawn anew")
            previous = now
        }
        XCTAssertEqual(bus.blendedFrames, 3)
    }

    func testFlashGuardLimitsTransitionFrames() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let output = try rig.output()
        let bright = try scene(rig, white, pool: pool)
        let dark = try scene(rig, black, pool: pool)
        let fast = try SceneTransitionSpec(style: .crossfade, durationSeconds: 0.05, easing: .linear)
        bus.show(bright)
        var minimum: Float = 1
        for k in 0..<48 {
            if k % 2 == 0, k > 0 { bus.transition(to: bus.liveScene === bright ? dark : bright, spec: fast, reduceMotion: false) }
            try frame(rig, bus, k, into: output, reduceFlashing: true)
            minimum = min(minimum, bus.lastFlashGain)
        }
        XCTAssertGreaterThan(bus.blendedFrames, 0, "the frames went through the transition path")
        XCTAssertLessThan(minimum, 1, "the flash guard limits a 10 Hz back-and-forth crossfade")
        print("CMP-014 flash: blended frames \(bus.blendedFrames), lowest guard gain \(minimum)")
    }

    // MARK: - US4: GPU time (recorded only)

    func testGPUTimeOfTransitionFramesIsRecorded() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let output = try rig.output(.bgra8Unorm_srgb, width: 1920, height: 1080)
        func threeLayers(_ color: Pixel) throws -> Compositor {
            try Compositor(device: rig.device, layers: [SolidLayer("a", color: color), SolidLayer("b", color: color * 0.5),
                                                       SolidLayer("c", color: color * 0.25)], texturePool: pool)
        }
        func gpuMilliseconds(_ k: Int) throws -> Double {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            XCTAssertTrue(bus.encodeFrame(into: output, commandBuffer: commands, presentationTimeNanoseconds: Self.time(k),
                                          contentScale: 2, reduceFlashing: true, audio: .empty))
            commands.commit()
            commands.waitUntilCompleted()
            return (commands.gpuEndTime - commands.gpuStartTime) * 1000
        }
        bus.show(try threeLayers(red))
        for k in 0..<3 { _ = try gpuMilliseconds(k) }   // warm-up
        var single: [Double] = []
        for k in 3..<13 { single.append(try gpuMilliseconds(k)) }
        bus.transition(to: try threeLayers(blue), spec: try SceneTransitionSpec(style: .crossfade, durationSeconds: 10), reduceMotion: false)
        _ = try gpuMilliseconds(13)
        var blended: [Double] = []
        for k in 14..<24 { blended.append(try gpuMilliseconds(k)) }
        let median = { (values: [Double]) -> Double in values.sorted()[values.count / 2] }
        print(String(format: "CMP-014 GPU 1920x1080: single-scene median %.3f ms, transition median %.3f ms (10 frames each)",
                     median(single), median(blended)))
        XCTAssertEqual(bus.blendedFrames, 10)
    }
}
#endif
