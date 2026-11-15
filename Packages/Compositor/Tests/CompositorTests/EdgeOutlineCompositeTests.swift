// FX-014-T07: the edge outline through the real Metal compositor (FX-014-S1 to S4). The roadmap acceptance "Flat image
// produces no outlines and checkerboard produces boundaries": flat pictures (several colours) are bit-identical in
// overlay mode and black in outline-only mode, the border included; on an 8-pixel checkerboard the outlined pixels are
// exactly the CPU reference's mask (both sides of every boundary, within the width) and none lie inside the squares;
// a threshold above the checkerboard's contrast outlines nothing; off is bit-identical with no pass. Small frames, one
// frame each. Skipped without Metal. `PixelsLayer` comes from `ChromaticSplitCompositeTests`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import XCTest

final class EdgeOutlineCompositeTests: XCTestCase {
    private static let outlineTime: UInt64 = 1_000_000_000
    private static let red = EdgeOutlineColor(red: 1, green: 0, blue: 0)

    private func outlineCompositor(_ rig: GPURig, _ pixels: [Pixel], width: Int, height: Int,
                                   outline: EdgeOutline) throws -> Compositor {
        let c = try Compositor(device: rig.device, layers: [PixelsLayer(width: width, height: height, pixels: pixels)])
        c.edgeOutline = outline
        return c
    }

