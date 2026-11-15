// FX-018-T07: the scanlines through the real Metal compositor (FX-018-S1 to S3) — the shader unit test. The roadmap
// acceptance "Spacing is consistent in pixels and disabled state is identity": off and intensity 0 are bit-identical
// on random content with no pass; `cmp_scanlines` run directly at intensity 0 is bit-identical too; for every spacing
// 2…16 at odd, portrait and landscape sizes (and spacings 2, 3, 16 at 3840 × 2160) exactly the rows (columns) with
// index mod spacing < thickness are darkened, all by one factor, every other pixel is bit-identical, and the pitch
// measured from the rendered picture equals the spacing for every pair of bands; the GPU equals the half-rounded CPU
// reference; HDR input gives finite output. One frame each; rows are compared with `memcmp` so the 4K case stays
// fast. Skipped without Metal. `PixelsLayer` comes from `ChromaticSplitCompositeTests`, `SolidLayer` from `TestLayers`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Foundation
import Metal
import XCTest

final class ScanlinesCompositeTests: XCTestCase {
    private static let scanlinesTime: UInt64 = 1_000_000_000
    /// A uniform premultiplied colour (alpha 1), half-exact.
    private static let scanlinesGrey = Pixel(0.75, 0.5, 0.25, 1)

    private static func scanlinesQ(_ k: Int) -> Float { Float(k) / 1024 }

    /// Seeded random premultiplied content (colour ≤ alpha), half-exact.
    private static func scanlinesRandom(width: Int, height: Int, seed: UInt64) -> [Pixel] {
        var state: UInt64 = seed
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        return (0..<(width * height)).map { (_: Int) -> Pixel in
            let a: Int = 256 + next(769)
            return Pixel(scanlinesQ(next(a + 1)), scanlinesQ(next(a + 1)), scanlinesQ(next(a + 1)), scanlinesQ(a))
        }
    }

    private static func scanlinesHalves(_ pixels: [Pixel]) -> [UInt16] {
        pixels.flatMap { (p: Pixel) -> [UInt16] in
            [Float16(p.x).bitPattern, Float16(p.y).bitPattern, Float16(p.z).bitPattern, Float16(p.w).bitPattern]
        }
    }

    private static func scanlinesFloats(_ halves: [UInt16]) -> [Pixel] {
        stride(from: 0, to: halves.count, by: 4).map { (i: Int) -> Pixel in
            Pixel(Float(Float16(bitPattern: halves[i])), Float(Float16(bitPattern: halves[i + 1])),
                  Float(Float16(bitPattern: halves[i + 2])), Float(Float16(bitPattern: halves[i + 3])))
        }
    }

