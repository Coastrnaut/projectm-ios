// FX-008-T07: the radial blur through the real Metal compositor (FX-008-S1 to S4). The roadmap acceptance "Center
// remains stable while outer test points spread predictably": on a pattern of single bright dots at the focus and at
// 8, 16 and 32 px in four directions, at the maximum strength (25%) the focus pixel is bit-identical, every outer dot
// becomes a streak from the dot to d × 1.25 (within one pixel) on its ray, and nothing lights up off the rays; off and a
// zero strength are bit-identical; the GPU matches the CPU reference. Small frames, one frame each. Skipped without
// Metal. `PixelsLayer` comes from `ChromaticSplitCompositeTests`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import XCTest

final class RadialBlurCompositeTests: XCTestCase {
    private static let time: UInt64 = 1_000_000_000
    private let maximum = RadialBlur(isEnabled: true, strength: 0.25)
    /// Half a sample's full weight: a pixel is "lit" when a dot reaches it through at least that much.
    private static let lit: Float = 0.5 / 16

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

    private func compositor(_ rig: GPURig, _ pixels: [Pixel], width: Int, height: Int, blur: RadialBlur) throws -> Compositor {
        let c = try Compositor(device: rig.device, layers: [PixelsLayer(width: width, height: height, pixels: pixels)])
        c.radialBlur = blur
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

    private static func halves(_ pixels: [Pixel]) -> [UInt16] {
        pixels.flatMap { (p: Pixel) -> [UInt16] in
            [Float16(p.x).bitPattern, Float16(p.y).bitPattern, Float16(p.z).bitPattern, Float16(p.w).bitPattern]
        }
    }

    // MARK: - Off and zero are exact (FX-008-S1)

    func testOffAndZeroStrengthAreBitIdenticalOnRandomContent() throws {
        let rig = try GPURig()
        let w = 37, h = 29
        let pixels: [Pixel] = Self.random(width: w, height: h, seed: 8)
        let off = try compositor(rig, pixels, width: w, height: h, blur: .off)
        let zero = try compositor(rig, pixels, width: w, height: h, blur: RadialBlur(isEnabled: true, strength: 0, focusX: 0.2))
        let reference: [UInt16] = try sceneHalves(rig, off, width: w, height: h)
        XCTAssertEqual(try sceneHalves(rig, zero, width: w, height: h), reference, "the stack result, bit for bit")
        XCTAssertEqual(reference, Self.halves(pixels), "and that is the input picture itself")
        let outOff = try rig.output(.rgba16Float, width: w, height: h)
        let outZero = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(off, into: outOff, time: Self.time + 16_666_667))
        XCTAssertTrue(try rig.frame(zero, into: outZero, time: Self.time + 16_666_667))
        XCTAssertEqual(try rig.read(outZero), try rig.read(outOff), "the screen output")
        XCTAssertEqual(zero.radialBlurFrames, 0, "no pass runs")
        XCTAssertFalse(zero.holdsRadialBlurPicture, "no picture is held")
    }

    // MARK: - Centre stable, outer points spread predictably (roadmap acceptance; FX-008-S2, S3)

    /// Black frame with single white dots at the focus and at 8, 16, 32 px right, left, up and down of it.
    private static func dots(width: Int, height: Int, focus: SIMD2<Int>, directions: [SIMD2<Int>]) -> [Pixel] {
        var pixels = [Pixel](repeating: Pixel(0, 0, 0, 1), count: width * height)
        pixels[focus.y * width + focus.x] = Pixel(1, 1, 1, 1)
        for u in directions {
            for d in [8, 16, 32] {
                let p: SIMD2<Int> = focus &+ u &* d
                pixels[p.y * width + p.x] = Pixel(1, 1, 1, 1)
            }
        }
        return pixels
    }

    private static let fourWays: [SIMD2<Int>] = [SIMD2(1, 0), SIMD2(-1, 0), SIMD2(0, -1), SIMD2(0, 1)]

