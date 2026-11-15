// FX-010-T07: Echo through the real Metal compositor (FX-010-S1 to S4). The roadmap acceptance "Echo count is capped
// and memory use remains bounded": a request for 8 echoes draws exactly 4 (and the shader's loop bound is the cap); a
// 600-frame run with setting changes, resizes and an off/on keeps exactly 4 history pictures whose identities change
// only with the history size, whose total `allocatedSize` stays under the bound, and nothing is allocated on steady
// frames. Also: a moving dot leaves N copies at the expected delays matching the CPU reference; off and 0 echoes are
// bit-identical; a reset shows no echo of old content. Tiny frames and injected frame times (no clock); skipped
// without Metal. Reuses `PixelsLayer` (ChromaticSplitCompositeTests.swift) and `SolidLayer` (TestLayers.swift).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import simd
import XCTest

/// A 2 × 2 white dot on black that moves `step` pixels right every frame (the frame clock's index).
final class MovingDotLayer: LayerSource {
    let layerName = "dot"
    let fallback = LayerFallback.transparent
    let width: Int
    let height: Int
    let step: Int

    init(width: Int, height: Int, step: Int) {
        self.width = width
        self.height = height
        self.step = step
    }

    static func pixels(frame: Int, width: Int, height: Int, step: Int) -> [Pixel] {
        var pixels = [Pixel](repeating: Pixel(0, 0, 0, 1), count: width * height)
        let x0: Int = 2 + step * frame
        for y in 6...7 {
            for x in x0...(x0 + 1) where x < width { pixels[y * width + x] = Pixel(1, 1, 1, 1) }
        }
        return pixels
    }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        let pixels: [Pixel] = Self.pixels(frame: Int(frame.frameIndex), width: width, height: height, step: step)
        try PixelsLayer(width: width, height: height, pixels: pixels).render(into: picture, commandBuffer: commandBuffer,
                                                                             frame: frame, audio: audio)
    }
}

final class EchoCompositeTests: XCTestCase {
    private static let start: UInt64 = 1_000_000_000
    /// 62.5 ms frames: exact in binary, so the schedule is exact.
    private static func time(_ k: Int) -> UInt64 { start + UInt64(k) * 62_500_000 }

    private static func random(width: Int, height: Int, seed: UInt64) -> [Pixel] {
        var state: UInt64 = seed
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        return (0..<(width * height)).map { (_: Int) -> Pixel in
            let a: Int = 256 + next(769)
            return Pixel(Float(next(a + 1)) / 1024, Float(next(a + 1)) / 1024, Float(next(a + 1)) / 1024, Float(a) / 1024)
        }
    }