    /// Reads an `rgba16Float` texture's raw halves, rows top first.
    private func scanlinesRead(_ rig: GPURig, _ texture: MTLTexture) throws -> [UInt16] {
        let w: Int = texture.width, h: Int = texture.height
        let rowBytes: Int = w * 8
        let buffer = try XCTUnwrap(rig.device.makeBuffer(length: rowBytes * h, options: .storageModeShared))
        let copy = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let blit = try XCTUnwrap(copy.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * h)
        blit.endEncoding()
        copy.commit()
        copy.waitUntilCompleted()
        let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: w * h * 4)
        return Array(UnsafeBufferPointer(start: halves, count: w * h * 4))
    }

    /// The stack phase plus output effects (`encodeScene`), as raw halves.
    private func scanlinesScene(_ rig: GPURig, _ c: Compositor, width: Int, height: Int, frame: UInt64 = 0) throws -> [UInt16] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let shown = try XCTUnwrap(c.encodeScene(width: width, height: height, commandBuffer: commands,
                                                presentationTimeNanoseconds: Self.scanlinesTime + frame * 16_666_667,
                                                contentScale: 2, reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        return try scanlinesRead(rig, shown)
    }

    private func scanlinesCompositor(_ rig: GPURig, _ layer: any LayerSource, _ lines: Scanlines) throws -> Compositor {
        let c = try Compositor(device: rig.device, layers: [layer])
        c.scanlines = lines
        return c
    }

    /// One row of `width` pixels of one colour, as raw halves.
    private static func scanlinesRow(_ pixel: [UInt16], width: Int) -> [UInt16] {
        (0..<width).flatMap { (_: Int) -> [UInt16] in pixel }
    }

    /// Checks a uniform-input frame: rows (or columns) with index mod p < t equal `dark` exactly, all others `grey`
    /// exactly, and the measured pitch equals p. Returns the number of dark rows (columns).
    private func scanlinesCheckUniform(_ out: [UInt16], width w: Int, height h: Int, lines: Scanlines, grey: [UInt16],
                                       dark expected: [UInt16], _ label: String) -> Int {
        // Pixel (0, 0) is always in a line. Its value is the one darkened value every line pixel must equal exactly (one
        // factor); it must be the reference within one half-float step (research FX-018-D5: the GPU's float-to-half store
        // may round towards zero where the CPU rounds to nearest).
        let dark: [UInt16] = Array(out[0..<4])
        XCTAssertTrue(Self.scanlinesWithinOneHalfStep(dark, expected), "\(label): the darkened value \(dark) is the reference \(expected)")
        let p: Int = Scanlines.clampSpacing(lines.spacing), t: Int = lines.effectiveThickness
        var darkIndices: [Int] = []
        out.withUnsafeBufferPointer { (all: UnsafeBufferPointer<UInt16>) -> Void in
            if !lines.isVertical {
                let greyRow: [UInt16] = Self.scanlinesRow(grey, width: w)
                let darkRow: [UInt16] = Self.scanlinesRow(dark, width: w)
                for y in 0..<h {
                    let row = UnsafeRawPointer(all.baseAddress! + y * w * 4)
                    let expectDark: Bool = y % p < t
                    let match: Int32 = (expectDark ? darkRow : greyRow).withUnsafeBytes { (e: UnsafeRawBufferPointer) -> Int32 in
                        memcmp(row, e.baseAddress!, w * 8)
                    }
                    XCTAssertEqual(match, 0, "\(label): row \(y) is exactly \(expectDark ? "dark" : "unchanged")")
                    if match == 0, expectDark { darkIndices.append(y) }
                }
            } else {
                let pattern: [UInt16] = (0..<w).flatMap { (x: Int) -> [UInt16] in x % p < t ? dark : grey }
                for y in 0..<h {
                    let row = UnsafeRawPointer(all.baseAddress! + y * w * 4)
                    let match: Int32 = pattern.withUnsafeBytes { (e: UnsafeRawBufferPointer) -> Int32 in memcmp(row, e.baseAddress!, w * 8) }
                    XCTAssertEqual(match, 0, "\(label): row \(y) has exactly the predicted dark columns")
                }
                for x in 0..<w where Array(all[(x * 4)..<(x * 4 + 4)]) == dark { darkIndices.append(x) }
            }
        }
        let starts: [Int] = darkIndices.filter { (i: Int) -> Bool in i == 0 || !darkIndices.contains(i - 1) }
        XCTAssertEqual(starts.first, 0, "\(label): the first band starts at pixel 0")
        for (a, b) in zip(starts, starts.dropFirst()) { XCTAssertEqual(b - a, p, "\(label): measured pitch") }
        XCTAssertEqual(starts.count, ((lines.isVertical ? w : h) + p - 1) / p, "\(label): one band per period")
        return darkIndices.count
    }

    /// Same-sign halves at most one representable step apart (bit patterns differ by at most 1).
    private static func scanlinesWithinOneHalfStep(_ a: [UInt16], _ b: [UInt16]) -> Bool {
        zip(a, b).allSatisfy { (x: UInt16, y: UInt16) -> Bool in
            (x & 0x8000) == (y & 0x8000) && (x > y ? x - y : y - x) <= 1
        }
    }

    private static func scanlinesDark(_ grey: Pixel, _ lines: Scanlines) -> [UInt16] {
        let f: Float = lines.factor
        return [Float16(grey.x * f).bitPattern, Float16(grey.y * f).bitPattern, Float16(grey.z * f).bitPattern,
                Float16(grey.w).bitPattern]
    }

    // MARK: - Disabled state is identity (FX-018-S1)

    func testScanlinesOffAndZeroIntensityAreBitIdentical() throws {
        let rig = try GPURig()
        let w = 37, h = 29
        let pixels: [Pixel] = Self.scanlinesRandom(width: w, height: h, seed: 18)
        let off = try scanlinesCompositor(rig, PixelsLayer(width: w, height: h, pixels: pixels), .off)
        let reference: [UInt16] = try scanlinesScene(rig, off, width: w, height: h)
        XCTAssertEqual(reference, Self.scanlinesHalves(pixels), "the stack result is the input picture itself")
        let outOff = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(off, into: outOff, time: Self.scanlinesTime + 16_666_667))
        let screen: [Pixel] = try rig.read(outOff)
        let cases: [Scanlines] = [Scanlines(isEnabled: true, intensity: 0),
                                  Scanlines(isEnabled: true, spacing: 2, thickness: 1, intensity: 0, isVertical: true),
                                  Scanlines(isEnabled: true, spacing: 16, thickness: 15, intensity: 0),
                                  Scanlines(isEnabled: false, spacing: 5, thickness: 2, intensity: 1)]
        for lines in cases {
            let c = try scanlinesCompositor(rig, PixelsLayer(width: w, height: h, pixels: pixels), lines)
            XCTAssertEqual(try scanlinesScene(rig, c, width: w, height: h), reference, "\(lines): bit for bit")
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.scanlinesTime + 16_666_667))
            XCTAssertEqual(try rig.read(out), screen, "\(lines): the screen output")
            XCTAssertEqual(c.scanlinesFrames, 0, "no pass runs")
            XCTAssertFalse(c.holdsScanlinesPicture, "no picture is held")
        }
    }

    func testScanlinesShaderRunAtZeroIntensityIsBitIdentical() throws {
        let rig = try GPURig()
        let w = 33, h = 21
        let pixels: [Pixel] = Self.scanlinesRandom(width: w, height: h, seed: 7)
        var withHDR: [Pixel] = pixels
        withHDR[0] = Pixel(60_000, 2_000, 1, 1)
        let input: [UInt16] = Self.scanlinesHalves(withHDR)
        let library = try CompositorShaders.library(device: rig.device, source: CompositorShaders.source + ScanlinesPass.source)
        let pass = try ScanlinesPass(device: rig.device, library: library,
                                     vertex: try CompositorShaders.function(library, "cmp_fullscreen"))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        let source = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            source.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: w * 8)
        }
        let pool = TexturePool(device: rig.device)
        for lines in [Scanlines(isEnabled: true, spacing: 2, thickness: 1, intensity: 0),
                      Scanlines(isEnabled: true, spacing: 16, thickness: 15, intensity: 0, isVertical: true)] {
            XCTAssertEqual(lines.block.factor, 1)
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let output = try XCTUnwrap(pass.encode(input: source, block: lines.block, pool: pool, fence: nil, commandBuffer: commands))
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertNil(commands.error)
            XCTAssertEqual(try scanlinesRead(rig, output), input, "\(lines): the shader at intensity 0 returns its input bit for bit")
        }
        XCTAssertEqual(pass.frames, 2, "the shader ran")
        pass.release(to: pool, after: nil)
    }

    // MARK: - Spacing is consistent in pixels (FX-018-S2)

    func testScanlinesEverySpacingDarkensExactlyThePredictedRowsAtEverySize() throws {
        let rig = try GPURig()
        let grey: Pixel = Self.scanlinesGrey
        let greyHalves: [UInt16] = Self.scanlinesHalves([grey])
        for (w, h) in [(37, 23), (61, 97), (129, 45)] {   // odd, portrait, landscape
            let c = try scanlinesCompositor(rig, SolidLayer("grey", color: grey), .off)
            var frame: UInt64 = 0
            for p in Scanlines.spacingRange {
                let t: Int = 1 + (p * 7) % (p - 1 == 0 ? 1 : p - 1)   // varied thickness in 1…p − 1
                for vertical in [false, true] {
                    let lines = Scanlines(isEnabled: true, spacing: p, thickness: t, intensity: 0.3, isVertical: vertical)
                    c.scanlines = lines
                    frame += 1
                    let out: [UInt16] = try scanlinesScene(rig, c, width: w, height: h, frame: frame)
                    let dark: [UInt16] = Self.scanlinesDark(grey, lines)
                    XCTAssertNotEqual(dark, greyHalves)
                    let label = "\(w)×\(h) spacing \(p) thickness \(t) \(vertical ? "vertical" : "horizontal")"
                    let count: Int = scanlinesCheckUniform(out, width: w, height: h, lines: lines, grey: greyHalves, dark: dark, label)
                    let extent: Int = vertical ? w : h
                    XCTAssertEqual(count, (0..<extent).filter { (i: Int) -> Bool in i % p < t }.count, label)
                }
            }
            XCTAssertEqual(c.scanlinesFrames, 30, "\(w)×\(h): one pass per frame")
        }
    }

    func testScanlinesSpacingIsConsistentAt4K() throws {
        let rig = try GPURig()
        let w = 3840, h = 2160
        let grey: Pixel = Self.scanlinesGrey
        let greyHalves: [UInt16] = Self.scanlinesHalves([grey])
        let c = try scanlinesCompositor(rig, SolidLayer("grey", color: grey), .off)
        var frame: UInt64 = 0
        for lines in [Scanlines(isEnabled: true, spacing: 2, thickness: 1, intensity: 1),
                      Scanlines(isEnabled: true, spacing: 3, thickness: 1, intensity: 0.5),
                      Scanlines(isEnabled: true, spacing: 16, thickness: 5, intensity: 0.8),
                      Scanlines(isEnabled: true, spacing: 3, thickness: 2, intensity: 0.5, isVertical: true)] {
            c.scanlines = lines
            frame += 1
            let out: [UInt16] = try scanlinesScene(rig, c, width: w, height: h, frame: frame)
            _ = scanlinesCheckUniform(out, width: w, height: h, lines: lines, grey: greyHalves,
                                      dark: Self.scanlinesDark(grey, lines), "4K \(lines)")
        }
    }

    // MARK: - Reference and finite output (FX-018-S3)

    func testScanlinesMatchesTheReferenceAndStaysFinite() throws {
        let rig = try GPURig()
        let w = 41, h = 23
        var pixels: [Pixel] = Self.scanlinesRandom(width: w, height: h, seed: 5)
        pixels[0] = Pixel(60_000, 2_000, 1, 1)   // HDR near the half-float limit, on a dark row
        pixels[w * h - 1] = Pixel(0, 0, 0, 0)
        let input: [Pixel] = Self.scanlinesFloats(Self.scanlinesHalves(pixels))
        for lines in [Scanlines(isEnabled: true, spacing: 5, thickness: 2, intensity: 0.85),
                      Scanlines(isEnabled: true, spacing: 4, thickness: 3, intensity: 0.37, isVertical: true)] {
            let c = try scanlinesCompositor(rig, PixelsLayer(width: w, height: h, pixels: pixels), lines)
            let out: [UInt16] = try scanlinesScene(rig, c, width: w, height: h)
            let expected: [UInt16] = Self.scanlinesHalves(lines.reference(input, width: w, height: h))
            let b: Scanlines.Block = lines.block
            for y in 0..<h {
                for x in 0..<w {
                    let i: Int = (y * w + x) * 4
                    let got = Array(out[i..<(i + 4)]), want = Array(expected[i..<(i + 4)])
                    if Scanlines.isDark(x: x, y: y, block: b) {
                        XCTAssertTrue(Self.scanlinesWithinOneHalfStep(got, want), "\(lines): (\(x), \(y)) = reference within one half step")
                    } else {
                        XCTAssertEqual(got, want, "\(lines): (\(x), \(y)) untouched, bit for bit")
                    }
                }
            }
            let floats: [Pixel] = Self.scanlinesFloats(out)
            for (i, p) in floats.enumerated() {
                for ch in 0..<4 {
                    XCTAssertTrue(p[ch].isFinite, "pixel \(i) finite")
                    XCTAssertLessThanOrEqual(p[ch], input[i][ch], "pixel \(i) never brighter")
                }
                XCTAssertEqual(p.w, input[i].w, "alpha kept")
            }
        }
    }

    // MARK: - Order, outputs and pool (FX-018-R1, R7, R11)

    func testScanlinesReachTheScreenFoldColorBeforeAndReturnThePicture() throws {
        let rig = try GPURig()
        let w = 32, h = 24
        let grey: Pixel = Self.scanlinesGrey
        let off = try scanlinesCompositor(rig, SolidLayer("grey", color: grey), .off)
        let offOut = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(off, into: offOut, time: Self.scanlinesTime))
        let offScreen: [Pixel] = try rig.read(offOut)
        let on = try scanlinesCompositor(rig, SolidLayer("grey", color: grey),
                                         Scanlines(isEnabled: true, spacing: 4, thickness: 2, intensity: 0.6))
        let onOut = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(on, into: onOut, time: Self.scanlinesTime))
        let onScreen: [Pixel] = try rig.read(onOut)
        for y in 0..<h {
            let row = Array(onScreen[(y * w)..<(y * w + w)]), offRow = Array(offScreen[(y * w)..<(y * w + w)])
            if y % 4 < 2 {
                XCTAssertTrue(zip(row, offRow).allSatisfy { (a: Pixel, b: Pixel) -> Bool in a.x < b.x }, "screen row \(y) darker")
            } else {
                XCTAssertEqual(row, offRow, "screen row \(y) unchanged")
            }
        }
        let pixels: [Pixel] = Self.scanlinesRandom(width: w, height: h, seed: 4)
        func render(_ order: OutputEffectOrder) throws -> Compositor {
            let c = try scanlinesCompositor(rig, PixelsLayer(width: w, height: h, pixels: pixels),
                                            Scanlines(isEnabled: true, intensity: 0.7))
            c.colorGrade = ColorGrade(saturation: 0.2)
            c.outputEffectOrder = order
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.scanlinesTime))
            return c
        }
        let standard = try render(.standard)
        XCTAssertEqual(standard.gradePassFrames, 1, "Color listed before the scanlines is applied before them")
        XCTAssertEqual(standard.scanlinesFrames, 1)
        let late = try render(OutputEffectOrder([.scanlines, .trails, .chromatic, .grade]))
        XCTAssertEqual(late.gradePassFrames, 0, "Color after the scanlines stays in the output pass")
        XCTAssertTrue(late.holdsScanlinesPicture)
        late.scanlines = .off
        XCTAssertFalse(late.holdsScanlinesPicture, "turning it off returns the picture")
    }
}
#endif
