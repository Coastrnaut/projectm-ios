// FX-012-T07: the mosaic through the real Metal compositor (FX-012-S1 to S4). The roadmap acceptance "Block size one
// equals original frame; larger sizes are visibly discrete": off and size 1 (both shapes) are bit-identical on random
// content with no pass; at size 8 every 8 × 8 square block from the top-left is one colour, its centre pixel's, and
// adjacent blocks differ; hexagonal cells are uniform at pixels away from cell borders; the GPU equals the CPU
// reference. Small frames, one frame each. Skipped without Metal. `PixelsLayer` comes from
// `ChromaticSplitCompositeTests`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import XCTest

final class MosaicCompositeTests: XCTestCase {
    private static let mosaicTime: UInt64 = 1_000_000_000

    private static func mosaicQ(_ k: Int) -> Float { Float(k) / 1024 }

    /// Seeded random premultiplied content (colour ≤ alpha), half-exact.
    private static func mosaicRandom(width: Int, height: Int, seed: UInt64) -> [Pixel] {
        var state: UInt64 = seed
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        return (0..<(width * height)).map { (_: Int) -> Pixel in
            let a: Int = 256 + next(769)
            return Pixel(mosaicQ(next(a + 1)), mosaicQ(next(a + 1)), mosaicQ(next(a + 1)), mosaicQ(a))
        }
    }

    private func mosaicCompositor(_ rig: GPURig, _ pixels: [Pixel], width: Int, height: Int, mosaic: Mosaic) throws -> Compositor {
        let c = try Compositor(device: rig.device, layers: [PixelsLayer(width: width, height: height, pixels: pixels)])
        c.mosaic = mosaic
        return c
    }

