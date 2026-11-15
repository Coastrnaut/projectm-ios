// FX-011-T07: the pixel sort through the real Metal compositor (FX-011-S1 to S4) — the shader unit test. The roadmap
// acceptance "threshold changes ordering; worst-case frame budget is enforced": at thresholds 0.5 and 0.2, both
// directions, with a partial last tile, the GPU output equals the CPU reference bit for bit, the two outputs differ,
// every segment is non-decreasing and every other pixel is untouched; off is bit-identical with no dispatch; an active
// frame encodes exactly one dispatch with a workload within the budget; a lowered budget shortens the span or skips the
// pass (zero dispatches, identical output); random HDR content stays finite and each tile is a permutation. Small frames,
// one frame each. Skipped without Metal. `PixelsLayer` comes from `ChromaticSplitCompositeTests`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import XCTest

final class PixelSortCompositeTests: XCTestCase {
    private static let sortTime: UInt64 = 1_000_000_000

    private func sortCompositor(_ rig: GPURig, _ pixels: [Pixel], width: Int, height: Int,
                                sort: PixelSort) throws -> Compositor {
        let c = try Compositor(device: rig.device, layers: [PixelsLayer(width: width, height: height, pixels: pixels)])
        c.pixelSort = sort
        return c
    }

    private func sortHalves(_ rig: GPURig, _ texture: MTLTexture, width: Int, height: Int) throws -> [Pixel] {
        let rowBytes: Int = width * 8
        let buffer = try XCTUnwrap(rig.device.makeBuffer(length: rowBytes * height, options: .storageModeShared))
        let copy = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let blit = try XCTUnwrap(copy.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        copy.commit()
        copy.waitUntilCompleted()
        let halves = buffer.contents().bindMemory(to: Float16.self, capacity: width * height * 4)
        let flat = Array(UnsafeBufferPointer(start: halves, count: width * height * 4))
        return stride(from: 0, to: flat.count, by: 4).map { (i: Int) -> Pixel in
            Pixel(Float(flat[i]), Float(flat[i + 1]), Float(flat[i + 2]), Float(flat[i + 3]))
        }
    }

    /// The stack phase plus output effects (`encodeScene`).
    private func sortScene(_ rig: GPURig, _ c: Compositor, width: Int, height: Int) throws -> [Pixel] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let shown = try XCTUnwrap(c.encodeScene(width: width, height: height, commandBuffer: commands,
                                                presentationTimeNanoseconds: Self.sortTime, contentScale: 2,
                                                reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        return try sortHalves(rig, shown, width: width, height: height)
    }

    /// Seeded random premultiplied content (colour ≤ alpha) with a few HDR pixels, half-exact.
    private static func sortRandom(width: Int, height: Int, seed: UInt64) -> [Pixel] {
        var state: UInt64 = seed
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        return (0..<(width * height)).map { (i: Int) -> Pixel in
            if i % 17 == 0 { return Pixel(Float(next(2000) * 2), 3, 0.5, 1) }
            let a: Int = 256 + next(769)
            return Pixel(Float(next(a + 1)) / 1024, Float(next(a + 1)) / 1024, Float(next(a + 1)) / 1024, Float(a) / 1024)
        }
    }

    // MARK: - Threshold changes ordering (FX-011-S1)

    func testThresholdChangesOrderingAndTheGPUEqualsTheReference() throws {
        let rig = try GPURig()
        let w = 37, h = 21   // 37 = 4 × 8 + 5 and 21 = 2 × 8 + 5: a partial last tile both ways
        let input: [Pixel] = PixelSortModelTests.grayPicture(width: w, height: h, seed: 11)
        for direction in PixelSort.Direction.allCases {
            var outputs: [[Pixel]] = []
            for threshold in [0.5, 0.2] {
                let sort = PixelSort(isEnabled: true, threshold: threshold, span: 8, direction: direction)
                let c = try sortCompositor(rig, input, width: w, height: h, sort: sort)
                let out: [Pixel] = try sortScene(rig, c, width: w, height: h)
                XCTAssertEqual(c.pixelSortDispatches, 1, "one dispatch")
                XCTAssertEqual(c.pixelSortEffectiveSpan, 8)
                XCTAssertEqual(out, sort.reference(input, width: w, height: h), "\(direction) \(threshold): GPU = reference")
                PixelSortModelTests.assertSorted(input: input, output: out, width: w, height: h, span: 8,
                                                 threshold: Float(threshold), direction: direction)
                outputs.append(out)
            }
            XCTAssertNotEqual(outputs[0], outputs[1], "\(direction): the threshold changes the ordering")
            XCTAssertNotEqual(outputs[0], input, "\(direction): pixels moved")
        }
    }

    func testRandomContentStaysFiniteAndEachTileIsAPermutation() throws {
        let rig = try GPURig()
        let w = 70, h = 9
        let input: [Pixel] = Self.sortRandom(width: w, height: h, seed: 3)
        for span in [4, 64] {
            let sort = PixelSort(isEnabled: true, threshold: 0.3, span: span)
            let c = try sortCompositor(rig, input, width: w, height: h, sort: sort)
            let out: [Pixel] = try sortScene(rig, c, width: w, height: h)
            for p in out { for ch in 0..<4 { XCTAssertTrue(p[ch].isFinite) } }
            PixelSortModelTests.assertSorted(input: input, output: out, width: w, height: h, span: span, threshold: 0.3,
                                             direction: .horizontal)
        }
    }

    // MARK: - Off is the identity (FX-011-S3)

    func testOffIsBitIdenticalWithNoDispatch() throws {
        let rig = try GPURig()
        let w = 33, h = 17
        let input: [Pixel] = Self.sortRandom(width: w, height: h, seed: 8)
        let none = try sortCompositor(rig, input, width: w, height: h, sort: .off)
        let reference: [Pixel] = try sortScene(rig, none, width: w, height: h)
        let outNone = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(none, into: outNone, time: Self.sortTime + 16_666_667))
        let screen: [Pixel] = try rig.read(outNone)
        do {
            let c = try sortCompositor(rig, input, width: w, height: h, sort: PixelSort(isEnabled: false, threshold: 0, span: 64))
            XCTAssertEqual(try sortScene(rig, c, width: w, height: h), reference)
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.sortTime + 16_666_667))
            XCTAssertEqual(try rig.read(out), screen)
            XCTAssertEqual(c.pixelSortDispatches, 0)
            XCTAssertFalse(c.holdsPixelSortPicture)
        }
        let row: [Pixel] = Array(input[0..<w])
        let flat = try sortCompositor(rig, row, width: w, height: 1, sort: PixelSort(isEnabled: true, direction: .vertical))
        let flatOff = try sortCompositor(rig, row, width: w, height: 1, sort: .off)
        XCTAssertEqual(try sortScene(rig, flat, width: w, height: 1), try sortScene(rig, flatOff, width: w, height: 1),
                       "a frame 1 pixel high is too small for a vertical sort")
        XCTAssertEqual(flat.pixelSortDispatches, 0)
    }

    // MARK: - Worst-case frame budget (FX-011-S2)

    func testEveryActiveFrameEncodesOneDispatchWithinTheBudget() throws {
        let rig = try GPURig()
        let w = 40, h = 24
        let input: [Pixel] = PixelSortModelTests.grayPicture(width: w, height: h, seed: 5)
        let c = try sortCompositor(rig, input, width: w, height: h, sort: PixelSort(isEnabled: true, threshold: 0.4, span: 64))
        let out = try rig.output(.rgba16Float, width: w, height: h)
        for k in 0..<3 {
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.sortTime + UInt64(k) * 16_666_667))
            XCTAssertEqual(c.pixelSortDispatches, k + 1, "exactly one dispatch per frame")
            XCTAssertEqual(c.pixelSortEffectiveSpan, 64)
            XCTAssertEqual(c.pixelSortWorkload, w * h * 64)
            XCTAssertLessThanOrEqual(c.pixelSortWorkload, PixelSort.frameBudget)
        }
        XCTAssertTrue(c.holdsPixelSortPicture)
        XCTAssertEqual(c.pixelSortBudgetSkips, 0)
    }

    func testALoweredBudgetShortensTheSpanOrSkipsThePass() throws {
        let rig = try GPURig()
        let w = 40, h = 24
        let input: [Pixel] = PixelSortModelTests.grayPicture(width: w, height: h, seed: 6)
        let sort = PixelSort(isEnabled: true, threshold: 0.3, span: 64)
        let shorter = try sortCompositor(rig, input, width: w, height: h, sort: sort)
        shorter.pixelSortBudget = w * h * 8 + 7
        let out8: [Pixel] = try sortScene(rig, shorter, width: w, height: h)
        XCTAssertEqual(shorter.pixelSortEffectiveSpan, 8, "the largest span within the budget")
        XCTAssertLessThanOrEqual(shorter.pixelSortWorkload, shorter.pixelSortBudget)
        XCTAssertEqual(out8, sort.referenceAlways(input, width: w, height: h, span: 8))

        let skipped = try sortCompositor(rig, input, width: w, height: h, sort: sort)
        skipped.pixelSortBudget = w * h * 4 - 1
        let none = try sortCompositor(rig, input, width: w, height: h, sort: .off)
        XCTAssertEqual(try sortScene(rig, skipped, width: w, height: h), try sortScene(rig, none, width: w, height: h),
                       "skipped: the frame passes through")
        XCTAssertEqual(skipped.pixelSortDispatches, 0, "no dispatch when span 4 does not fit")
        XCTAssertEqual(skipped.pixelSortBudgetSkips, 1)
        XCTAssertFalse(skipped.holdsPixelSortPicture)
    }

    // MARK: - Order, pool and archive (FX-011-R8, R12, R14)

    func testOrderFoldsColorBeforeItAndThePictureIsReturned() throws {
        let rig = try GPURig()
        let w = 32, h = 24
        let input: [Pixel] = Self.sortRandom(width: w, height: h, seed: 4)
        func render(_ order: OutputEffectOrder) throws -> Compositor {
            let c = try sortCompositor(rig, input, width: w, height: h, sort: PixelSort(isEnabled: true, threshold: 0.2))
            c.colorGrade = ColorGrade(saturation: 0.2)
            c.outputEffectOrder = order
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.sortTime))
            return c
        }
        let standard = try render(.standard)
        XCTAssertEqual(standard.gradePassFrames, 1, "Color listed before the sort is applied before it")
        XCTAssertEqual(standard.pixelSortDispatches, 1)
        let late = try render(OutputEffectOrder([.pixelSort, .trails, .chromatic, .grade]))
        XCTAssertEqual(late.gradePassFrames, 0, "Color after the sort stays in the output pass")
        XCTAssertTrue(late.holdsPixelSortPicture)
        late.pixelSort = .off
        XCTAssertFalse(late.holdsPixelSortPicture, "off returns the picture")
        XCTAssertTrue(CompositorShaderSources.archived.contains(PixelSortPass.source), "in the pipeline-archive key")
        let order: [OutputEffectKind] = OutputEffectOrder.standard.effects
        XCTAssertEqual(order.firstIndex(of: .pixelSort), (order.firstIndex(of: .lensDistortion) ?? 0) + 1)
        XCTAssertEqual(order.firstIndex(of: .vignette), (order.firstIndex(of: .pixelSort) ?? 0) + 1, "Vignette directly follows Pixel sort")
        XCTAssertEqual(order.firstIndex(of: .scanlines), (order.firstIndex(of: .vignette) ?? 0) + 1, "then FX-018 Scanlines")
        XCTAssertEqual(order.last, .filmGrain, "FX-017 Film grain is last")
    }
}
#endif
