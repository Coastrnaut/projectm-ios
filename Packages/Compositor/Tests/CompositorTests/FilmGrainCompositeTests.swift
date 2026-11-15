// FX-017-T07: film grain through the real Metal compositor (FX-017-S1 to S4) — the shader unit test. The roadmap
// acceptance "Fixed seed produces stable snapshots and opacity zero is identity": off and opacity 0 (several seeds,
// sizes, colour, temporal) are bit-identical on random content with no pass, and the pass run directly at opacity 0
// returns its input bit for bit; the GPU's integer hash and noise equal the CPU exactly (a test kernel compiled with the
// compositor's own library function and safe math); the output equals the reference within one half-float step; a fixed
// seed with static grain renders identically twice and at other frame times; seeds differ; temporal grain changes per
// 1⁄24 s step only, and Reduce flashing keeps it static; a uniform grey keeps its mean, the bound holds, all finite;
// order and pool. Small frames. Skipped without Metal. `PixelsLayer` comes from `ChromaticSplitCompositeTests`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import XCTest

final class FilmGrainCompositeTests: XCTestCase {
    private static let grainTime: UInt64 = 1_000_000_000

    private static func grainQ(_ k: Int) -> Float { Float(k) / 1024 }

    /// Seeded random premultiplied content (colour ≤ alpha), half-exact.
    private static func grainRandom(width: Int, height: Int, seed: UInt64) -> [Pixel] {
        var state: UInt64 = seed
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        return (0..<(width * height)).map { (_: Int) -> Pixel in
            let a: Int = 256 + next(769)
            return Pixel(grainQ(next(a + 1)), grainQ(next(a + 1)), grainQ(next(a + 1)), grainQ(a))
        }
    }

    private func grainCompositor(_ rig: GPURig, _ pixels: [Pixel], width: Int, height: Int, grain: FilmGrain) throws -> Compositor {
        let c = try Compositor(device: rig.device, layers: [PixelsLayer(width: width, height: height, pixels: pixels)])
        c.filmGrain = grain
        return c
    }

