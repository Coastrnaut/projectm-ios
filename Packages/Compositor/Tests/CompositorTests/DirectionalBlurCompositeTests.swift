// FX-007-T07: the directional blur through the real Metal compositor (FX-007-S1 to S5). The roadmap acceptance "Angle
// zero blurs horizontally and radius zero is identity": off and a zero radius are bit-identical on random content and
// hold no picture; at 0° a short vertical line spreads only along its rows (every other row unchanged, each row's
// energy kept) and at 90° only along its columns; at the maximum radius every value stays within the frame's range;
// the GPU matches the CPU reference; the shader declares the fixed 16-tap budget. Small frames, one frame each.
// Skipped without Metal. Reuses FX-006's `PixelsLayer` (ChromaticSplitCompositeTests.swift).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import XCTest

final class DirectionalBlurCompositeTests: XCTestCase {
    private static let time: UInt64 = 1_000_000_000
    /// 0.02 × 300 = a 6-px radius.
    private static let side = 300
    private let maximum = DirectionalBlur(isEnabled: true, radius: 0.02)

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

    private func compositor(_ rig: GPURig, _ pixels: [Pixel], width: Int, height: Int, blur: DirectionalBlur) throws -> Compositor {
        let c = try Compositor(device: rig.device, layers: [PixelsLayer(width: width, height: height, pixels: pixels)])
        c.directionalBlur = blur
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

    // MARK: - Radius zero is identity (FX-007-S1)

    func testOffAndZeroRadiusAreBitIdenticalOnRandomContent() throws {
        let rig = try GPURig()
        let w = 37, h = 29
        let pixels: [Pixel] = Self.random(width: w, height: h, seed: 7)
        let off = try compositor(rig, pixels, width: w, height: h, blur: .off)
        let zero = try compositor(rig, pixels, width: w, height: h, blur: DirectionalBlur(isEnabled: true, radius: 0, angleDegrees: 30))
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
        XCTAssertEqual(zero.directionalBlurFrames, 0, "no pass runs")
        XCTAssertFalse(zero.holdsDirectionalBlurPicture, "no picture is held")
    }

    // MARK: - Angle zero blurs horizontally (FX-007-S2)

    /// A short bright line across `range` (vertical at `column`, or horizontal at row `column`).
    private func line(vertical: Bool, at column: Int, range: ClosedRange<Int>) -> [Pixel] {
        let s: Int = Self.side
        var pixels = [Pixel](repeating: Pixel(0, 0, 0, 1), count: s * s)
        for k in range { pixels[vertical ? k * s + column : column * s + k] = Pixel(1, 1, 1, 1) }
        return pixels
    }

    func testAngleZeroSpreadsAVerticalLineOnlyAlongItsRows() throws {
        let rig = try GPURig()
        let s: Int = Self.side
        let pixels: [Pixel] = line(vertical: true, at: 150, range: 140...147)
        let out: [Pixel] = try scene(rig, try compositor(rig, pixels, width: s, height: s, blur: maximum), width: s, height: s)
        for y in 0..<s where !(140...147).contains(y) {
            for x in 0..<s where out[y * s + x] != pixels[y * s + x] {
                XCTFail("row \(y) changed at x = \(x): \(out[y * s + x])")
                return
            }
        }
        for y in 140...147 {
            let row: [Pixel] = Array(out[(y * s)..<(y * s + s)])
            let energy: Float = row.reduce(Float(0)) { (e: Float, p: Pixel) -> Float in e + p.x }
            XCTAssertEqual(energy, 1, accuracy: 0.01, "row \(y) keeps its energy")
            XCTAssertGreaterThan(row[146].x, 0, "spreads left")
            XCTAssertGreaterThan(row[154].x, 0, "spreads right")
            XCTAssertLessThan(row[150].x, 0.5, "the line is spread out")
            XCTAssertEqual(row[143].x, 0, "nothing beyond the radius")
            XCTAssertEqual(row[157].x, 0)
        }
    }

    func testNinetyDegreesSpreadsAHorizontalLineOnlyAlongItsColumns() throws {
        let rig = try GPURig()
        let s: Int = Self.side
        let pixels: [Pixel] = line(vertical: false, at: 150, range: 140...147)
        let blur = DirectionalBlur(isEnabled: true, radius: 0.02, angleDegrees: 90)
        let out: [Pixel] = try scene(rig, try compositor(rig, pixels, width: s, height: s, blur: blur), width: s, height: s)
        for x in 0..<s where !(140...147).contains(x) {
            for y in 0..<s where out[y * s + x] != pixels[y * s + x] {
                XCTFail("column \(x) changed at y = \(y): \(out[y * s + x])")
                return
            }
        }
        for x in 140...147 {
            let energy: Float = (0..<s).reduce(Float(0)) { (e: Float, y: Int) -> Float in e + out[y * s + x].x }
            XCTAssertEqual(energy, 1, accuracy: 0.01, "column \(x) keeps its energy")
            XCTAssertGreaterThan(out[146 * s + x].x, 0, "spreads up")
            XCTAssertGreaterThan(out[154 * s + x].x, 0, "spreads down")
        }
    }

    // MARK: - Bounds, reference, tap budget, pool (FX-007-S3 to S5)

    func testMaximumRadiusStaysInRangeAndMatchesTheReference() throws {
        let rig = try GPURig()
        let w = 120, h = 100   // 0.02 × 100 = a 2-px radius
        let pixels: [Pixel] = Self.random(width: w, height: h, seed: 11)
        var low = Pixel(repeating: .infinity), high = Pixel(repeating: -.infinity)
        for p in pixels { low = pointwiseMin(low, p); high = pointwiseMax(high, p) }
        for angle in [0.0, 45, 90, 150] {
            let blur = DirectionalBlur(isEnabled: true, radius: 0.02, angleDegrees: angle)
            let c = try compositor(rig, pixels, width: w, height: h, blur: blur)
            let out: [Pixel] = try scene(rig, c, width: w, height: h)
            let expected: [Pixel] = blur.reference(pixels, width: w, height: h)
            var worst: Float = 0
            for (i, p) in out.enumerated() {
                XCTAssertTrue(all(p .>= low - 1.0 / 1024) && all(p .<= high + 1.0 / 1024), "\(angle)°: pixel \(i) = \(p) outside")
                let d: Pixel = p - expected[i]
                worst = max(worst, max(max(Swift.abs(d.x), Swift.abs(d.y)), max(Swift.abs(d.z), Swift.abs(d.w))))
            }
            XCTAssertLessThanOrEqual(worst, 1.0 / 256, "\(angle)°: GPU vs reference")
            XCTAssertEqual(c.directionalBlurFrames, 1)
        }
    }

    func testShaderDeclaresTheFixedTapBudgetAndThePictureIsReturned() throws {
        XCTAssertTrue(DirectionalBlurPass.source.contains("constant uint cmp_dirblur_taps = \(DirectionalBlur.tapCount);"))
        XCTAssertTrue(DirectionalBlurPass.source.contains("for (uint i = 0; i < cmp_dirblur_taps; i++)"),
                      "the loop runs the constant, never a radius-dependent count")
        XCTAssertTrue(CompositorShaderSources.archived.contains(DirectionalBlurPass.source), "in the pipeline-archive key")
        let rig = try GPURig()
        let w = 32, h = 24
        let c = try compositor(rig, Self.random(width: w, height: h, seed: 3), width: w, height: h, blur: maximum)
        c.colorGrade = ColorGrade(saturation: 0.2)
        let out = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(c, into: out, time: Self.time))
        XCTAssertEqual(c.gradePassFrames, 1, "Color listed before the blur is applied before it")
        XCTAssertTrue(c.holdsDirectionalBlurPicture)
        c.directionalBlur = .off
        XCTAssertFalse(c.holdsDirectionalBlurPicture, "turning it off returns the picture")
    }
}
#endif