    /// The stack phase plus output effects (`encodeScene`), one 4-half quad per pixel.
    private func outlineScene(_ rig: GPURig, _ c: Compositor, width: Int, height: Int) throws -> [[UInt16]] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let shown = try XCTUnwrap(c.encodeScene(width: width, height: height, commandBuffer: commands,
                                                presentationTimeNanoseconds: Self.outlineTime, contentScale: 2,
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

    private static func outlineHalves(_ pixels: [Pixel]) -> [[UInt16]] {
        pixels.map { (p: Pixel) -> [UInt16] in
            [Float16(p.x).bitPattern, Float16(p.y).bitPattern, Float16(p.z).bitPattern, Float16(p.w).bitPattern]
        }
    }

    /// Squares of `size` pixels alternating `a` and `b`, from the top-left corner.
    private static func checkerboard(width: Int, height: Int, size: Int, _ a: Pixel, _ b: Pixel) -> [Pixel] {
        (0..<(width * height)).map { (i: Int) -> Pixel in
            let x: Int = i % width
            let y: Int = i / width
            return (x / size + y / size) % 2 == 0 ? a : b
        }
    }

    /// Whether a square boundary lies within `width` pixels of `v` along one axis.
    private static func nearBoundary(_ v: Int, extent: Int, size: Int, width: Int) -> Bool {
        stride(from: size, to: extent, by: size).contains { (b: Int) -> Bool in v >= b - width && v <= b - 1 + width }
    }

    // MARK: - Flat pictures: no outline (FX-014-S1)

    func testEdgeOutlineFlatPicturesAreUnchangedInOverlayAndBlackInOutlineOnly() throws {
        let rig = try GPURig()
        let w = 23, h = 17
        let colours: [Pixel] = [Pixel(0, 0, 0, 1), Pixel(1, 1, 1, 1), Pixel(0.25, 0.5, 0.125, 1), Pixel(0.375, 0.0625, 0.75, 1),
                                Pixel(0.25, 0.125, 0.5, 0.5)]
        let black: [UInt16] = Self.outlineHalves([Pixel(0, 0, 0, 1)])[0]
        for colour in colours {
            let pixels = [Pixel](repeating: colour, count: w * h)
            let input: [[UInt16]] = Self.outlineHalves(pixels)
            let overlay = try outlineCompositor(rig, pixels, width: w, height: h,
                                                outline: EdgeOutline(isEnabled: true, threshold: 0.02, width: 3, color: Self.red))
            XCTAssertEqual(try outlineScene(rig, overlay, width: w, height: h), input, "\(colour): overlay is the input, bit for bit")
            XCTAssertEqual(overlay.edgeOutlineFrames, 1, "the pass ran")
            let only = try outlineCompositor(rig, pixels, width: w, height: h,
                                             outline: EdgeOutline(isEnabled: true, threshold: 0.02, color: Self.red, mode: .outlineOnly))
            let shown: [[UInt16]] = try outlineScene(rig, only, width: w, height: h)
            XCTAssertEqual(shown, [[UInt16]](repeating: black, count: w * h), "\(colour): outline only is black everywhere")
        }
    }

    // MARK: - Checkerboard: boundaries only (FX-014-S2, S3)

    func testEdgeOutlineCheckerboardOutlinesExactlyTheBoundaries() throws {
        let rig = try GPURig()
        let w = 36, h = 28, size = 8   // full squares plus partial ones at the right and bottom edges
        let pixels: [Pixel] = Self.checkerboard(width: w, height: h, size: size, Pixel(0, 0, 0, 1), Pixel(1, 1, 1, 1))
        let input: [[UInt16]] = Self.outlineHalves(pixels)
        let redHalves: [UInt16] = Self.outlineHalves([Pixel(1, 0, 0, 1)])[0]
        for width in [1, 3] {
            let outline = EdgeOutline(isEnabled: true, threshold: 0.2, width: width, color: Self.red)
            let c = try outlineCompositor(rig, pixels, width: w, height: h, outline: outline)
            let out: [[UInt16]] = try outlineScene(rig, c, width: w, height: h)
            let mask: [Float] = outline.referenceMask(pixels, width: w, height: h)
            var outlined = 0
            for y in 0..<h {
                for x in 0..<w {
                    let i: Int = y * w + x
                    let changed: Bool = out[i] != input[i]
                    XCTAssertEqual(changed, mask[i] > 0, "width \(width) (\(x), \(y)): GPU and reference agree")
                    if mask[i] >= 1 { XCTAssertEqual(out[i], redHalves, "full-mask pixel (\(x), \(y)) is the outline colour") }
                    if changed { outlined += 1 }
                    // A boundary lies between pixels b − 1 and b (b = 8, 16, …); taps reach `width` pixels.
                    let nearX: Bool = Self.nearBoundary(x, extent: w, size: size, width: width)
                    let nearY: Bool = Self.nearBoundary(y, extent: h, size: size, width: width)
                    if !nearX && !nearY {
                        XCTAssertFalse(changed, "width \(width) (\(x), \(y)) is inside a square: no outline")
                    }
                }
            }
            // Every boundary between two squares is outlined on both sides: each column x = 7, 8 (and the rows y = 7, 8).
            for b in stride(from: size, to: w, by: size) {
                for y in [3, 12, 20] {
                    XCTAssertNotEqual(out[y * w + b - 1], input[y * w + b - 1], "left of the boundary at x = \(b)")
                    XCTAssertNotEqual(out[y * w + b], input[y * w + b], "right of the boundary at x = \(b)")
                }
            }
            XCTAssertGreaterThan(outlined, w * h / 6, "boundaries are drawn")
        }
    }

    func testEdgeOutlineThresholdAboveTheContrastDrawsNothing() throws {
        let rig = try GPURig()
        let w = 24, h = 16
        let pixels: [Pixel] = Self.checkerboard(width: w, height: h, size: 8, Pixel(0.25, 0.25, 0.25, 1), Pixel(0.5, 0.5, 0.5, 1))
        let input: [[UInt16]] = Self.outlineHalves(pixels)
        let high = try outlineCompositor(rig, pixels, width: w, height: h,
                                         outline: EdgeOutline(isEnabled: true, threshold: 0.3, width: 2, color: Self.red))
        XCTAssertEqual(try outlineScene(rig, high, width: w, height: h), input, "contrast 0.25 < threshold 0.3: no outline")
        let low = try outlineCompositor(rig, pixels, width: w, height: h,
                                        outline: EdgeOutline(isEnabled: true, threshold: 0.1, width: 2, color: Self.red))
        XCTAssertNotEqual(try outlineScene(rig, low, width: w, height: h), input, "below the contrast: outlined")
    }

    // MARK: - Off (FX-014-S4), order and pool (FX-014-R7, R12)

    func testEdgeOutlineOffIsBitIdenticalAndThePictureIsReturned() throws {
        let rig = try GPURig()
        let w = 32, h = 24
        let pixels: [Pixel] = Self.checkerboard(width: w, height: h, size: 4, Pixel(0, 0, 0, 1), Pixel(1, 0.5, 0.25, 1))
        let off = try outlineCompositor(rig, pixels, width: w, height: h, outline: .off)
        XCTAssertEqual(try outlineScene(rig, off, width: w, height: h), Self.outlineHalves(pixels))
        XCTAssertEqual(off.edgeOutlineFrames, 0, "no pass runs")
        XCTAssertFalse(off.holdsEdgeOutlinePicture)
        let plain = try Compositor(device: rig.device, layers: [PixelsLayer(width: w, height: h, pixels: pixels)])
        let outPlain = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(plain, into: outPlain, time: Self.outlineTime))
        let disabled = try outlineCompositor(rig, pixels, width: w, height: h,
                                             outline: EdgeOutline(isEnabled: false, threshold: 0.02, width: 3, mode: .outlineOnly))
        let outOff = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(disabled, into: outOff, time: Self.outlineTime))
        XCTAssertEqual(try rig.read(outOff), try rig.read(outPlain), "off: the screen output bit for bit")

        let c = try outlineCompositor(rig, pixels, width: w, height: h, outline: EdgeOutline(isEnabled: true))
        c.colorGrade = ColorGrade(saturation: 0.2)
        let out = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(c, into: out, time: Self.outlineTime))
        XCTAssertEqual(c.gradePassFrames, 1, "Color listed before the outline is applied before it")
        XCTAssertEqual(c.edgeOutlineFrames, 1)
        XCTAssertEqual(c.outputEffectOrder.effects.firstIndex(of: .edgeOutline), 7, "appended after Mosaic")
        XCTAssertTrue(c.holdsEdgeOutlinePicture)
        c.edgeOutline = .off
        XCTAssertFalse(c.holdsEdgeOutlinePicture, "turning it off returns the picture")
    }
}
#endif
