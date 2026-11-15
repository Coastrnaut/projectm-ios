// FX-006-T07: the chromatic split through the real Metal compositor (FX-006-S1 to S4). The roadmap acceptance "Zero
// offset is exact pass-through and edges stay within frame bounds": off and a zero amount are bit-identical on random
// content; at the maximum amount every output value comes from inside the frame and the border ring is unchanged; a
// line moves by exactly ±2 px in red and blue; the GPU matches the CPU reference. Small frames, one frame each.
// Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import XCTest

/// Shows a fixed picture (linear premultiplied RGBA, rows top first), uploaded through a shared texture and a blit.
final class PixelsLayer: LayerSource {
    let layerName = "pixels"
    let fallback = LayerFallback.transparent
    let width: Int
    let height: Int
    let pixels: [Pixel]

    init(width: Int, height: Int, pixels: [Pixel]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        d.storageMode = .shared
        guard let staging = commandBuffer.device.makeTexture(descriptor: d) else { throw .resourceUnavailable("staging") }
        let halves: [UInt16] = pixels.flatMap { (p: Pixel) -> [UInt16] in
            [Float16(p.x).bitPattern, Float16(p.y).bitPattern, Float16(p.z).bitPattern, Float16(p.w).bitPattern]
        }
        halves.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            staging.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: raw.baseAddress!,
                            bytesPerRow: width * 8)
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { throw .resourceUnavailable("blit") }
        blit.copy(from: staging, to: picture)
        blit.endEncoding()
    }
}

final class ChromaticSplitCompositeTests: XCTestCase {
    private static let time: UInt64 = 1_000_000_000
    private let maximum = ChromaticSplit(isEnabled: true, amount: 0.02)

    /// Values exactly representable in half floats: k / 1024.
    private static func q(_ k: Int) -> Float { Float(k) / 1024 }

    /// Seeded random premultiplied content (colour ≤ alpha), half-exact.
    private static func random(width: Int, height: Int, seed: UInt64) -> [Pixel] {
        var state: UInt64 = seed
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        return (0..<(width * height)).map { (_: Int) -> Pixel in
            let a: Int = 256 + next(769)
            return Pixel(q(next(a + 1)), q(next(a + 1)), q(next(a + 1)), q(a))
        }
    }

    /// Unique border colours around a uniform interior (every channel non-zero, all half-exact).
    private static func bordered(width: Int, height: Int) -> [Pixel] {
        var pixels = [Pixel](repeating: Pixel(q(900), q(910), q(920), 1), count: width * height)
        var i = 0
        for y in 0..<height {
            for x in 0..<width where x == 0 || y == 0 || x == width - 1 || y == height - 1 {
                pixels[y * width + x] = Pixel(q(256 + i), q(700 - i), q(300 + i), 1)
                i += 1
            }
        }
        return pixels
    }

    private func compositor(_ rig: GPURig, _ pixels: [Pixel], width: Int, height: Int, split: ChromaticSplit) throws -> Compositor {
        let c = try Compositor(device: rig.device, layers: [PixelsLayer(width: width, height: height, pixels: pixels)])
        c.chromaticSplit = split
        return c
    }

