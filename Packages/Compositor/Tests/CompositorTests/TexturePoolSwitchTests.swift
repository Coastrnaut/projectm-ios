// PERF-004-T05, T06, T09, T10: the Metal texture pool and the compositor on the GPU (PERF-004-R1 to
// R9; S1 to S4). The acceptance (S1, the roadmap row "Hundred scene switches do not grow live texture
// count indefinitely") applies 100 alternating stacks with new layer IDs every switch, resizes every 10th
// switch and renders a frame after each. Small sizes (64 × 48) keep every test well under 2 s. Skipped
// without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Dispatch
import Metal
import XCTest

final class TexturePoolSwitchTests: XCTestCase {
    private static let kind = LayerKind("test.pool.solid")

    private func pictureDescriptor(width: Int = 64, height: Int = 48) -> MTLTextureDescriptor {
        LayerPictureDescriptor(width: width, height: height)!.textureDescriptor()
    }

    /// Replaces every entry of `stack` with new ones (new IDs): a scene switch.
    private func switchScene(_ stack: inout LayerStack, colors: [Pixel], lastGood: [Bool]) throws {
        for entry in stack.entries { _ = try stack.remove(entry.id) }
        for (c, keep) in zip(colors, lastGood) {
            try stack.add(LayerDescriptor(kind: Self.kind, parameters: ["r": Double(c.x), "g": Double(c.y), "b": Double(c.z),
                                                                        "a": Double(c.w), "lastGood": keep ? 1 : 0]))
        }
    }

