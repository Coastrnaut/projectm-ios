// FX-015-T07: the vignette through the real Metal compositor (FX-015-S1 to S4) — the shader unit test. The roadmap
// acceptance "Center brightness stays unchanged at zero intensity": off and intensity 0 (several softness and centre
// values) are bit-identical on random content, centre and corners included, with no pass; on a uniform picture the
// centre pixel is exact at any intensity, brightness never rises from the centre to each corner and the corners are
// darker; moving the centre moves the unchanged region; the GPU equals the CPU reference within half-float rounding;
// HDR input gives finite output. Small frames, one frame each. Skipped without Metal. `PixelsLayer` comes from
// `ChromaticSplitCompositeTests`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import XCTest

final class VignetteCompositeTests: XCTestCase {
    private static let vignetteTime: UInt64 = 1_000_000_000

    private static func vignetteQ(_ k: Int) -> Float { Float(k) / 1024 }

    /// Seeded random premultiplied content (colour ≤ alpha), half-exact.
    private static func vignetteRandom(width: Int, height: Int, seed: UInt64) -> [Pixel] {
        var state: UInt64 = seed
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        return (0..<(width * height)).map { (_: Int) -> Pixel in
            let a: Int = 256 + next(769)
            return Pixel(vignetteQ(next(a + 1)), vignetteQ(next(a + 1)), vignetteQ(next(a + 1)), vignetteQ(a))
        }
    }

    private func vignetteCompositor(_ rig: GPURig, _ pixels: [Pixel], width: Int, height: Int,
                                    vignette: Vignette) throws -> Compositor {
        let c = try Compositor(device: rig.device, layers: [PixelsLayer(width: width, height: height, pixels: pixels)])
        c.vignette = vignette
        return c
    }