    /// The stack phase plus output effects (`encodeScene`) at `time`, as floats read from the halves.
    private func grainScene(_ rig: GPURig, _ c: Compositor, width: Int, height: Int, time: UInt64 = grainTime,
                            reduceFlashing: Bool = false) throws -> [Pixel] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let shown = try XCTUnwrap(c.encodeScene(width: width, height: height, commandBuffer: commands,
                                                presentationTimeNanoseconds: time, contentScale: 2,
                                                reduceFlashing: reduceFlashing, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        return try rig.read(shown)
    }

    private static func grainHalfRounded(_ pixels: [Pixel]) -> [Pixel] {
        pixels.map { (p: Pixel) -> Pixel in
            Pixel(Float(Float16(p.x)), Float(Float16(p.y)), Float(Float16(p.z)), Float(Float16(p.w)))
        }
    }

    // MARK: - Opacity zero is identity (FX-017-S1)

    func testFilmGrainOffAndZeroOpacityAreBitIdenticalWithNoPass() throws {
        let rig = try GPURig()
        let w = 37, h = 29
        let pixels: [Pixel] = Self.grainRandom(width: w, height: h, seed: 17)
        let off = try grainCompositor(rig, pixels, width: w, height: h, grain: .off)
        let reference: [Pixel] = try grainScene(rig, off, width: w, height: h)
        XCTAssertEqual(reference, Self.grainHalfRounded(pixels), "the stack result is the input picture itself")
        let outOff = try rig.output(.rgba16Float, width: w, height: h)
        XCTAssertTrue(try rig.frame(off, into: outOff, time: Self.grainTime))
        let screen: [Pixel] = try rig.read(outOff)
        let cases: [FilmGrain] = [FilmGrain(isEnabled: true, opacity: 0),
                                  FilmGrain(isEnabled: true, opacity: 0, size: 3, isColor: true, seed: 9_999, isAnimated: true),
                                  FilmGrain(isEnabled: true, opacity: 0, size: 2, seed: 0),
                                  FilmGrain(isEnabled: false, opacity: 1, isColor: true, isAnimated: true)]
        for g in cases {
            let c = try grainCompositor(rig, pixels, width: w, height: h, grain: g)
            XCTAssertEqual(try grainScene(rig, c, width: w, height: h, time: Self.grainTime + 123_456_789), reference, "\(g): bit for bit")
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.grainTime))
            XCTAssertEqual(try rig.read(out), screen, "\(g): the screen output")
            XCTAssertEqual(c.filmGrainFrames, 0, "no pass runs")
            XCTAssertFalse(c.holdsFilmGrainPicture, "no picture is held")
        }
    }

    func testFilmGrainPassAtZeroOpacityReturnsItsInputBitForBit() throws {
        let rig = try GPURig()
        let library = try CompositorShaders.library(device: rig.device, source: CompositorShaders.source + FilmGrainPass.source)
        let pass = try FilmGrainPass(device: rig.device, library: library,
                                     vertex: try CompositorShaders.function(library, "cmp_fullscreen"))
        let pool = TexturePool(device: rig.device)
        for (w, h) in [(37, 29), (2, 2), (3, 64)] {
            var pixels: [Pixel] = Self.grainRandom(width: w, height: h, seed: UInt64(w * h))
            pixels[0] = Pixel(-0.25, 60_000, 0, 0.5)   // negative and HDR values pass unchanged too
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
            d.usage = [.shaderRead]
            d.storageMode = .shared
            let input = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
            var halves: [UInt16] = []
            for p in pixels { halves += [Float16(p.x).bitPattern, Float16(p.y).bitPattern, Float16(p.z).bitPattern, Float16(p.w).bitPattern] }
            halves.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
                input.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: w * 8)
            }
            let block = FilmGrain(isEnabled: true, opacity: 0, size: 2, isColor: true, seed: 5, isAnimated: true).block(frame: 77)
            XCTAssertEqual(block.scale, 0)
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let output = try XCTUnwrap(pass.encode(input: input, block: block, pool: pool, fence: nil, commandBuffer: commands))
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertEqual(try rig.read(output), try rig.read(input), "\(w) × \(h): the input bit for bit")
            pass.release(to: pool, after: commands)
        }
    }

    // MARK: - The GPU hash is the CPU hash (FX-017-R13)

    func testFilmGrainGPUHashAndNoiseEqualTheCPUExactly() throws {
        let rig = try GPURig()
        let kernel = """

        kernel void test_film_grain_hash(device uint *hashes [[buffer(0)]], device float *noises [[buffer(1)]],
                                         constant uint4 &p [[buffer(2)]], uint i [[thread_position_in_grid]]) {
            uint h = cmp_grain_hash(i % 32u * p.w, i / 32u * 977u, p.x, p.y, p.z);
            hashes[i] = h;
            noises[i] = cmp_grain_noise(h);
        }
        """
        let library = try CompositorShaders.library(device: rig.device, source: CompositorShaders.source + FilmGrainPass.source + kernel)
        let function = try CompositorShaders.function(library, "test_film_grain_hash")
        let pipeline = try rig.device.makeComputePipelineState(function: function)
        let count = 1_024
        for params: SIMD4<UInt32> in [SIMD4(1, 0, 0, 1), SIMD4(9_999, 0xFFFF_FFFF, 2, 131_071), SIMD4(0, 12_345, 1, 7)] {
            let hashes = try XCTUnwrap(rig.device.makeBuffer(length: count * 4, options: .storageModeShared))
            let noises = try XCTUnwrap(rig.device.makeBuffer(length: count * 4, options: .storageModeShared))
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(commands.makeComputeCommandEncoder())
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(hashes, offset: 0, index: 0)
            encoder.setBuffer(noises, offset: 0, index: 1)
            var p: SIMD4<UInt32> = params
            encoder.setBytes(&p, length: MemoryLayout<SIMD4<UInt32>>.stride, index: 2)
            encoder.dispatchThreadgroups(MTLSize(width: count / 64, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertNil(commands.error)
            let h = hashes.contents().bindMemory(to: UInt32.self, capacity: count)
            let n = noises.contents().bindMemory(to: Float.self, capacity: count)
            var mismatches = 0
            for i in 0..<count {
                let cx = UInt32(i % 32) &* params.w, cy = UInt32(i / 32) &* 977
                let cpu: UInt32 = FilmGrain.hash(cellX: cx, cellY: cy, seed: params.x, frame: params.y, channel: params.z)
                if h[i] != cpu || n[i].bitPattern != FilmGrain.noise(cpu).bitPattern { mismatches += 1 }
            }
            XCTAssertEqual(mismatches, 0, "\(params): GPU hash and noise equal the CPU bit for bit")
        }
    }

    // MARK: - Reference, stable snapshots, seeds (FX-017-S2, S3, S4)

    func testFilmGrainMatchesTheReferenceAndIsStableForAFixedSeed() throws {
        let rig = try GPURig()
        let w = 41, h = 23
        var pixels: [Pixel] = Self.grainRandom(width: w, height: h, seed: 5)
        pixels[0] = Pixel(60_000, 2_000, 1, 1)   // HDR near the half-float limit
        pixels[w * h - 1] = Pixel(0, 0, 0, 0)
        let input: [Pixel] = Self.grainHalfRounded(pixels)
        for g in [FilmGrain(isEnabled: true, opacity: 1, seed: 1), FilmGrain(isEnabled: true, opacity: 0.6, size: 2, isColor: true, seed: 7)] {
            let c = try grainCompositor(rig, pixels, width: w, height: h, grain: g)
            let out: [Pixel] = try grainScene(rig, c, width: w, height: h)
            XCTAssertEqual(c.filmGrainFrames, 1, "the pass ran")
            XCTAssertEqual(c.lastFilmGrainFrame, 0, "static grain")
            let expected: [Pixel] = g.reference(input, width: w, height: h, frame: 0)
            var worst: Float = 0
            for i in 0..<(w * h) {
                for ch in 0..<4 {
                    XCTAssertTrue(out[i][ch].isFinite, "pixel \(i) finite")
                    let step: Float = Swift.max(Swift.abs(expected[i][ch]) / 1024, 0x1p-24)   // one half-float step
                    worst = Swift.max(worst, Swift.abs(out[i][ch] - expected[i][ch]) - step)
                }
                XCTAssertEqual(out[i].w, input[i].w, "alpha kept")
            }
            XCTAssertLessThanOrEqual(worst, 0, "\(g): GPU = reference within one half-float step")
            XCTAssertEqual(out[w * h - 1], Pixel(0, 0, 0, 0), "transparent pixel unchanged")
            // Stable snapshots: a fresh compositor, and later frame times, give the same pixels.
            let again = try grainCompositor(rig, pixels, width: w, height: h, grain: g)
            XCTAssertEqual(try grainScene(rig, again, width: w, height: h), out, "two renders bit-identical")
            XCTAssertEqual(try grainScene(rig, again, width: w, height: h, time: Self.grainTime + 777_000_000), out,
                           "static grain does not change with time")
        }
        let one = try grainCompositor(rig, pixels, width: w, height: h, grain: FilmGrain(isEnabled: true, opacity: 1, seed: 1))
        let two = try grainCompositor(rig, pixels, width: w, height: h, grain: FilmGrain(isEnabled: true, opacity: 1, seed: 2))
        XCTAssertNotEqual(try grainScene(rig, one, width: w, height: h), try grainScene(rig, two, width: w, height: h), "seeds differ")
    }

    func testFilmGrainTemporalStepsChangeOnlyPerStepAndReduceFlashingKeepsItStatic() throws {
        let rig = try GPURig()
        let w = 32, h = 24
        let pixels = [Pixel](repeating: Pixel(0.5, 0.5, 0.5, 1), count: w * h)
        let g = FilmGrain(isEnabled: true, opacity: 1, seed: 3, isAnimated: true)
        let c = try grainCompositor(rig, pixels, width: w, height: h, grain: g)
        let period: UInt64 = FilmGrain.framePeriodNanoseconds
        let t0: UInt64 = 100 * period
        let first: [Pixel] = try grainScene(rig, c, width: w, height: h, time: t0)
        XCTAssertEqual(c.lastFilmGrainFrame, 100)
        XCTAssertEqual(try grainScene(rig, c, width: w, height: h, time: t0 + period / 2), first, "same 1⁄24 s step: identical")
        XCTAssertEqual(try grainScene(rig, c, width: w, height: h, time: t0), first, "same (seed, step): identical")
        let next: [Pixel] = try grainScene(rig, c, width: w, height: h, time: t0 + period)
        XCTAssertEqual(c.lastFilmGrainFrame, 101)
        XCTAssertNotEqual(next, first, "the next step differs")
        let fresh = try grainCompositor(rig, pixels, width: w, height: h, grain: g)
        XCTAssertEqual(try grainScene(rig, fresh, width: w, height: h, time: t0 + period), next, "stateless: another compositor agrees")
        let still = try grainCompositor(rig, pixels, width: w, height: h, grain: FilmGrain(isEnabled: true, opacity: 1, seed: 3))
        let staticPicture: [Pixel] = try grainScene(rig, still, width: w, height: h, time: t0)
        for t in [t0, t0 + period, t0 + 5 * period] {
            XCTAssertEqual(try grainScene(rig, c, width: w, height: h, time: t, reduceFlashing: true), staticPicture,
                           "Reduce flashing: the static grain")
            XCTAssertEqual(c.lastFilmGrainFrame, 0)
        }
    }

    func testFilmGrainKeepsTheMeanOfAUniformGreyWithinTheBound() throws {
        let rig = try GPURig()
        let w = 96, h = 64
        let grey = Pixel(0.5, 0.5, 0.5, 1)
        for g in [FilmGrain(isEnabled: true, opacity: 1, seed: 11), FilmGrain(isEnabled: true, opacity: 1, size: 3, isColor: true, seed: 12)] {
            let c = try grainCompositor(rig, [Pixel](repeating: grey, count: w * h), width: w, height: h, grain: g)
            let out: [Pixel] = try grainScene(rig, c, width: w, height: h)
            var sum = Pixel(0, 0, 0, 0)
            for p in out {
                sum += p - grey
                for ch in 0..<3 {
                    XCTAssertTrue(p[ch].isFinite)
                    XCTAssertLessThanOrEqual(Swift.abs(p[ch] - 0.5), FilmGrain.amplitude + 0x1p-10, "bound held")
                }
                if !g.isColor { XCTAssertEqual(p.x, p.y); XCTAssertEqual(p.y, p.z) }
            }
            for ch in 0..<3 { XCTAssertLessThan(Swift.abs(sum[ch] / Float(w * h)), 0.005, "\(g): no brightness drift") }
            XCTAssertGreaterThan(out.filter { (p: Pixel) -> Bool in p != grey }.count, w * h / 2, "grain is visible")
        }
    }

    // MARK: - Order and pool (FX-017-R8, R12)

    func testFilmGrainIsLastFoldsColorBeforeItAndReturnsThePicture() throws {
        let rig = try GPURig()
        XCTAssertEqual(OutputEffectOrder.standard.effects.last, .filmGrain)
        let w = 32, h = 24
        let pixels: [Pixel] = Self.grainRandom(width: w, height: h, seed: 4)
        func render(_ order: OutputEffectOrder) throws -> Compositor {
            let c = try grainCompositor(rig, pixels, width: w, height: h, grain: FilmGrain(isEnabled: true, opacity: 0.7))
            c.colorGrade = ColorGrade(saturation: 0.2)
            c.outputEffectOrder = order
            let out = try rig.output(.rgba16Float, width: w, height: h)
            XCTAssertTrue(try rig.frame(c, into: out, time: Self.grainTime))
            return c
        }
        let standard = try render(.standard)
        XCTAssertEqual(standard.gradePassFrames, 1, "Color listed before the grain is applied before it")
        XCTAssertEqual(standard.filmGrainFrames, 1)
        let late = try render(OutputEffectOrder([.filmGrain, .trails, .chromatic, .grade]))
        XCTAssertEqual(late.gradePassFrames, 0, "Color after the grain stays in the output pass")
        XCTAssertTrue(late.holdsFilmGrainPicture)
        late.filmGrain = .off
        XCTAssertFalse(late.holdsFilmGrainPicture, "turning it off returns the picture")
    }
}
#endif
