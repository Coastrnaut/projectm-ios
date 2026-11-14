// FX-009-T05 to T07, T09 to T11: Trails through the real Metal compositor (FX-009-R1 to R8, R12; S1 to S6, S8). The
// roadmap acceptance "Reset clears prior scene content in the first new frame": red frames with Trails on, a scene
// change, then blue — the first new frame is bit-identical to blue with Trails off, for every reset trigger. Small
// outputs (32 × 24) keep each test well under a second; frame times are injected (no clock). Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FlashSafety
import Metal
import XCTest

final class MotionFeedbackCompositeTests: XCTestCase {
    private static let start: UInt64 = 1_000_000_000
    private let red = Pixel(1, 0, 0, 1)
    private let blue = Pixel(0, 0, 1, 1)
    private let green = Pixel(0, 1, 0, 1)
    private let white = Pixel(1, 1, 1, 1)
    private let longest = MotionFeedback(isEnabled: true, halfLifeSeconds: 0.5)

    /// Frame `k` at `fps` (injected presentation times).
    private static func time(_ k: Int, fps: Double = 60) -> UInt64 { start + UInt64((Double(k) * 1e9 / fps).rounded()) }

    private func raw(_ rig: GPURig, _ texture: MTLTexture) throws -> [UInt16] {
        let bytesPerPixel: Int = texture.pixelFormat == .rgba16Float ? 8 : 4
        let rowBytes: Int = texture.width * bytesPerPixel
        let buffer = try XCTUnwrap(rig.device.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared))
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * texture.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let count: Int = rowBytes * texture.height / 2
        let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: count)
        return Array(UnsafeBufferPointer(start: halves, count: count))
    }

    /// The stack phase of frame `k` (`encodeScene`: the shown composite before the flash guard), read back raw.
    private func scene(_ rig: GPURig, _ compositor: Compositor, _ k: Int, width: Int = 32, height: Int = 24,
                       fps: Double = 60) throws -> [UInt16] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let shown = try XCTUnwrap(compositor.encodeScene(width: width, height: height, commandBuffer: commands,
                                                         presentationTimeNanoseconds: Self.time(k, fps: fps), contentScale: 2,
                                                         reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        return try raw(rig, shown)
    }

    private func sceneFloats(_ rig: GPURig, _ compositor: Compositor, _ k: Int, fps: Double = 60) throws -> [Pixel] {
        let halves: [UInt16] = try scene(rig, compositor, k, fps: fps)
        var out: [Pixel] = []
        for i in stride(from: 0, to: halves.count, by: 4) {
            out.append(Pixel(Half.toFloat(halves[i]), Half.toFloat(halves[i + 1]), Half.toFloat(halves[i + 2]),
                             Half.toFloat(halves[i + 3])))
        }
        return out
    }

    /// The first frame of `color` alone, Trails off (the reference "B alone").
    private func alone(_ rig: GPURig, _ color: Pixel, width: Int = 32, height: Int = 24) throws -> [UInt16] {
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("alone", color: color)])
        return try scene(rig, compositor, 0, width: width, height: height)
    }

    /// A compositor showing red with Trails on for five frames; returns it and its layer.
    private func redWithTrails(_ rig: GPURig, pool: TexturePool? = nil) throws -> (Compositor, SolidLayer) {
        let layer = SolidLayer("scene", color: red)
        let compositor = try Compositor(device: rig.device, layers: [layer], texturePool: pool)
        compositor.motionFeedback = longest
        for k in 0..<5 { _ = try scene(rig, compositor, k) }
        return (compositor, layer)
    }

    private func assertNoRed(_ halves: [UInt16], _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        var reds = 0
        for i in stride(from: 0, to: halves.count, by: 4) where Half.toFloat(halves[i]) != 0 { reds += 1 }
        XCTAssertEqual(reds, 0, "\(message): pixels with red", file: file, line: line)
    }

    // MARK: - US2: the acceptance (FX-009-S1)

    func testControlRedTrailsShowWithoutAReset() throws {
        let rig = try GPURig()
        let (compositor, layer) = try redWithTrails(rig)
        layer.color = blue
        let next: [UInt16] = try scene(rig, compositor, 5)
        XCTAssertNotEqual(next, try alone(rig, blue), "control: without a reset the red trail is visible")
        XCTAssertGreaterThan(Half.toFloat(next[0]), 0.9, "decayed red (0.977 per frame at 60 fps)")
    }

    func testFirstFrameAfterEachResetTriggerHasNoPriorSceneContent() throws {
        let rig = try GPURig()
        let blueAlone: [UInt16] = try alone(rig, blue)
        let triggers: [(String, (Compositor) -> Void)] = [
            ("resetFeedback (cue apply, scene reopen, undo/redo)", { (c: Compositor) -> Void in c.resetFeedback() }),
            ("resetFlashHistory (visual switch, frame-loop start)", { (c: Compositor) -> Void in c.resetFlashHistory() }),
            ("resetRenderHealth (PERF-014)", { (c: Compositor) -> Void in c.resetRenderHealth() }),
            ("Trails turned off and on", { (c: Compositor) -> Void in
                let value: MotionFeedback = c.motionFeedback
                c.motionFeedback = .off
                c.motionFeedback = value
            }),
        ]
        for (name, trigger) in triggers {
            let (compositor, layer) = try redWithTrails(rig)
            let resetsBefore: Int = compositor.trailsResets
            layer.color = blue
            trigger(compositor)
            let first: [UInt16] = try scene(rig, compositor, 5)
            XCTAssertEqual(first, blueAlone, "\(name): the first new frame is bit-identical to blue alone")
            assertNoRed(first, name)
            XCTAssertEqual(compositor.trailsResets, resetsBefore + 1, name)
            // Trails build up again from the new scene only.
            XCTAssertEqual(try scene(rig, compositor, 6), blueAlone, "\(name): a still blue scene trails into itself")
        }
    }

    func testSizeChangeStartsClean() throws {
        let rig = try GPURig()
        let (compositor, layer) = try redWithTrails(rig)
        layer.color = blue
        let first: [UInt16] = try scene(rig, compositor, 5, width: 40, height: 20)
        XCTAssertEqual(first, try alone(rig, blue, width: 40, height: 20), "a new size: blue alone")
        assertNoRed(first, "size change")
    }

    func testOutputFormatChangeStartsCleanInBothFormats() throws {
        let rig = try GPURig()
        let layer = SolidLayer("scene", color: red)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        compositor.motionFeedback = longest
        let half = try rig.output(.rgba16Float, width: 32, height: 24)
        let srgb = try rig.output(.bgra8Unorm_srgb, width: 32, height: 24)
        for k in 0..<5 { try rig.frame(compositor, into: half, time: Self.time(k)) }
        layer.color = blue
        try rig.frame(compositor, into: srgb, time: Self.time(5))
        XCTAssertEqual(compositor.lastFlashGain, 1)
        let reference = try Compositor(device: rig.device, layers: [SolidLayer("alone", color: blue)])
        let referenceOutput = try rig.output(.bgra8Unorm_srgb, width: 32, height: 24)
        try rig.frame(reference, into: referenceOutput, time: Self.time(0))
        XCTAssertEqual(try raw(rig, srgb), try raw(rig, referenceOutput), "screen format: bit-identical to blue alone")
        // And the half-float output after a scene change (the guard history reset with it, as at a loop start).
        layer.color = red
        try rig.frame(compositor, into: half, time: Self.time(6))
        try rig.frame(compositor, into: half, time: Self.time(7))
        layer.color = blue
        compositor.resetFlashHistory()
        try rig.frame(compositor, into: half, time: Self.time(8))
        let halfReference = try rig.output(.rgba16Float, width: 32, height: 24)
        let fresh = try Compositor(device: rig.device, layers: [SolidLayer("alone", color: blue)])
        try rig.frame(fresh, into: halfReference, time: Self.time(0))
        XCTAssertEqual(try raw(rig, half), try raw(rig, halfReference), "half float: bit-identical to blue alone")
    }

    func testTransitionStartClearsBothScenesTrails() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let bus = try SceneTransitionBus(device: rig.device, texturePool: pool)
        let layerA = SolidLayer("a", color: red)
        let layerB = SolidLayer("b", color: red)
        let a = try Compositor(device: rig.device, layers: [layerA], texturePool: pool)
        let b = try Compositor(device: rig.device, layers: [layerB], texturePool: pool)
        a.motionFeedback = longest
        b.motionFeedback = longest
        let output = try rig.output(.rgba16Float, width: 32, height: 24)
        var k = 0
        func busFrame() throws {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            XCTAssertTrue(bus.encodeFrame(into: output, commandBuffer: commands, presentationTimeNanoseconds: Self.time(k),
                                          contentScale: 2, reduceFlashing: false, audio: .empty))
            commands.commit()
            commands.waitUntilCompleted()
            k += 1
        }
        bus.show(b)
        for _ in 0..<3 { try busFrame() }   // B holds red trails
        bus.show(a)
        for _ in 0..<3 { try busFrame() }   // A holds red trails
        layerA.color = green
        layerB.color = blue
        bus.transition(to: b, spec: try SceneTransitionSpec(style: .crossfade, durationSeconds: 0.1, easing: .linear),
                       reduceMotion: false)
        try busFrame()   // progress 0: A alone
        assertNoRed(try raw(rig, output), "transition progress 0")
        try busFrame()   // a blend of A and B
        assertNoRed(try raw(rig, output), "transition blend")
    }

    // MARK: - US1: trails follow the reference (FX-009-R2, R3, S2)

    func testTrailingFramesFollowTheHalfLifeAt60And120() throws {
        let rig = try GPURig()
        for fps in [60.0, 120.0] {
            let layer = SolidLayer("patch", color: white)
            let compositor = try Compositor(device: rig.device, layers: [layer])
            let feedback = MotionFeedback(isEnabled: true, halfLifeSeconds: 0.2)
            compositor.motionFeedback = feedback
            _ = try scene(rig, compositor, 0, fps: fps)
            _ = try scene(rig, compositor, 1, fps: fps)   // white, history white
            layer.color = .zero   // the patch disappears (transparent)
            let d: Float = Float(feedback.decay(frameDuration: 1 / fps))
            let one: [Pixel] = try sceneFloats(rig, compositor, 2, fps: fps)
            let expected: Pixel = MotionFeedback.blend(current: .zero, previous: white, decay: d, reset: false)
            assertAll(one, equal: expected, tolerance: 0.001, "one frame of decay at \(fps) fps")
            let frames: Int = Int((0.2 * fps).rounded())   // one half-life in total
            var last: [Pixel] = one
            for j in 1..<frames { last = try sceneFloats(rig, compositor, 2 + j, fps: fps) }
            assertAll(last, equal: Pixel(0.5, 0.5, 0.5, 0.5), tolerance: 0.006, "one half-life at \(fps) fps")
            print("FX-009 S2: after one half-life (0.2 s) at \(fps) fps: \(last[0].x)")
        }
    }

    func testStillPictureTrailsIntoItselfAndTransparentStaysTransparent() throws {
        let rig = try GPURig()
        let half = Pixel(0.25, 0.1, 0.4, 0.5)
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("still", color: half)])
        let empty = try Compositor(device: rig.device, layers: [SolidLayer("empty", color: .zero)])
        compositor.motionFeedback = longest
        empty.motionFeedback = longest
        let reference: [UInt16] = try alone(rig, half)
        for k in 0..<6 {
            XCTAssertEqual(try scene(rig, compositor, k), reference, "frame \(k)")
            assertAll(try sceneFloats(rig, empty, k), equal: .zero, tolerance: 0, "transparent, frame \(k)")
        }
    }

    // MARK: - US3: off is exactly today (FX-009-R8, R12; S3, S4, S6)

    func testOffIsBitIdenticalAndHoldsNothing() throws {
        let rig = try GPURig()
        let colors: [Pixel] = [red, blue, Pixel(0.2, 0.7, 0.1, 0.8), white, .zero]
        let layerA = SolidLayer("a", color: red)
        let layerB = SolidLayer("b", color: red)
        let never = try Compositor(device: rig.device, layers: [layerA])
        let toggled = try Compositor(device: rig.device, layers: [layerB])
        toggled.motionFeedback = longest
        for format in [MTLPixelFormat.rgba16Float, .bgra8Unorm_srgb] {
            let outA = try rig.output(format, width: 32, height: 24)
            let outB = try rig.output(format, width: 32, height: 24)
            for (k, color) in colors.enumerated() {
                layerA.color = color
                layerB.color = color
                if k == 1 { toggled.motionFeedback = .off }
                try rig.frame(never, into: outA, time: Self.time(k))
                try rig.frame(toggled, into: outB, time: Self.time(k))
                if k >= 1 { XCTAssertEqual(try raw(rig, outA), try raw(rig, outB), "off frame \(k), format \(format.rawValue)") }
            }
            toggled.motionFeedback = longest
        }
        toggled.motionFeedback = .off
        XCTAssertFalse(never.holdsTrailsPictures)
        XCTAssertFalse(toggled.holdsTrailsPictures, "turning Trails off returns the pair")
        XCTAssertEqual(never.trailsFrames, 0, "no pass while off")
    }

    func testCompositeIsNeverReusedWhileTrailsAreActive() throws {
        let rig = try GPURig()
        let layer = StillLayer("still", color: Pixel(0.3, 0.2, 0.1, 1))
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output(width: 32, height: 24)
        compositor.motionFeedback = longest
        for k in 0..<5 { try rig.frame(compositor, into: output, time: Self.time(k)) }
        XCTAssertEqual(compositor.compositeReuses, 0, "no composite reuse while Trails are on")
        XCTAssertGreaterThan(compositor.renderCacheHits, 0, "layer pictures may still be reused")
        compositor.motionFeedback = .off
        for k in 5..<9 { try rig.frame(compositor, into: output, time: Self.time(k)) }
        XCTAssertGreaterThan(compositor.compositeReuses, 0, "off: CMP-013 reuses the composite as before")
    }

    func testPoolCheckoutsReturnAfterEnableDisableAndSizeCycles() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("s", color: red)], texturePool: pool)
        _ = try scene(rig, compositor, 0)
        let start: Int = pool.counters.checkedOutTextures
        var k = 1
        for cycle in 0..<6 {
            compositor.motionFeedback = longest
            let width: Int = cycle % 2 == 0 ? 32 : 40
            _ = try scene(rig, compositor, k, width: width, height: 24)
            k += 1
            XCTAssertEqual(pool.counters.checkedOutTextures, start + 2, "active: the pair (cycle \(cycle))")
            _ = try scene(rig, compositor, k, width: 48, height: 16)
            k += 1
            XCTAssertEqual(pool.counters.checkedOutTextures, start + 2, "a size change swaps the pair, never adds")
            compositor.motionFeedback = .off
            _ = try scene(rig, compositor, k)
            k += 1
            XCTAssertEqual(pool.counters.checkedOutTextures, start, "off: back to the start (cycle \(cycle))")
        }
        print("FX-009 S6: pool checked out at start \(start), after 6 enable/size/disable cycles \(pool.counters.checkedOutTextures)")
    }

    // MARK: - US4: safety (FX-009-R7, S5)

    private func minimumGain(_ rig: GPURig, feedback: MotionFeedback, clamp: SafetyClamp) throws -> Float {
        let layer = SolidLayer("strobe", color: white)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        compositor.motionFeedback = feedback.limited(by: clamp)
        compositor.flashLimits = clamp.flashLimitsOverride
        let output = try rig.output(width: 32, height: 24)
        var lowest: Float = 1
        for k in 0..<90 {   // 5 Hz white/black strobe at 60 fps: six frames on, six off
            layer.color = (k / 6) % 2 == 0 ? white : Pixel(0, 0, 0, 1)
            try rig.frame(compositor, into: output, time: Self.time(k), reduceFlashing: clamp.reducesFlashing)
            lowest = min(lowest, compositor.lastFlashGain)
        }
        return lowest
    }

    func testFlashGuardStillLimitsAStrobeWithTrails() throws {
        let rig = try GPURig()
        let standard: Float = try minimumGain(rig, feedback: MotionFeedback(isEnabled: true, halfLifeSeconds: 0.2), clamp: .standard)
        let strict = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
        let capped: MotionFeedback = longest.limited(by: strict)
        XCTAssertEqual(capped.halfLifeSeconds, 0.125, accuracy: 1e-12, "Strict caps the length")
        let strictGain: Float = try minimumGain(rig, feedback: longest, clamp: strict)
        XCTAssertLessThan(standard, 1, "Standard: the guard lowers its gain on a strobe with trails")
        XCTAssertLessThan(strictGain, 1, "Strict: the guard lowers its gain on a strobe with capped trails")
        print("FX-009 S5: lowest guard gain with trails: Standard \(standard), Strict \(strictGain)")
    }

    // MARK: - Performance (FX-009-T10, S8; recorded, not asserted)

    func testBenchTrailsGPUTime() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("bench", color: Pixel(0.4, 0.3, 0.2, 1))])
        let output = try rig.output(.bgra8Unorm_srgb, width: 1170, height: 2532)
        var k = 0
        /// The median GPU time (ms) of 50 frames after 10 warm-up frames.
        func median() throws -> Double {
            var times: [Double] = []
            for j in 0..<60 {
                let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
                XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: Self.time(k),
                                                   contentScale: 3, reduceFlashing: false, audio: .empty))
                commands.commit()
                commands.waitUntilCompleted()
                k += 1
                if j >= 10 { times.append((commands.gpuEndTime - commands.gpuStartTime) * 1000) }
            }
            times.sort()
            return times[times.count / 2]
        }
        compositor.isRenderCachingEnabled = false   // the same stack work in both runs
        var offRuns: [Double] = []
        var onRuns: [Double] = []
        for _ in 0..<3 {   // alternate, so warm-up and clock changes hit both
            compositor.motionFeedback = .off
            offRuns.append(try median())
            compositor.motionFeedback = longest
            onRuns.append(try median())
        }
        let off: Double = offRuns.min() ?? 0
        let on: Double = onRuns.min() ?? 0
        print(String(format: "FX-009 T10: 1170 × 2532 frame GPU time (median, best of 3): off %.3f ms, on %.3f ms, trails pass %.3f ms",
                     off, on, on - off))
        XCTAssertGreaterThan(on, 0)
    }
}
#endif
