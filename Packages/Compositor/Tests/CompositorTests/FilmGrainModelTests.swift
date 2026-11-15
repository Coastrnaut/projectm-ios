// FX-017-T03: the film grain model and CPU reference (FX-017-R2 to R6, R13, S3, S4): clamps, the PCG hash's fixed
// vectors, exact noise, grain cells, monochrome and colour channels, the grain clock (static, Reduce flashing, at most
// 24 steps a second, wrap), zero mean and the bound on a uniform grey, opacity 0 identity. Plain Swift (runs on Linux).
import Compositor
import XCTest

final class FilmGrainModelTests: XCTestCase {
    func testFilmGrainClampsAndRounds() {
        XCTAssertEqual(FilmGrain.clampOpacity(.nan), FilmGrain.defaultOpacity)
        XCTAssertEqual(FilmGrain.clampOpacity(-.infinity), 0)
        XCTAssertEqual(FilmGrain.clampOpacity(2), 1)
        XCTAssertEqual(FilmGrain.clampSize(0), 1)
        XCTAssertEqual(FilmGrain.clampSize(9), 3)
        XCTAssertEqual(FilmGrain.clampSeed(-4), 0)
        XCTAssertEqual(FilmGrain.clampSeed(123_456), 9_999)
        XCTAssertEqual(FilmGrain.size(fromNumber: 2.4), 2)
        XCTAssertEqual(FilmGrain.size(fromNumber: .nan), FilmGrain.defaultSize)
        XCTAssertEqual(FilmGrain.size(fromNumber: .infinity), 3)
        XCTAssertEqual(FilmGrain.seed(fromNumber: 41.6), 42)
        XCTAssertEqual(FilmGrain.seed(fromNumber: .nan), FilmGrain.defaultSeed)
        XCTAssertEqual(FilmGrain.seed(fromNumber: -.infinity), 0)
        let wild = FilmGrain(isEnabled: true, opacity: 7, size: -1, isColor: true, seed: 99_999, isAnimated: true).clamped
        XCTAssertEqual(wild, FilmGrain(isEnabled: true, opacity: 1, size: 1, isColor: true, seed: 9_999, isAnimated: true))
        XCTAssertEqual(FilmGrain.off, FilmGrain(isEnabled: false, opacity: 0.3, size: 1, isColor: false, seed: 1, isAnimated: false))
        XCTAssertFalse(FilmGrain(isEnabled: true, opacity: 0).isActive(width: 64, height: 64))
        XCTAssertFalse(FilmGrain(isEnabled: true).isActive(width: 1, height: 64))
        XCTAssertFalse(FilmGrain(isEnabled: false, opacity: 1).isActive(width: 64, height: 64))
        XCTAssertTrue(FilmGrain(isEnabled: true).isActive(width: 2, height: 2))
        XCTAssertEqual(FilmGrain(isEnabled: false, opacity: 1).block(frame: 0).scale, 0, "off: scale 0")
    }

    func testFilmGrainHashIsTheFixedPCGSequence() {
        // PCG hash (Jarzynski and Olano) vectors, computed independently of `FilmGrain.pcg`.
        func pcg(_ v: UInt32) -> UInt32 {
            let s: UInt64 = (UInt64(v) * 747_796_405 + 2_891_336_453) & 0xFFFF_FFFF
            let shift: UInt64 = (s >> 28) + 4
            let w: UInt64 = (((s >> shift) ^ s) * 277_803_737) & 0xFFFF_FFFF
            return UInt32((w >> 22) ^ w)
        }
        for v: UInt32 in [0, 1, 2, 7, 1_000, 0x7FFF_FFFF, 0xFFFF_FFFF] {
            XCTAssertEqual(FilmGrain.pcg(v), pcg(v), "pcg(\(v))")
        }
        XCTAssertEqual(FilmGrain.pcg(0), 129_708_002)
        let h = FilmGrain.hash(cellX: 3, cellY: 5, seed: 7, frame: 0, channel: 0)
        XCTAssertEqual(h, pcg(3 &+ pcg(5 &+ pcg(0 &+ pcg(28)))))
        XCTAssertEqual(h, FilmGrain.hash(cellX: 3, cellY: 5, seed: 7, frame: 0, channel: 0), "deterministic")
        XCTAssertNotEqual(h, FilmGrain.hash(cellX: 3, cellY: 5, seed: 8, frame: 0, channel: 0), "seed changes it")
        XCTAssertNotEqual(h, FilmGrain.hash(cellX: 3, cellY: 5, seed: 7, frame: 1, channel: 0), "frame changes it")
        XCTAssertNotEqual(h, FilmGrain.hash(cellX: 3, cellY: 5, seed: 7, frame: 0, channel: 1), "channel changes it")
        XCTAssertNotEqual(h, FilmGrain.hash(cellX: 5, cellY: 3, seed: 7, frame: 0, channel: 0), "not symmetric")
    }

    func testFilmGrainNoiseIsExactAndInRange() {
        XCTAssertEqual(FilmGrain.noise(0), -1)
        XCTAssertEqual(FilmGrain.noise(0xFFFF_FFFF), 1 - 0x1p-23)
        XCTAssertEqual(FilmGrain.noise(0x8000_0000), 0)
        for v: UInt32 in [1, 255, 256, 0x1234_5678, 0xDEAD_BEEF] {
            let n: Float = FilmGrain.noise(v)
            XCTAssertGreaterThanOrEqual(n, -1)
            XCTAssertLessThan(n, 1)
            XCTAssertEqual(Double(n), Double(v >> 8) / 8_388_608 - 1, "exact multiple of 2⁻²³")
        }
    }