    private func apply(_ stack: LayerStack, _ compositor: Compositor) throws {
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            let p = entry.descriptor.parameters
            return SolidLayer("solid \(entry.id)", color: Pixel(Float(p["r"] ?? 0), Float(p["g"] ?? 0), Float(p["b"] ?? 0), Float(p["a"] ?? 0)),
                              fallback: p["lastGood"] == 1 ? .lastGoodFrame : .transparent)
        }
    }

    // MARK: - T05: the Metal pool

    func testATextureIsReusedOnlyAfterItsCommandBufferCompleted() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let d = pictureDescriptor()
        let a = try XCTUnwrap(pool.makeTexture(descriptor: d))
        let pending = try XCTUnwrap(rig.queue.makeCommandBuffer())   // never committed: never completes
        pool.recycle([a], after: pending)
        XCTAssertEqual(pool.counters.waitingTextures, 1)
        let b = try XCTUnwrap(pool.makeTexture(descriptor: d))
        XCTAssertFalse(a === b, "the GPU may still use a")
        let done = try XCTUnwrap(rig.queue.makeCommandBuffer())
        done.commit()
        done.waitUntilCompleted()
        pool.recycle([b], after: done)
        XCTAssertTrue(pool.makeTexture(descriptor: d) === b, "b's frame completed")
        XCTAssertEqual(pool.counters.hits, 1)
        XCTAssertEqual(pool.counters.misses, 2)
        _ = pending   // kept uncommitted to the end
    }

    func testDifferentDescriptionsMissAndPurgeAndForeignTextures() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let a = try XCTUnwrap(pool.makeTexture(descriptor: pictureDescriptor()))
        pool.recycle([a], after: nil)
        let other = pictureDescriptor()
        other.usage = [.shaderRead]
        XCTAssertFalse(pool.makeTexture(descriptor: other) === a, "another usage misses")
        XCTAssertFalse(pool.makeTexture(descriptor: pictureDescriptor(width: 65)) === a, "another size misses")
        XCTAssertEqual(pool.counters.retiredTextures, 1)
        XCTAssertGreaterThanOrEqual(pool.counters.retiredBytes, 64 * 48 * 8, "bytes from allocatedSize")
        pool.purge()
        XCTAssertEqual(pool.counters.retiredTextures, 0)
        XCTAssertEqual(pool.counters.purged, 1)
        let stranger = try XCTUnwrap(rig.device.makeTexture(descriptor: pictureDescriptor()))
        XCTAssertFalse(pool.recycle(stranger, after: nil), "not from this pool")
        XCTAssertEqual(TexturePool(device: rig.device).limits,
                       TexturePoolLimits.default(recommendedWorkingSetBytes: rig.device.recommendedMaxWorkingSetSize))
    }

    func testTwoThreadsShareAPool() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device, limits: TexturePoolLimits(maxRetiredBytes: 1 << 20, maxIdleFrames: 300))
        DispatchQueue.concurrentPerform(iterations: 2) { (thread: Int) in
            let d = LayerPictureDescriptor(width: 16 + thread, height: 16)!.textureDescriptor()
            for _ in 0..<100 {
                guard let t = pool.makeTexture(descriptor: d) else { continue }
                pool.recycle(t, after: nil)
                pool.tick()
            }
        }
        let c = pool.counters
        XCTAssertEqual(c.hits + c.misses, 200)
        XCTAssertEqual(c.checkedOutTextures, 0)
        XCTAssertEqual(c.liveTextures, c.retiredTextures)
        XCTAssertLessThanOrEqual(c.misses, 2 + c.evictions, "each thread's texture is reused")
    }

    // MARK: - T06: the acceptance (S1, S2)

    private struct SwitchRun {
        var live: [Int] = []
        var liveBytes: [Int] = []
        var misses: [Int] = []
        var allocated: [Int] = []
    }

    /// 100 switches between a 2-layer stack (3 pictures) and a 3-layer stack (4 pictures), a resize every
    /// 10th switch between 64 × 48 and 48 × 64, one completed frame after each.
    private func runSwitches(_ rig: GPURig, _ compositor: Compositor, _ pool: TexturePool) throws -> SwitchRun {
        let outputs = [try rig.output(width: 64, height: 48), try rig.output(width: 48, height: 64)]
        var stack = LayerStack()
        var run = SwitchRun()
        var time: UInt64 = 1_000_000_000
        for s in 1...100 {
            if s % 2 == 0 {
                try switchScene(&stack, colors: [Pixel(1, 0, 0, 1), Pixel(0, 0, 1, 0.5)], lastGood: [true, false])
            } else {
                try switchScene(&stack, colors: [Pixel(0, 1, 0, 1), Pixel(0, 0, 0, 0), Pixel(1, 1, 0, 0.5)], lastGood: [false, false, true])
            }
            try apply(stack, compositor)
            time += 16_666_667
            XCTAssertTrue(try rig.frame(compositor, into: outputs[(s / 10) % 2], time: time))
            let c = pool.counters
            run.live.append(c.liveTextures)
            run.liveBytes.append(c.liveBytes)
            run.misses.append(c.misses)
            run.allocated.append(rig.device.currentAllocatedSize)
        }
        return run
    }

    func testHundredSceneSwitchesKeepLiveTexturesBounded() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device, limits: TexturePoolLimits())
        var compositor: Compositor? = try Compositor(device: rig.device, texturePool: pool)
        let run = try runSwitches(rig, try XCTUnwrap(compositor), pool)

        // Per size: the composite plus at most 4 layer pictures in use; the other size stays retired
        // (300-frame age limit, 128 MiB cap): 2 × 5 textures.
        let bound = 10
        XCTAssertLessThanOrEqual(run.live.max() ?? .max, bound, "live textures: \(run.live)")
        XCTAssertEqual(run.live[19], run.live[99], "plateau: switch 20 and switch 100")
        XCTAssertEqual(run.liveBytes[19], run.liveBytes[99], "plateau in bytes")
        XCTAssertEqual(run.misses[19], run.misses[99], "no texture created after warm-up: \(run.misses)")
        // Whole device (layers' own resources included): no growth after warm-up beyond 1 MiB of driver noise.
        XCTAssertLessThanOrEqual(run.allocated[99], run.allocated[19] + (1 << 20),
                                 "device allocation at switch 20 \(run.allocated[19]) and 100 \(run.allocated[99])")
        print("PERF-004 acceptance: live textures \(run.live[99]) (max \(run.live.max() ?? 0)), live bytes \(run.liveBytes[99]), "
              + "pool misses \(run.misses[99]), hits \(pool.counters.hits), device allocated \(run.allocated[19]) → \(run.allocated[99])")

        // S2: at a steady size and stack, 60 frames take no picture.
        let taken = compositor!.pictureAllocations, misses = pool.counters.misses, hits = pool.counters.hits
        let output = try rig.output(width: 64, height: 48)   // the size of switch 100 ((100 / 10) % 2 == 0)
        for f in 0..<60 { try rig.frame(compositor!, into: output, time: 3_000_000_000 + UInt64(f) * 16_666_667) }
        XCTAssertEqual(compositor!.pictureAllocations, taken)
        XCTAssertEqual(pool.counters.misses, misses)
        XCTAssertEqual(pool.counters.hits, hits)

        // Releasing the compositor returns every picture.
        compositor = nil
        XCTAssertEqual(pool.counters.checkedOutTextures, 0)
        XCTAssertEqual(pool.counters.liveTextures, pool.counters.retiredTextures)
    }

    func testWithoutReuseTheSameRunCreatesATextureForEverySwitch() throws {
        // The baseline: a pool that keeps nothing behaves like the compositor before PERF-004.
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device, limits: TexturePoolLimits(maxRetiredBytes: 0))
        let compositor = try Compositor(device: rig.device, texturePool: pool)
        let run = try runSwitches(rig, compositor, pool)
        XCTAssertGreaterThanOrEqual(run.misses[99], 300, "every switch creates its pictures again")
        XCTAssertLessThanOrEqual(run.live.max() ?? .max, 5, "nothing retained")
        print("PERF-004 baseline (no reuse): pool misses \(run.misses[99]) over 100 switches")
    }

    // MARK: - T09: no reuse before completion through the compositor (S3)

    func testARemovedLayersPicturesAreNotReusedWhileItsFrameIsPending() throws {
        let rig = try GPURig()
        let pool = TexturePool(device: rig.device)
        let compositor = try Compositor(device: rig.device, texturePool: pool)
        let output = try rig.output(width: 64, height: 48)
        var stack = LayerStack()
        try switchScene(&stack, colors: [Pixel(1, 0, 0, 1)], lastGood: [false])
        try apply(stack, compositor)
        try rig.frame(compositor, into: output, time: 1_000_000_000)

        let pending = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: output, commandBuffer: pending, presentationTimeNanoseconds: 1_016_666_667,
                                           contentScale: 2, reduceFlashing: false, audio: .empty))
        try switchScene(&stack, colors: [Pixel(0, 0, 1, 1)], lastGood: [false])
        let misses = pool.counters.misses
        try apply(stack, compositor)   // the red layer's picture waits for `pending`
        XCTAssertEqual(pool.counters.misses, misses + 1, "the blue layer got a new picture")
        XCTAssertEqual(pool.counters.waitingTextures, 1)

        pending.commit()
        pending.waitUntilCompleted()
        try rig.frame(compositor, into: output, time: 1_033_333_333)
        assertAll(try rig.read(output), equal: Pixel(0, 0, 1, 1), "only the new layer shows")
        try switchScene(&stack, colors: [Pixel(0, 1, 0, 1)], lastGood: [false])
        let hits = pool.counters.hits
        try apply(stack, compositor)
        XCTAssertEqual(pool.counters.hits, hits + 1, "after completion the retired picture is reused")
        try rig.frame(compositor, into: output, time: 1_050_000_000)
        assertAll(try rig.read(output), equal: Pixel(0, 1, 0, 1), "a reused picture shows only its new layer")
    }

    // MARK: - T10: caps, age and purge through the compositor (S4)

    func testCapAgeAndPurgeThroughTheCompositor() throws {
        let rig = try GPURig()
        let probe = try XCTUnwrap(rig.device.makeTexture(descriptor: pictureDescriptor()))
        let pool = TexturePool(device: rig.device, limits: TexturePoolLimits(maxRetiredBytes: probe.allocatedSize, maxIdleFrames: 5))
        let compositor = try Compositor(device: rig.device, texturePool: pool)
        var stack = LayerStack()
        try switchScene(&stack, colors: [Pixel(1, 0, 0, 1)], lastGood: [false])
        try apply(stack, compositor)
        try rig.frame(compositor, into: try rig.output(width: 64, height: 48), time: 1_000_000_000)
        XCTAssertEqual(pool.counters.checkedOutTextures, 2, "composite and one picture")

        let resized = try rig.output(width: 48, height: 64)
        try rig.frame(compositor, into: resized, time: 1_016_666_667)
        XCTAssertEqual(pool.counters.retiredTextures, 1, "the cap holds one picture of the old size")
        XCTAssertEqual(pool.counters.evictions, 1)
        for f in 0..<6 { try rig.frame(compositor, into: resized, time: 1_033_333_333 + UInt64(f) * 16_666_667) }
        XCTAssertEqual(pool.counters.retiredTextures, 0, "the old size aged out")
        XCTAssertEqual(pool.counters.evictions, 2)

        try switchScene(&stack, colors: [Pixel(0, 0, 1, 1)], lastGood: [false])
        try apply(stack, compositor)
        pool.purge()
        XCTAssertEqual(pool.counters.retiredTextures, 0)
        try rig.frame(compositor, into: resized, time: 2_000_000_000)
        assertAll(try rig.read(resized), equal: Pixel(0, 0, 1, 1), "the visual keeps rendering after a purge")
    }
}
#endif