    /// The stack phase plus output effects (`encodeScene`), read back as raw halves.
    private func sceneHalves(_ rig: GPURig, _ c: Compositor, width: Int, height: Int) throws -> [UInt16] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let shown = try XCTUnwrap(c.encodeScene(width: width, height: height, commandBuffer: commands,
                                                presentationTimeNanoseconds: Self.time, contentScale: 2, reduceFlashing: false,
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

    private func scene(_ rig: GPURig, _ c: Compositor, width: Int, height: Int) throws -> [Pixel] {
        let h: [UInt16] = try sceneHalves(rig, c, width: width, height: height)
        return stride(from: 0, to: h.count, by: 4).map { (i: Int) -> Pixel in
            Pixel(Half.toFloat(h[i]), Half.toFloat(h[i + 1]), Half.toFloat(h[i + 2]), Half.toFloat(h[i + 3]))
        }
    }

    private static func isBorder(_ i: Int, _ w: Int, _ h: Int) -> Bool {
        let x: Int = i % w, y: Int = i / w
        return x == 0 || y == 0 || x == w - 1 || y == h - 1
    }

    // MARK: - Zero is exact pass-through (FX-006-S1)

    func testOffAndZeroAmountAreBitIdenticalOnRandomContent() throws {
        let rig = try GPURig()
        let w = 37, h = 29
        let pixels: [Pixel] = Self.random(width: w, height: h, seed: 6)
        let off = try compositor(rig, pixels, width: w, height: h, split: .off)
        let zero = try compositor(rig, pixels, width: w, height: h, split: ChromaticSplit(isEnabled: true, amount: 0, angleDegrees: 45))
        let reference: [UInt16] = try sceneHalves(rig, off, width: w, height: h)
        XCTAssertEqual(try sceneHalves(rig, zero, width: w, height: h), reference, "the stack result, bit for bit")
        let input: [UInt16] = pixels.flatMap { (p: Pixel) -> [UInt16] in
            [Float16(p.x).bitPattern, Float16(p.y).bitPattern, Float16(p.z).bitPattern, Float16(p.w).bitPattern]
        }
        XCTAssertEqual(reference, input, "and that is the input picture itself")
        let outOff = try rig.output(.rgba16Float, width: w, height: h)
        let outZero = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(off, into: outOff, time: Self.time + 16_666_667))
        XCTAssertTrue(try rig.frame(zero, into: outZero, time: Self.time + 16_666_667))
        XCTAssertEqual(try rig.read(outZero), try rig.read(outOff), "the screen output")
        XCTAssertEqual(zero.chromaticFrames, 0, "no pass runs")
        XCTAssertFalse(zero.holdsChromaticPicture, "no picture is held")
    }

    // MARK: - Edges stay within frame bounds (FX-006-S2)

    func testWholePixelShiftsReadOnlyInsideTheFrameAndKeepTheBorder() throws {
        let rig = try GPURig()
        let w = 100, h = 100   // 2% → exactly 2 px; the fade band gives 1 px next to the border: whole pixels only
        let pixels: [Pixel] = Self.bordered(width: w, height: h)
        let reds = Set(pixels.map(\.x)), greens = Set(pixels.map(\.y)), blues = Set(pixels.map(\.z))
        for angle in [0.0, 90, 180, 270] {
            let c = try compositor(rig, pixels, width: w, height: h,
                                   split: ChromaticSplit(isEnabled: true, amount: 0.02, angleDegrees: angle))
            let out: [Pixel] = try scene(rig, c, width: w, height: h)
            var moved = 0
            for (i, p) in out.enumerated() {
                XCTAssertTrue(reds.contains(p.x) && greens.contains(p.y) && blues.contains(p.z) && p.w == 1,
                              "\(angle)°: pixel \(i) = \(p) is not made of values inside the frame")
                if Self.isBorder(i, w, h) { XCTAssertEqual(p, pixels[i], "\(angle)°: border pixel \(i) changed") }
                if p != pixels[i] { moved += 1 }
            }
            XCTAssertGreaterThan(moved, 0, "\(angle)°: the split moved something")
            XCTAssertEqual(out, maximum.clampedAngle(angle).reference(pixels, width: w, height: h), "\(angle)°: GPU = reference")
            XCTAssertEqual(c.chromaticFrames, 1)
        }
    }

    func testFractionalAndRadialSplitsStayInsideTheFrame() throws {
        let rig = try GPURig()
        let w = 64, h = 40
        let pixels: [Pixel] = Self.bordered(width: w, height: h)
        var low = Pixel(repeating: .infinity), high = Pixel(repeating: -.infinity)
        for p in pixels { low = pointwiseMin(low, p); high = pointwiseMax(high, p) }
        let splits: [ChromaticSplit] = [ChromaticSplit(isEnabled: true, amount: 0.02, angleDegrees: 45),
                                        ChromaticSplit(isEnabled: true, amount: 0.02, isRadial: true)]
        for split in splits {
            let c = try compositor(rig, pixels, width: w, height: h, split: split)
            let out: [Pixel] = try scene(rig, c, width: w, height: h)
            let expected: [Pixel] = split.reference(pixels, width: w, height: h)
            for (i, p) in out.enumerated() {
                XCTAssertTrue(all(p .>= low) && all(p .<= high), "\(split): pixel \(i) = \(p) outside the frame's values")
                if Self.isBorder(i, w, h) { XCTAssertEqual(p, pixels[i], "\(split): border pixel \(i) changed") }
                let d: Pixel = p - expected[i]
                let worst: Float = max(max(Swift.abs(d.x), Swift.abs(d.y)), max(Swift.abs(d.z), Swift.abs(d.w)))
                XCTAssertLessThanOrEqual(worst, 1.0 / 512, "\(split): pixel \(i) vs reference")
            }
        }
    }

    // MARK: - Red and blue move by the expected distance (FX-006-S3)

    func testRedAndBlueShiftByTwoPixels() throws {
        let rig = try GPURig()
        let w = 100, h = 100
        var pixels = [Pixel](repeating: Pixel(0, 0, 0, 1), count: w * h)
        for k in 0..<w {
            pixels[k * w + 50] = Pixel(1, 1, 1, 1)   // column x = 50
            pixels[30 * w + k] = Pixel(1, 1, 1, 1)   // row y = 30
        }
        let right = try scene(rig, try compositor(rig, pixels, width: w, height: h, split: maximum), width: w, height: h)
        let row: Int = 70 * w
        XCTAssertEqual(right[row + 52], Pixel(1, 0, 0, 1), "red 2 px right of the column")
        XCTAssertEqual(right[row + 48], Pixel(0, 0, 1, 1), "blue 2 px left")
        XCTAssertEqual(right[row + 50], Pixel(0, 1, 0, 1), "green in place")
        let up = try scene(rig, try compositor(rig, pixels, width: w, height: h,
                                               split: ChromaticSplit(isEnabled: true, amount: 0.02, angleDegrees: 90)),
                           width: w, height: h)
        XCTAssertEqual(up[28 * w + 20], Pixel(1, 0, 0, 1), "90°: red 2 px above the row")
        XCTAssertEqual(up[32 * w + 20], Pixel(0, 0, 1, 1), "blue 2 px below")
        XCTAssertEqual(up[30 * w + 20], Pixel(0, 1, 0, 1), "green in place")
    }

    // MARK: - Order, Color folding and the pool (FX-006-R7, R11)

    func testOrderFoldsColorBeforeTheSplitAndThePictureIsReturned() throws {
        let rig = try GPURig()
        let w = 32, h = 24
        let pixels: [Pixel] = Self.random(width: w, height: h, seed: 9)
        func render(_ order: OutputEffectOrder) throws -> (Compositor, [Pixel]) {
            let c = try compositor(rig, pixels, width: w, height: h, split: maximum.clampedAngle(30))
            c.colorGrade = ColorGrade(saturation: 0.2)
            c.outputEffectOrder = order
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.time))
            return (c, try rig.read(out))
        }
        let (standard, colorFirst) = try render(.standard)
        XCTAssertEqual(standard.gradePassFrames, 1, "Color listed before the split is applied before it")
        let (late, splitFirst) = try render(OutputEffectOrder([.trails, .chromatic, .grade]))
        XCTAssertEqual(late.gradePassFrames, 0, "Color after the split stays in the output pass")
        XCTAssertNotEqual(colorFirst, splitFirst, "the order matters for a channel-mixing grade")
        XCTAssertTrue(late.holdsChromaticPicture)
        late.chromaticSplit = .off
        XCTAssertFalse(late.holdsChromaticPicture, "turning it off returns the picture")
    }
}

private extension ChromaticSplit {
    func clampedAngle(_ degrees: Double) -> ChromaticSplit {
        ChromaticSplit(isEnabled: isEnabled, amount: amount, angleDegrees: degrees, isRadial: isRadial)
    }
}
#endif