    /// Frame `k`'s stack phase plus output effects (`encodeScene`), read back as raw halves.
    private func sceneHalves(_ rig: GPURig, _ c: Compositor, _ k: Int, width: Int, height: Int) throws -> [UInt16] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let shown = try XCTUnwrap(c.encodeScene(width: width, height: height, commandBuffer: commands,
                                                presentationTimeNanoseconds: Self.time(k), contentScale: 2, reduceFlashing: false,
                                                audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        let rowBytes: Int = width * 8
        let buffer = try XCTUnwrap(rig.device.makeBuffer(length: rowBytes * height, options: .storageModeShared))
        let copy = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let blit = try XCTUnwrap(copy.makeBlitCommandEncoder())
        blit.copy(from: shown, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        copy.commit()
        copy.waitUntilCompleted()
        let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: width * height * 4)
        return Array(UnsafeBufferPointer(start: halves, count: width * height * 4))
    }

    private func scene(_ rig: GPURig, _ c: Compositor, _ k: Int, width: Int, height: Int) throws -> [Pixel] {
        let h: [UInt16] = try sceneHalves(rig, c, k, width: width, height: height)
        return stride(from: 0, to: h.count, by: 4).map { (i: Int) -> Pixel in
            Pixel(Half.toFloat(h[i]), Half.toFloat(h[i + 1]), Half.toFloat(h[i + 2]), Half.toFloat(h[i + 3]))
        }
    }

    /// One frame of `encodeScene` committed without reading back.
    private func frame(_ rig: GPURig, _ c: Compositor, _ k: Int, width: Int, height: Int) throws {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertNotNil(c.encodeScene(width: width, height: height, commandBuffer: commands, presentationTimeNanoseconds: Self.time(k),
                                      contentScale: 2, reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
    }

    // MARK: - Off is exact (FX-010-S4)

    func testOffAndZeroEchoesAreBitIdenticalOnRandomContent() throws {
        let rig = try GPURig()
        let w = 37, h = 29
        let pixels: [Pixel] = Self.random(width: w, height: h, seed: 7)
        let variants: [EchoFeedback] = [.off, EchoFeedback(isEnabled: true, count: 0),
                                        EchoFeedback(isEnabled: true, count: 4, weightCap: 0), EchoFeedback(isEnabled: false, count: 4)]
        let reference = try Compositor(device: rig.device, layers: [PixelsLayer(width: w, height: h, pixels: pixels)])
        let compositors: [Compositor] = try variants.map { (e: EchoFeedback) -> Compositor in
            let c = try Compositor(device: rig.device, layers: [PixelsLayer(width: w, height: h, pixels: pixels)])
            c.echoFeedback = e
            return c
        }
        for k in 0..<3 {
            let expected: [UInt16] = try sceneHalves(rig, reference, k, width: w, height: h)
            for (i, c) in compositors.enumerated() {
                XCTAssertEqual(try sceneHalves(rig, c, k, width: w, height: h), expected, "variant \(i) frame \(k), bit for bit")
            }
        }
        let outRef = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(reference, into: outRef, time: Self.time(3)))
        let expectedOut: [Pixel] = try rig.read(outRef)
        for c in compositors {
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.time(3)))
            XCTAssertEqual(try rig.read(out), expectedOut, "the screen output")
            XCTAssertEqual(c.echoFrames + c.echoStores, 0, "no pass runs")
            XCTAssertFalse(c.holdsEchoPictures, "no picture is held")
        }
    }

    // MARK: - Capped count and echo maths (FX-010-S1, S3)