    /// The stack phase plus output effects (`encodeScene`), one 4-half quad per pixel.
    private func mosaicScene(_ rig: GPURig, _ c: Compositor, width: Int, height: Int) throws -> [[UInt16]] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let shown = try XCTUnwrap(c.encodeScene(width: width, height: height, commandBuffer: commands,
                                                presentationTimeNanoseconds: Self.mosaicTime, contentScale: 2,
                                                reduceFlashing: false, audio: .empty))
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
        let flat = Array(UnsafeBufferPointer(start: halves, count: width * height * 4))
        return stride(from: 0, to: flat.count, by: 4).map { (i: Int) -> [UInt16] in Array(flat[i..<(i + 4)]) }
    }

    private static func mosaicHalves(_ pixels: [Pixel]) -> [[UInt16]] {
        pixels.map { (p: Pixel) -> [UInt16] in
            [Float16(p.x).bitPattern, Float16(p.y).bitPattern, Float16(p.z).bitPattern, Float16(p.w).bitPattern]
        }
    }

    // MARK: - Block size one equals the original frame (FX-012-S1)

    func testMosaicOffAndSizeOneAreBitIdenticalOnRandomContent() throws {
        let rig = try GPURig()
        let w = 37, h = 29
        let pixels: [Pixel] = Self.mosaicRandom(width: w, height: h, seed: 12)
        let off = try mosaicCompositor(rig, pixels, width: w, height: h, mosaic: .off)
        let reference: [[UInt16]] = try mosaicScene(rig, off, width: w, height: h)
        XCTAssertEqual(reference, Self.mosaicHalves(pixels), "the stack result is the input picture itself")
        let outOff = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(off, into: outOff, time: Self.mosaicTime + 16_666_667))
        let screen: [Pixel] = try rig.read(outOff)
        for shape in MosaicShape.allCases {
            let one = try mosaicCompositor(rig, pixels, width: w, height: h, mosaic: Mosaic(isEnabled: true, blockSize: 1, shape: shape))
            XCTAssertEqual(try mosaicScene(rig, one, width: w, height: h), reference, "\(shape) size 1: bit for bit")
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(one, into: out, time: Self.mosaicTime + 16_666_667))
            XCTAssertEqual(try rig.read(out), screen, "\(shape) size 1: the screen output")
            XCTAssertEqual(one.mosaicFrames, 0, "no pass runs")
            XCTAssertFalse(one.holdsMosaicPicture, "no picture is held")
        }
    }

    // MARK: - Larger sizes are visibly discrete (FX-012-S2, S4)

    func testMosaicSquaresAreUniformBlocksOfTheirCentrePixelAndDiffer() throws {
        let rig = try GPURig()
        let w = 44, h = 27   // five full columns and three full rows of 8 × 8 blocks, plus partial edges
        let pixels: [Pixel] = Self.mosaicRandom(width: w, height: h, seed: 8)
        let mosaic = Mosaic(isEnabled: true, blockSize: 8)
        let c = try mosaicCompositor(rig, pixels, width: w, height: h, mosaic: mosaic)
        let out: [[UInt16]] = try mosaicScene(rig, c, width: w, height: h)
        XCTAssertEqual(c.mosaicFrames, 1, "the pass ran")
        let input: [[UInt16]] = Self.mosaicHalves(pixels)
        var colours: [SIMD2<Int>: [UInt16]] = [:]
        for by in 0..<(h / 8) {
            for bx in 0..<(w / 8) {
                let centre: [UInt16] = input[(by * 8 + 4) * w + bx * 8 + 4]
                for y in (by * 8)..<(by * 8 + 8) {
                    for x in (bx * 8)..<(bx * 8 + 8) {
                        XCTAssertEqual(out[y * w + x], centre, "block (\(bx), \(by)) pixel (\(x), \(y)): one colour, its centre's")
                    }
                }
                colours[SIMD2(bx, by)] = centre
            }
        }
        for (cell, colour) in colours {
            for step in [SIMD2(1, 0), SIMD2(0, 1)] {
                if let next = colours[cell &+ step] { XCTAssertNotEqual(colour, next, "adjacent blocks \(cell) and \(cell &+ step) differ") }
            }
        }
        XCTAssertEqual(out, mosaic.reference(input, width: w, height: h), "GPU = reference, every pixel including partial blocks")
    }

    func testMosaicHexagonCellsAreUniformAwayFromBorders() throws {
        let rig = try GPURig()
        let w = 61, h = 47, size = 12
        let pixels: [Pixel] = Self.mosaicRandom(width: w, height: h, seed: 6)
        let mosaic = Mosaic(isEnabled: true, blockSize: size, shape: .hexagon)
        let c = try mosaicCompositor(rig, pixels, width: w, height: h, mosaic: mosaic)
        let out: [[UInt16]] = try mosaicScene(rig, c, width: w, height: h)
        let expected: [[UInt16]] = mosaic.reference(Self.mosaicHalves(pixels), width: w, height: h)
        var cellColours: [SIMD2<Int>: Set<[UInt16]>] = [:]
        var interior = 0
        var mismatches = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let cell: SIMD2<Int> = Mosaic.hexCell(x: x, y: y, size: size)
                let neighbours: [SIMD2<Int>] = [SIMD2(x - 1, y), SIMD2(x + 1, y), SIMD2(x, y - 1), SIMD2(x, y + 1)]
                let inside: Bool = neighbours.allSatisfy { (p: SIMD2<Int>) -> Bool in Mosaic.hexCell(x: p.x, y: p.y, size: size) == cell }
                if out[y * w + x] != expected[y * w + x] { mismatches += 1 }
                guard inside else { continue }
                interior += 1
                XCTAssertEqual(out[y * w + x], expected[y * w + x], "(\(x), \(y)) in cell \(cell): the reference colour")
                cellColours[cell, default: []].insert(out[y * w + x])
            }
        }
        XCTAssertGreaterThan(interior, (w - 2) * (h - 2) * 6 / 10, "most pixels are away from cell borders")
        XCTAssertGreaterThan(cellColours.count, 15, "many cells")
        for (cell, colours) in cellColours { XCTAssertEqual(colours.count, 1, "cell \(cell) is one uniform colour") }
        XCTAssertLessThan(mismatches, w * h / 50, "border ties only: \(mismatches) pixels differ from the reference")
    }

    // MARK: - Order and pool (FX-012-R7, R11)

    func testMosaicOrderFoldsColorBeforeItAndThePictureIsReturned() throws {
        let rig = try GPURig()
        let w = 32, h = 24
        let pixels: [Pixel] = Self.mosaicRandom(width: w, height: h, seed: 4)
        func render(_ order: OutputEffectOrder) throws -> Compositor {
            let c = try mosaicCompositor(rig, pixels, width: w, height: h, mosaic: Mosaic(isEnabled: true, blockSize: 4))
            c.colorGrade = ColorGrade(saturation: 0.2)
            c.outputEffectOrder = order
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.mosaicTime))
            return c
        }
        let standard = try render(.standard)
        XCTAssertEqual(standard.gradePassFrames, 1, "Color listed before the mosaic is applied before it")
        XCTAssertEqual(standard.mosaicFrames, 1)
        let late = try render(OutputEffectOrder([.mosaic, .trails, .chromatic, .grade]))
        XCTAssertEqual(late.gradePassFrames, 0, "Color after the mosaic stays in the output pass")
        XCTAssertTrue(late.holdsMosaicPicture)
        late.mosaic = .off
        XCTAssertFalse(late.holdsMosaicPicture, "turning it off returns the picture")
    }
}
#endif
