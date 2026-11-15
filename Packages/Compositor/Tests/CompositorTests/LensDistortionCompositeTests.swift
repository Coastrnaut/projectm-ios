// FX-016-T07: the lens distortion through the real Metal compositor (FX-016-S1, S2, S4) — the shader unit test. The
// roadmap acceptance "zero distortion is identity; corners remain safely sampled": off and strength 0 (zoom on and off)
// are bit-identical on random content with no pass; the pass itself run with a zero coefficient returns its input bit for
// bit; at strength ±1, zoom on and off, the GPU equals the CPU reference within half-float rounding, every value is finite
// (HDR corners included), the middle pixel is exact, and only barrel without zoom shows transparent-black corners. Small
// frames, one frame each. Skipped without Metal. `PixelsLayer` comes from `ChromaticSplitCompositeTests`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import XCTest

final class LensDistortionCompositeTests: XCTestCase {
    private static let lensTime: UInt64 = 1_000_000_000

    private static func lensQ(_ k: Int) -> Float { Float(k) / 1024 }

    /// Seeded random premultiplied content (colour ≤ alpha), half-exact.
    private static func lensRandom(width: Int, height: Int, seed: UInt64) -> [Pixel] {
        var state: UInt64 = seed
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        return (0..<(width * height)).map { (_: Int) -> Pixel in
            let a: Int = 256 + next(769)
            return Pixel(lensQ(next(a + 1)), lensQ(next(a + 1)), lensQ(next(a + 1)), lensQ(a))
        }
    }

    private func lensCompositor(_ rig: GPURig, _ pixels: [Pixel], width: Int, height: Int,
                                lens: LensDistortion) throws -> Compositor {
        let c = try Compositor(device: rig.device, layers: [PixelsLayer(width: width, height: height, pixels: pixels)])
        c.lensDistortion = lens
        return c
    }