    func testMovingDotShowsExactlyFourCappedEchoesMatchingTheReference() throws {
        XCTAssertTrue(EchoPass.source.contains("constant uint cmp_echo_cap = \(EchoFeedback.cap);"))
        XCTAssertTrue(EchoPass.source.contains("uint n = min(e.count, cmp_echo_cap);"), "the loop bound is the cap")
        XCTAssertTrue(EchoPass.source.contains("for (uint k = 0; k < n; k++)"))
        XCTAssertTrue(CompositorShaderSources.archived.contains(EchoPass.source), "in the pipeline-archive key")
        let rig = try GPURig()
        let w = 64, h = 16, step = 6, last = 6
        let echo = EchoFeedback(isEnabled: true, count: 8, delaySeconds: 0.05, decay: 0.6)   // 8 requested, one store per frame
        let c = try Compositor(device: rig.device, layers: [MovingDotLayer(width: w, height: h, step: step)])
        c.echoFeedback = echo
        for k in 0..<last { try frame(rig, c, k, width: w, height: h) }
        let out: [Pixel] = try scene(rig, c, last, width: w, height: h)
        XCTAssertEqual(c.echoStores, last + 1, "one store per frame at this delay")
        // CPU reference: frames 5, 4, 3, 2 (most recent first), stored at the history size.
        let size = try XCTUnwrap(EchoFeedback.historySize(width: w, height: h))   // 32 × 16 (at least 16 rows)
        let hw: Int = size.width, hh: Int = size.height
        let history: [[Pixel]] = (1...4).map { (k: Int) -> [Pixel] in
            EchoFeedback.downsample(MovingDotLayer.pixels(frame: last - k, width: w, height: h, step: step), width: w, height: h,
                                    historyWidth: hw, historyHeight: hh)
        }
        let weights: [Float] = echo.weights(valid: 4)
        XCTAssertEqual(weights.count, 4, "exactly the cap")
        XCTAssertLessThanOrEqual(weights.reduce(Float(0), +), 1, "the weight sum never exceeds the cap")
        let current: [Pixel] = MovingDotLayer.pixels(frame: last, width: w, height: h, step: step)
        let expected: [Pixel] = EchoFeedback.reference(current, width: w, height: h, history: history, historyWidth: hw,
                                                       historyHeight: hh, weights: weights)
        var worst: Float = 0
        for (i, p) in out.enumerated() {
            let d: Pixel = simd_abs(p - expected[i])
            worst = max(worst, d.max())
            if d.max() > 2.0 / 1024 && ProcessInfo.processInfo.environment["ECHO_DEBUG"] != nil {
                print("ECHO diff at \(i % w),\(i / w): gpu \(p) cpu \(expected[i])")
            }
        }
        XCTAssertLessThanOrEqual(worst, 2.0 / 1024, "GPU vs CPU reference")
        // The copies: echo k sits where the dot was k frames ago, each weaker by the fade; nothing at the 5th.
        func peak(_ frame: Int) -> Float {
            let x0: Int = 2 + step * frame
            return (5...8).flatMap { (y: Int) -> [Float] in (x0 - 1...x0 + 2).map { (x: Int) -> Float in out[y * w + x].x } }.max() ?? 0
        }
        XCTAssertEqual(peak(last), 1, "the live dot")
        var previous: Float = 1
        for k in 1...4 {
            let p: Float = peak(last - k)
            XCTAssertGreaterThan(p, 0.01, "echo \(k) is there")
            if k > 1 { XCTAssertEqual(p / previous, 0.6, accuracy: 0.02, "echo \(k) is weaker by the fade") }
            previous = p
        }
        XCTAssertEqual(peak(last - 5), 0, "never a fifth copy")
    }

    func testNeverBrighterThanTheFramesItIsMadeOf() throws {
        let rig = try GPURig()
        let layer = SolidLayer("white", color: Pixel(1, 1, 1, 1))
        let c = try Compositor(device: rig.device, layers: [layer])
        c.echoFeedback = EchoFeedback(isEnabled: true, count: 4, delaySeconds: 0.05, decay: 0.9)   // raw sum 3.1, scaled to 1
        for k in 0..<6 {
            layer.color = k % 2 == 0 ? Pixel(1, 1, 1, 1) : Pixel(0.25, 0.25, 0.25, 1)
            let out: [Pixel] = try scene(rig, c, k, width: 32, height: 24)
            for p in out { XCTAssertLessThanOrEqual(p.max(), 1, "frame \(k)") }
        }
    }

    // MARK: - Bounded memory over a long run (roadmap acceptance, FX-010-S2)