    func testFilmGrainCellsAndChannels() {
        let mono2 = FilmGrain(isEnabled: true, size: 2, seed: 9).block(frame: 0)
        for (x, y) in [(0, 0), (4, 6), (10, 2)] {
            let n: Float = FilmGrain.noise(x: x, y: y, channel: 0, block: mono2)
            XCTAssertEqual(FilmGrain.noise(x: x + 1, y: y, channel: 0, block: mono2), n, "2 × 2 cell")
            XCTAssertEqual(FilmGrain.noise(x: x, y: y + 1, channel: 0, block: mono2), n)
            XCTAssertEqual(FilmGrain.noise(x: x + 1, y: y + 1, channel: 2, block: mono2), n, "monochrome: one value")
        }
        XCTAssertNotEqual(FilmGrain.noise(x: 0, y: 0, channel: 0, block: mono2), FilmGrain.noise(x: 2, y: 0, channel: 0, block: mono2))
        let colour = FilmGrain(isEnabled: true, size: 2, isColor: true, seed: 9).block(frame: 0)
        XCTAssertEqual(FilmGrain.noise(x: 4, y: 6, channel: 0, block: colour), FilmGrain.noise(x: 4, y: 6, channel: 0, block: mono2),
                       "colour red = monochrome")
        XCTAssertNotEqual(FilmGrain.noise(x: 4, y: 6, channel: 1, block: colour), FilmGrain.noise(x: 4, y: 6, channel: 0, block: colour))
    }

    func testFilmGrainClockIsStaticOrCappedAt24Hz() {
        let still = FilmGrain(isEnabled: true)
        let moving = FilmGrain(isEnabled: true, isAnimated: true)
        XCTAssertEqual(still.grainFrame(presentationTimeNanoseconds: 9_876_543_210, reduceFlashing: false), 0)
        XCTAssertEqual(moving.grainFrame(presentationTimeNanoseconds: 9_876_543_210, reduceFlashing: true), 0, "Reduce flashing: static")
        XCTAssertEqual(moving.effective(reduceMotion: true).grainFrame(presentationTimeNanoseconds: 9_876_543_210, reduceFlashing: false),
                       0, "Reduce Motion: static")
        XCTAssertTrue(moving.effective(reduceMotion: false).isAnimated)
        // One second at 120 Hz: at most 24 distinct steps, at least 23.
        var steps: Set<UInt32> = []
        var changes = 0
        var previous: UInt32?
        for i in 0..<120 {
            let t: UInt64 = 5_000_000_000 + UInt64(i) * 1_000_000_000 / 120
            let f: UInt32 = moving.grainFrame(presentationTimeNanoseconds: t, reduceFlashing: false)
            steps.insert(f)
            if let previous, previous != f { changes += 1 }
            previous = f
        }
        XCTAssertLessThanOrEqual(changes, 24, "at most 24 changes a second")
        XCTAssertGreaterThanOrEqual(steps.count, 23)
        let wrap: UInt64 = (UInt64(UInt32.max) + 1) * FilmGrain.framePeriodNanoseconds
        XCTAssertEqual(moving.grainFrame(presentationTimeNanoseconds: wrap, reduceFlashing: false), 0, "wraps at 2³²")
        XCTAssertEqual(moving.grainFrame(presentationTimeNanoseconds: wrap - 1, reduceFlashing: false), UInt32.max)
    }

    func testFilmGrainIsZeroMeanBoundedAndIdentityAtZeroOpacity() {
        let w = 96, h = 64
        let grey = SIMD4<Float>(0.5, 0.5, 0.5, 1)
        let input = [SIMD4<Float>](repeating: grey, count: w * h)
        for grain in [FilmGrain(isEnabled: true, opacity: 1, seed: 3), FilmGrain(isEnabled: true, opacity: 0.5, size: 3, isColor: true, seed: 77)] {
            let out = grain.reference(input, width: w, height: h, frame: 0)
            var sum = SIMD4<Float>(0, 0, 0, 0)
            let bound: Float = grain.scale
            for p in out {
                sum += p - grey
                for ch in 0..<3 { XCTAssertLessThanOrEqual(Swift.abs(p[ch] - 0.5), bound + 1e-7) }
                XCTAssertEqual(p.w, 1, "alpha kept")
                if !grain.isColor { XCTAssertEqual(p.x, p.y); XCTAssertEqual(p.y, p.z) }
            }
            for ch in 0..<3 { XCTAssertLessThan(Swift.abs(sum[ch] / Float(w * h)), 0.005, "\(grain): mean within 0.5 %") }
            XCTAssertNotEqual(out, input)
        }
        let transparent = SIMD4<Float>(0, 0, 0, 0)
        XCTAssertEqual(FilmGrain.referencePixel(transparent, x: 3, y: 3, block: FilmGrain(isEnabled: true, opacity: 1).block(frame: 0)),
                       transparent, "alpha 0 unchanged")
        let black = SIMD4<Float>(0, 0, 0, 1)
        for x in 0..<32 {
            let p = FilmGrain.referencePixel(black, x: x, y: 0, block: FilmGrain(isEnabled: true, opacity: 1).block(frame: 0))
            XCTAssertGreaterThanOrEqual(p.x, 0, "never below zero")
        }
        let zero = FilmGrain(isEnabled: true, opacity: 0, size: 2, isColor: true, seed: 5, isAnimated: true)
        let odd: [SIMD4<Float>] = [SIMD4(-0.25, 3, .infinity, 0.5), SIMD4(0.1, 0.2, 0.3, 1)]
        XCTAssertEqual(FilmGrain.referencePixel(odd[0], x: 1, y: 1, block: zero.block(frame: 9)), odd[0], "scale 0: the input")
        XCTAssertEqual(zero.reference(odd, width: 2, height: 1, frame: 9), odd)
    }
}