    /// Copies a half-float picture into 4-half quads per pixel.
    private func lensHalves(_ rig: GPURig, _ texture: MTLTexture, width: Int, height: Int) throws -> [[UInt16]] {
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
        let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: width * height * 4)
        let flat = Array(UnsafeBufferPointer(start: halves, count: width * height * 4))
        return stride(from: 0, to: flat.count, by: 4).map { (i: Int) -> [UInt16] in Array(flat[i..<(i + 4)]) }
    }

    /// The stack phase plus output effects (`encodeScene`).
    private func lensScene(_ rig: GPURig, _ c: Compositor, width: Int, height: Int) throws -> [[UInt16]] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let shown = try XCTUnwrap(c.encodeScene(width: width, height: height, commandBuffer: commands,
                                                presentationTimeNanoseconds: Self.lensTime, contentScale: 2,
                                                reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        return try lensHalves(rig, shown, width: width, height: height)
    }

    private static func lensHalfBits(_ pixels: [Pixel]) -> [[UInt16]] {
        pixels.map { (p: Pixel) -> [UInt16] in
            [Float16(p.x).bitPattern, Float16(p.y).bitPattern, Float16(p.z).bitPattern, Float16(p.w).bitPattern]
        }
    }

    private static func lensFloats(_ halves: [[UInt16]]) -> [Pixel] {
        halves.map { (h: [UInt16]) -> Pixel in
            Pixel(Float(Float16(bitPattern: h[0])), Float(Float16(bitPattern: h[1])), Float(Float16(bitPattern: h[2])),
                  Float(Float16(bitPattern: h[3])))
        }
    }

    // MARK: - Zero distortion is the identity (FX-016-S1)

    func testLensDistortionOffAndZeroStrengthAreBitIdentical() throws {
        let rig = try GPURig()
        let w = 37, h = 29
        let pixels: [Pixel] = Self.lensRandom(width: w, height: h, seed: 16)
        let off = try lensCompositor(rig, pixels, width: w, height: h, lens: .off)
        let reference: [[UInt16]] = try lensScene(rig, off, width: w, height: h)
        XCTAssertEqual(reference, Self.lensHalfBits(pixels), "the stack result is the input picture itself")
        let outOff = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(off, into: outOff, time: Self.lensTime + 16_666_667))
        let screen: [Pixel] = try rig.read(outOff)
        let cases: [LensDistortion] = [LensDistortion(isEnabled: true, strength: 0),
                                       LensDistortion(isEnabled: true, strength: 0, zoomToFill: false),
                                       LensDistortion(isEnabled: false, strength: 1, zoomToFill: false)]
        for lens in cases {
            let c = try lensCompositor(rig, pixels, width: w, height: h, lens: lens)
            XCTAssertEqual(try lensScene(rig, c, width: w, height: h), reference, "\(lens): bit for bit")
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.lensTime + 16_666_667))
            XCTAssertEqual(try rig.read(out), screen, "\(lens): the screen output")
            XCTAssertEqual(c.lensDistortionFrames, 0, "no pass runs")
            XCTAssertFalse(c.holdsLensDistortionPicture, "no picture is held")
        }
    }

    func testLensDistortionShaderWithZeroCoefficientIsBitIdentical() throws {
        let rig = try GPURig()
        for (w, h) in [(37, 29), (2, 2), (3, 64)] {
            var pixels: [Pixel] = Self.lensRandom(width: w, height: h, seed: UInt64(w * h))
            pixels[0] = Pixel(-0.0, 60_000, 0, 1)   // a negative zero and an HDR value survive the exact read
            let source = try lensCompositor(rig, pixels, width: w, height: h, lens: .off)
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let input = try XCTUnwrap(source.encodeScene(width: w, height: h, commandBuffer: commands,
                                                         presentationTimeNanoseconds: Self.lensTime, contentScale: 2,
                                                         reduceFlashing: false, audio: .empty))
            let library = try CompositorShaders.library(device: rig.device, source: CompositorShaders.source + LensDistortionPass.source)
            let pass = try LensDistortionPass(device: rig.device, library: library,
                                              vertex: try CompositorShaders.function(library, "cmp_fullscreen"))
            let pool = TexturePool(device: rig.device)
            for zoom in [true, false] {
                let block = LensDistortion(isEnabled: true, strength: 0, zoomToFill: zoom).block(width: w, height: h)
                XCTAssertEqual(block.coefficient, 0)
                let warped = try XCTUnwrap(pass.encode(input: input, block: block, pool: pool, fence: nil, commandBuffer: commands))
                XCTAssertEqual(warped.width, w)
            }
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertNil(commands.error)
            let block = LensDistortion(isEnabled: true, strength: 0).block(width: w, height: h)
            let check = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let warped = try XCTUnwrap(pass.encode(input: input, block: block, pool: pool, fence: nil, commandBuffer: check))
            check.commit()
            check.waitUntilCompleted()
            XCTAssertEqual(try lensHalves(rig, warped, width: w, height: h), try lensHalves(rig, input, width: w, height: h),
                           "\(w) × \(h): the warp at k = 0 is the identity, bit for bit")
            XCTAssertEqual(pass.frames, 3)
        }
    }

    // MARK: - Strongest barrel and pincushion: reference, finite, safe corners (FX-016-S2, S4)

    func testLensDistortionExtremesMatchTheReferenceAndStayFinite() throws {
        let rig = try GPURig()
        for (w, h) in [(49, 27), (9, 65)] {
            var pixels: [Pixel] = Self.lensRandom(width: w, height: h, seed: 7)
            for corner in [0, w - 1, (h - 1) * w, h * w - 1] { pixels[corner] = Pixel(60_000, 2_000, 1, 1) }   // HDR corners
            let input: [Pixel] = Self.lensFloats(Self.lensHalfBits(pixels))
            for strength in [1.0, -1.0] {
                for zoom in [true, false] {
                    let lens = LensDistortion(isEnabled: true, strength: strength, zoomToFill: zoom)
                    let c = try lensCompositor(rig, pixels, width: w, height: h, lens: lens)
                    let out: [Pixel] = Self.lensFloats(try lensScene(rig, c, width: w, height: h))
                    XCTAssertEqual(c.lensDistortionFrames, 1, "the pass ran")
                    let expected: [Pixel] = lens.reference(input, width: w, height: h)
                    let b: LensDistortion.Block = lens.block(width: w, height: h)
                    var worst: Float = 0
                    var black = 0
                    for y in 0..<h {
                        for x in 0..<w {
                            let i = y * w + x
                            let (s, inside) = LensDistortion.sample(x: x, y: y, block: b)
                            let edge: Float = min(s.x, Float(w) - s.x, s.y, Float(h) - s.y)
                            for ch in 0..<4 { XCTAssertTrue(out[i][ch].isFinite, "(\(x), \(y)) finite") }
                            if !inside { black += out[i] == Pixel(0, 0, 0, 0) ? 1 : 0 }
                            guard Swift.abs(edge) > 1e-3 else { continue }   // a sample on the picture's edge may round either way
                            for ch in 0..<4 {
                                let tolerance: Float = Swift.abs(expected[i][ch]) / 256 + 2e-3
                                worst = max(worst, Swift.abs(out[i][ch] - expected[i][ch]) - tolerance)
                            }
                        }
                    }
                    XCTAssertLessThanOrEqual(worst, 0, "strength \(strength), zoom \(zoom), \(w) × \(h): GPU = reference")
                    let middle: Int = (h / 2) * w + w / 2
                    XCTAssertEqual(out[middle], input[middle], "the middle pixel (odd sizes: on the centre) stays exact")
                    let cornerBlack: Bool = out[0] == Pixel(0, 0, 0, 0) && out[h * w - 1] == Pixel(0, 0, 0, 0)
                    XCTAssertEqual(cornerBlack, strength > 0 && !zoom, "strength \(strength), zoom \(zoom): corners")
                    if strength < 0 || zoom { XCTAssertEqual(black, 0, "every sample inside the picture") }
                }
            }
        }
    }

    // MARK: - Order and pool (FX-016-R7, R11)

    func testLensDistortionOrderFoldsColorBeforeItAndThePictureIsReturned() throws {
        let rig = try GPURig()
        let w = 32, h = 24
        let pixels: [Pixel] = Self.lensRandom(width: w, height: h, seed: 4)
        func render(_ order: OutputEffectOrder) throws -> Compositor {
            let c = try lensCompositor(rig, pixels, width: w, height: h, lens: LensDistortion(isEnabled: true, strength: 0.6))
            c.colorGrade = ColorGrade(saturation: 0.2)
            c.outputEffectOrder = order
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.lensTime))
            return c
        }
        let standard = try render(.standard)
        XCTAssertEqual(standard.gradePassFrames, 1, "Color listed before the warp is applied before it")
        XCTAssertEqual(standard.lensDistortionFrames, 1)
        let late = try render(OutputEffectOrder([.lensDistortion, .trails, .chromatic, .grade]))
        XCTAssertEqual(late.gradePassFrames, 0, "Color after the warp stays in the output pass")
        XCTAssertTrue(late.holdsLensDistortionPicture)
        late.lensDistortion = LensDistortion(isEnabled: true, strength: 0)
        XCTAssertFalse(late.holdsLensDistortionPicture, "strength 0 returns the picture")
    }
}
#endif