    func testMemoryStaysBoundedOverSixHundredFramesWithChangesAndResizes() throws {
        let rig = try GPURig()
        let layer = SolidLayer("scene", color: Pixel(0.5, 0.2, 0.1, 1))
        let c = try Compositor(device: rig.device, layers: [layer])
        c.echoFeedback = EchoFeedback(isEnabled: true)
        func size(_ k: Int) -> (Int, Int) {
            switch k {
            case 0..<200: return (32, 32)
            case 200..<300: return (34, 30)   // same history size class (16 × 16)
            case 300..<450: return (64, 48)   // a new class (32 × 24)
            default: return (32, 32)
            }
        }
        var previousIDs: [ObjectIdentifier] = []
        var previousHistorySize: (Int, Int)?
        var allocationFrames: [Int] = []
        var lastAllocations: Int = c.echoAllocations
        var maxBytes = 0
        for k in 0..<600 {
            var turnedOn = false
            if k % 50 == 25 {   // count 1…8 (capped), delay and fade changes keep the history
                let n: Int = (k / 50) % 8 + 1
                c.echoFeedback = EchoFeedback(isEnabled: true, count: n, delaySeconds: 0.05 + Double(k % 7) * 0.02,
                                              decay: 0.2 + Double(k % 5) * 0.15)
            }
            if k == 500 { c.echoFeedback.isEnabled = false }
            if k == 510 {
                c.echoFeedback.isEnabled = true
                turnedOn = true
            }
            layer.color = Pixel(Float(k % 10) / 10, 0.2, 0.1, 1)
            let (w, h) = size(k)
            try frame(rig, c, k, width: w, height: h)
            let history: [MTLTexture] = c.echoHistoryTextures
            guard c.echoFeedback.isActive else {
                XCTAssertTrue(history.isEmpty, "frame \(k): off holds no history")
                XCTAssertFalse(c.holdsEchoPictures)
                previousIDs = []
                continue
            }
            XCTAssertEqual(history.count, EchoFeedback.cap, "frame \(k): exactly the cap")
            let hs = try XCTUnwrap(EchoFeedback.historySize(width: w, height: h))
            for t in history { XCTAssertTrue(t.width == hs.width && t.height == hs.height, "frame \(k)") }
            let ids: [ObjectIdentifier] = history.map { (t: MTLTexture) -> ObjectIdentifier in ObjectIdentifier(t) }
            let classChanged: Bool = previousHistorySize.map { (p: (Int, Int)) -> Bool in p != (hs.width, hs.height) } ?? true
            if !previousIDs.isEmpty && !classChanged && !turnedOn {
                XCTAssertEqual(ids, previousIDs, "frame \(k): the same pictures")
            }
            previousIDs = ids
            previousHistorySize = (hs.width, hs.height)
            let descriptor = try XCTUnwrap(LayerPictureDescriptor(width: hs.width, height: hs.height)).textureDescriptor()
            let bound: Int = EchoFeedback.cap * rig.device.heapTextureSizeAndAlign(descriptor: descriptor).size
            XCTAssertLessThanOrEqual(c.echoHistoryBytes, bound, "frame \(k): total allocatedSize under the bound")
            XCTAssertLessThanOrEqual(EchoFeedback.historyBytes(width: w, height: h), EchoFeedback.historyBytesBound)
            maxBytes = max(maxBytes, c.echoHistoryBytes)
            if c.echoAllocations != lastAllocations {
                allocationFrames.append(k)
                lastAllocations = c.echoAllocations
            }
        }
        // Allocations only when turning on (0, 510) and when a size changed (200: output picture only; 300, 450).
        XCTAssertEqual(allocationFrames, [0, 200, 300, 450, 510], "nothing allocated on steady frames")
        XCTAssertGreaterThan(maxBytes, 0)
        c.echoFeedback = .off
        XCTAssertFalse(c.holdsEchoPictures, "turning it off returns every picture")
    }

    // MARK: - Reset (FX-010-R11)

    func testResetShowsNoEchoOfOldContent() throws {
        let rig = try GPURig()
        let layer = SolidLayer("scene", color: Pixel(1, 0, 0, 1))
        let c = try Compositor(device: rig.device, layers: [layer])
        c.echoFeedback = EchoFeedback(isEnabled: true, count: 4, delaySeconds: 0.05)
        for k in 0..<5 { try frame(rig, c, k, width: 32, height: 24) }
        XCTAssertGreaterThan(c.echoFrames, 0)
        layer.color = Pixel(0, 0, 0.5, 1)
        c.resetFeedback()   // a scene change
        let blue: [UInt16] = try sceneHalves(rig, c, 5, width: 32, height: 24)
        let alone = try Compositor(device: rig.device, layers: [SolidLayer("alone", color: Pixel(0, 0, 0.5, 1))])
        XCTAssertEqual(blue, try sceneHalves(rig, alone, 0, width: 32, height: 24), "no red echo after the reset, bit for bit")
        XCTAssertEqual(c.echoValidStores, 1, "the history restarted with the new scene")
    }
}
#endif