    func testFocusIsStableAndOuterDotsStreakByDistanceTimesStrength() throws {
        let rig = try GPURig()
        let w = 101, h = 81
        let focus = SIMD2<Int>(50, 40)   // 0.5 × 100, 0.5 × 80: whole pixels
        let pixels: [Pixel] = Self.dots(width: w, height: h, focus: focus, directions: Self.fourWays)
        let c = try compositor(rig, pixels, width: w, height: h, blur: maximum)
        let h16: [UInt16] = try sceneHalves(rig, c, width: w, height: h)
        let out: [Pixel] = try scene(rig, c, width: w, height: h)
        XCTAssertEqual(c.radialBlurFrames, 2, "the pass ran")
        let f: Int = (focus.y * w + focus.x) * 4
        XCTAssertEqual(Array(h16[f..<(f + 4)]), Self.halves([pixels[focus.y * w + focus.x]]), "the focus pixel, bit for bit")
        let s: Double = maximum.strength
        for u in Self.fourWays {
            for d in [8, 16, 32] {
                // Walk out along the ray from the dot: the lit run starts at the dot and ends at d × (1 + s).
                var end: Int = d
                while true {
                    let p: SIMD2<Int> = focus &+ u &* (end + 1)
                    guard p.x >= 0, p.y >= 0, p.x < w, p.y < h, out[p.y * w + p.x].x >= Self.lit else { break }
                    end += 1
                }
                let expected: Double = Double(d) * (1 + s)
                XCTAssertLessThanOrEqual(abs(Double(end) - expected), 1, "\(u) d=\(d): streak ends at \(end), expected \(expected)")
                let before: SIMD2<Int> = focus &+ u &* (d - 1)
                if d > 8 { XCTAssertLessThan(out[before.y * w + before.x].x, Self.lit, "\(u) d=\(d): nothing inward of the dot") }
                XCTAssertGreaterThanOrEqual(out[(focus.y + u.y * d) * w + focus.x + u.x * d].x, 1.0 / 16, "the dot stays lit")
            }
        }
        // Along the rays only: every pixel more than one pixel away from the focus row and column stays black.
        for y in 0..<h {
            for x in 0..<w where abs(y - focus.y) > 1 && abs(x - focus.x) > 1 {
                XCTAssertEqual(out[y * w + x], Pixel(0, 0, 0, 1), "(\(x), \(y)) lit off the rays")
            }
        }
    }

    func testOffCentreFocusIsStableAndStreaksRadiateFromIt() throws {
        let rig = try GPURig()
        let w = 101, h = 61
        let blur = RadialBlur(isEnabled: true, strength: 0.25, focusX: 0.25, focusY: 0.5)   // focus (25, 30)
        let focus = SIMD2<Int>(25, 30)
        let pixels: [Pixel] = Self.dots(width: w, height: h, focus: focus, directions: [SIMD2(1, 0)])
        let c = try compositor(rig, pixels, width: w, height: h, blur: blur)
        let h16: [UInt16] = try sceneHalves(rig, c, width: w, height: h)
        let f: Int = (focus.y * w + focus.x) * 4
        XCTAssertEqual(Array(h16[f..<(f + 4)]), Self.halves([Pixel(1, 1, 1, 1)]), "the moved focus pixel, bit for bit")
        let out: [Pixel] = try scene(rig, c, width: w, height: h)
        let row: [Float] = (0..<w).map { (x: Int) -> Float in out[focus.y * w + x].x }
        XCTAssertGreaterThanOrEqual(row[25 + 40], Self.lit, "d = 32 streaks to 32 × 1.25 = 40 right of the new focus")
        XCTAssertLessThan(row[25 + 42], Self.lit)
    }

    // MARK: - Reference and bounds (FX-008-S4)

    func testGPUMatchesTheReferenceForCentreAndCornerFocus() throws {
        let rig = try GPURig()
        let w = 37, h = 29
        let pixels: [Pixel] = Self.random(width: w, height: h, seed: 3)
        for blur in [maximum, RadialBlur(isEnabled: true, strength: 0.25, focusX: 0, focusY: 0),
                     RadialBlur(isEnabled: true, strength: 0.07, focusX: 1, focusY: 0.3)] {
            let c = try compositor(rig, pixels, width: w, height: h, blur: blur)
            let out: [Pixel] = try scene(rig, c, width: w, height: h)
            let expected: [Pixel] = blur.reference(pixels, width: w, height: h)
            var worst: Float = 0
            for i in 0..<out.count {
                let d: Pixel = out[i] - expected[i]
                worst = max(worst, max(max(Swift.abs(d.x), Swift.abs(d.y)), max(Swift.abs(d.z), Swift.abs(d.w))))
                XCTAssertTrue(out[i].x <= out[i].w + 1e-3 && out[i].z <= out[i].w + 1e-3, "premultiplied stays valid")
            }
            XCTAssertLessThanOrEqual(worst, 1.0 / 128, "\(blur): GPU vs reference")
        }
    }

    // MARK: - Order and pool (FX-008-R7, R11)

    func testOrderFoldsColorBeforeTheBlurAndThePictureIsReturned() throws {
        let rig = try GPURig()
        let w = 32, h = 24
        let pixels: [Pixel] = Self.random(width: w, height: h, seed: 4)
        func render(_ order: OutputEffectOrder) throws -> Compositor {
            let c = try compositor(rig, pixels, width: w, height: h, blur: maximum)
            c.colorGrade = ColorGrade(saturation: 0.2)
            c.outputEffectOrder = order
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.time))
            return c
        }
        let standard = try render(.standard)
        XCTAssertEqual(standard.gradePassFrames, 1, "Color listed before the blur is applied before it")
        XCTAssertEqual(standard.radialBlurFrames, 1)
        let late = try render(OutputEffectOrder([.radialBlur, .trails, .chromatic, .grade]))
        XCTAssertEqual(late.gradePassFrames, 0, "Color after the blur stays in the output pass")
        XCTAssertTrue(late.holdsRadialBlurPicture)
        late.radialBlur = .off
        XCTAssertFalse(late.holdsRadialBlurPicture, "turning it off returns the picture")
    }
}
#endif