    /// The stack phase plus output effects (`encodeScene`), one 4-half quad per pixel.
    private func vignetteScene(_ rig: GPURig, _ c: Compositor, width: Int, height: Int) throws -> [[UInt16]] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let shown = try XCTUnwrap(c.encodeScene(width: width, height: height, commandBuffer: commands,
                                                presentationTimeNanoseconds: Self.vignetteTime, contentScale: 2,
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

    private static func vignetteHalves(_ pixels: [Pixel]) -> [[UInt16]] {
        pixels.map { (p: Pixel) -> [UInt16] in
            [Float16(p.x).bitPattern, Float16(p.y).bitPattern, Float16(p.z).bitPattern, Float16(p.w).bitPattern]
        }
    }

    private static func vignetteFloats(_ halves: [[UInt16]]) -> [Pixel] {
        halves.map { (h: [UInt16]) -> Pixel in
            Pixel(Float(Float16(bitPattern: h[0])), Float(Float16(bitPattern: h[1])), Float(Float16(bitPattern: h[2])),
                  Float(Float16(bitPattern: h[3])))
        }
    }

    // MARK: - Zero intensity is the original frame (FX-015-S1)

    func testVignetteOffAndZeroIntensityAreBitIdenticalAtCentreAndCorners() throws {
        let rig = try GPURig()
        let w = 37, h = 29
        let pixels: [Pixel] = Self.vignetteRandom(width: w, height: h, seed: 15)
        let off = try vignetteCompositor(rig, pixels, width: w, height: h, vignette: .off)
        let reference: [[UInt16]] = try vignetteScene(rig, off, width: w, height: h)
        XCTAssertEqual(reference, Self.vignetteHalves(pixels), "the stack result is the input picture itself")
        let outOff = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(off, into: outOff, time: Self.vignetteTime + 16_666_667))
        let screen: [Pixel] = try rig.read(outOff)
        let cases: [Vignette] = [Vignette(isEnabled: true, intensity: 0),
                                 Vignette(isEnabled: true, intensity: 0, softness: 0.9, centerX: 0, centerY: 1),
                                 Vignette(isEnabled: true, intensity: 0, softness: 0.1, centerX: 0.8, centerY: 0.2),
                                 Vignette(isEnabled: false, intensity: 1, softness: 0.9)]
        for v in cases {
            let c = try vignetteCompositor(rig, pixels, width: w, height: h, vignette: v)
            let scene: [[UInt16]] = try vignetteScene(rig, c, width: w, height: h)
            XCTAssertEqual(scene, reference, "\(v): bit for bit")
            for i in [(h / 2) * w + w / 2, 0, w - 1, (h - 1) * w, h * w - 1] {
                XCTAssertEqual(scene[i], reference[i], "\(v): centre and corners unchanged")
            }
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.vignetteTime + 16_666_667))
            XCTAssertEqual(try rig.read(out), screen, "\(v): the screen output")
            XCTAssertEqual(c.vignetteFrames, 0, "no pass runs")
            XCTAssertFalse(c.holdsVignettePicture, "no picture is held")
        }
    }

    // MARK: - Centre exact, monotonic falloff, centre control (FX-015-S2, S3)

    func testVignetteCentreIsExactAndBrightnessFallsToEveryCorner() throws {
        let rig = try GPURig()
        let w = 48, h = 36
        let grey = Pixel(0.5, 0.5, 0.5, 1)
        let uniform = [Pixel](repeating: grey, count: w * h)
        for (intensity, softness) in [(0.3, 0.5), (1.0, 0.9), (1.0, 0.1)] {
            let c = try vignetteCompositor(rig, uniform, width: w, height: h,
                                           vignette: Vignette(isEnabled: true, intensity: intensity, softness: softness))
            let out: [Pixel] = Self.vignetteFloats(try vignetteScene(rig, c, width: w, height: h))
            XCTAssertEqual(c.vignetteFrames, 1, "the pass ran")
            for (x, y) in [(23, 17), (24, 18), (23, 18), (24, 17)] {
                XCTAssertEqual(out[y * w + x], grey, "intensity \(intensity), softness \(softness): middle pixel exact")
            }
            for corner in [SIMD2(0, 0), SIMD2(w - 1, 0), SIMD2(0, h - 1), SIMD2(w - 1, h - 1)] {
                var previous: Float = 0.5
                for k in 0...24 {
                    let x: Int = 24 + (corner.x - 24) * k / 24
                    let y: Int = 18 + (corner.y - 18) * k / 24
                    let p: Pixel = out[y * w + x]
                    XCTAssertLessThanOrEqual(p.x, previous, "never brighter towards \(corner) (step \(k))")
                    XCTAssertEqual(p.w, 1, "alpha kept")
                    previous = p.x
                }
                XCTAssertLessThan(previous, 0.5, "corner \(corner) is darker than the centre")
            }
        }
    }

    func testVignetteCentreControlMovesTheUnchangedRegion() throws {
        let rig = try GPURig()
        let w = 64, h = 32
        let grey = Pixel(0.5, 0.5, 0.5, 1)
        let c = try vignetteCompositor(rig, [Pixel](repeating: grey, count: w * h), width: w, height: h,
                                       vignette: Vignette(isEnabled: true, intensity: 1, softness: 0.9, centerX: 0.25, centerY: 0.5))
        let out: [Pixel] = Self.vignetteFloats(try vignetteScene(rig, c, width: w, height: h))
        var sum = SIMD2<Float>(0, 0)
        var count: Float = 0
        for y in 0..<h {
            for x in 0..<w where out[y * w + x] == grey {
                sum += SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
                count += 1
            }
        }
        XCTAssertGreaterThan(count, 0)
        XCTAssertEqual(sum.x / count, 16, accuracy: 1, "the unchanged region is centred a quarter of the width in")
        XCTAssertEqual(sum.y / count, 16, accuracy: 1)
        XCTAssertEqual(out[16 * w + 16], grey, "the pixel at the new centre is unchanged")
        XCTAssertGreaterThan(out[16 * w].x, out[16 * w + w - 1].x, "the left edge is brighter than the right edge")
    }

    // MARK: - Reference and finite output (FX-015-S4)

    func testVignetteMatchesTheReferenceAndStaysFinite() throws {
        let rig = try GPURig()
        let w = 41, h = 23
        var pixels: [Pixel] = Self.vignetteRandom(width: w, height: h, seed: 5)
        pixels[0] = Pixel(60_000, 2_000, 1, 1)   // HDR near the half-float limit, in a corner
        pixels[w * h - 1] = Pixel(0, 0, 0, 0)
        let v = Vignette(isEnabled: true, intensity: 0.85, softness: 0.4, centerX: 0.35, centerY: 0.6)
        let c = try vignetteCompositor(rig, pixels, width: w, height: h, vignette: v)
        let out: [Pixel] = Self.vignetteFloats(try vignetteScene(rig, c, width: w, height: h))
        let input: [Pixel] = Self.vignetteFloats(Self.vignetteHalves(pixels))
        let expected: [Pixel] = v.reference(input, width: w, height: h)
        let b: Vignette.Block = v.block(width: w, height: h)
        var worst: Float = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                for ch in 0..<4 {
                    XCTAssertTrue(out[i][ch].isFinite, "(\(x), \(y)) finite")
                    XCTAssertLessThanOrEqual(out[i][ch], input[i][ch], "(\(x), \(y)) never brighter")
                    let tolerance: Float = Swift.abs(expected[i][ch]) / 512 + 1e-6
                    worst = max(worst, Swift.abs(out[i][ch] - expected[i][ch]) - tolerance)
                }
                if Vignette.factor(x: x, y: y, block: b) == 1 { XCTAssertEqual(out[i], input[i], "(\(x), \(y)) clear core exact") }
            }
        }
        XCTAssertLessThanOrEqual(worst, 0, "GPU = reference within 2⁻⁹ relative")
    }

    // MARK: - Order and pool (FX-015-R7, R11)

    func testVignetteOrderFoldsColorBeforeItAndThePictureIsReturned() throws {
        let rig = try GPURig()
        let w = 32, h = 24
        let pixels: [Pixel] = Self.vignetteRandom(width: w, height: h, seed: 4)
        func render(_ order: OutputEffectOrder) throws -> Compositor {
            let c = try vignetteCompositor(rig, pixels, width: w, height: h, vignette: Vignette(isEnabled: true, intensity: 0.7))
            c.colorGrade = ColorGrade(saturation: 0.2)
            c.outputEffectOrder = order
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.vignetteTime))
            return c
        }
        let standard = try render(.standard)
        XCTAssertEqual(standard.gradePassFrames, 1, "Color listed before the vignette is applied before it")
        XCTAssertEqual(standard.vignetteFrames, 1)
        let late = try render(OutputEffectOrder([.vignette, .trails, .chromatic, .grade]))
        XCTAssertEqual(late.gradePassFrames, 0, "Color after the vignette stays in the output pass")
        XCTAssertTrue(late.holdsVignettePicture)
        late.vignette = .off
        XCTAssertFalse(late.holdsVignettePicture, "turning it off returns the picture")
    }
}
#endif
