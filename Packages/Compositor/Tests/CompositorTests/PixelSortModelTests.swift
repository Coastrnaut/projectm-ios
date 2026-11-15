// FX-011-T03: the pixel sort model (plain Swift, also on Linux): clamping and span snapping, the frame budget plan over
// frame sizes up to 16384 × 16384 and every span (FX-011-R6, S2: workload ≤ B, the largest admissible span, a skip
// exactly when span 4 does not fit), and the CPU reference (FX-011-R3, R4, S1, S4: segments non-decreasing, other pixels
// unchanged, each tile a permutation, two thresholds give different orderings).
import Compositor
import XCTest

final class PixelSortModelTests: XCTestCase {
    private static func gray(_ v: Float) -> SIMD4<Float> { SIMD4<Float>(v, v, v, 1) }

    /// Seeded gray picture on a 1⁄64 grid (half-exact, luminances well apart).
    static func grayPicture(width: Int, height: Int, seed: UInt64) -> [SIMD4<Float>] {
        var state: UInt64 = seed
        return (0..<(width * height)).map { (_: Int) -> SIMD4<Float> in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return gray(Float((state >> 33) % 65) / 64)
        }
    }

    func testValuesAreClampedAndSpansSnapped() {
        XCTAssertEqual(PixelSort.off.isEnabled, false)
        XCTAssertEqual(PixelSort.clampThreshold(.nan), 0.5)
        XCTAssertEqual(PixelSort.clampThreshold(-3), 0)
        XCTAssertEqual(PixelSort.clampThreshold(.infinity), 1)
        XCTAssertEqual(PixelSort.snapSpan(0), 4)
        XCTAssertEqual(PixelSort.snapSpan(4), 4)
        XCTAssertEqual(PixelSort.snapSpan(31), 16)
        XCTAssertEqual(PixelSort.snapSpan(1000), 64)
        XCTAssertEqual(PixelSort.snapSpan(Double.nan), 32)
        XCTAssertEqual(PixelSort.snapSpan(Double.infinity), 64)
        XCTAssertEqual(PixelSort.snapSpan(40.9), 32)
        let c: PixelSort = PixelSort(isEnabled: true, threshold: 7, span: 9, direction: .vertical).clamped
        XCTAssertEqual(c, PixelSort(isEnabled: true, threshold: 1, span: 8, direction: .vertical))
        XCTAssertEqual(PixelSort.frameBudget, 7680 * 4320 * 4)
        XCTAssertEqual(PixelSort.frameBudget, 3840 * 2160 * 16)
    }

    // MARK: - Worst-case frame budget (FX-011-R6, S2)

    func testThePlanNeverExceedsTheBudgetAtAnySizeOrSpan() {
        var sides: [Int] = [1, 2, 3, 63, 64, 65, 720, 1080, 1179, 1290, 1920, 2160, 2556, 2796, 3840, 4320, 6016, 7680, 16384]
        var s = 5
        while s < 16384 { sides.append(s); s = s * 3 / 2 + 1 }
        let budget: Int = PixelSort.frameBudget
        var ran = 0, skipped = 0
        for w in sides {
            for h in sides {
                for span in PixelSort.spans {
                    for direction in PixelSort.Direction.allCases {
                        let p: PixelSort.Plan = PixelSort(isEnabled: true, span: span, direction: direction)
                            .plan(width: w, height: h)
                        let along: Int = direction == .horizontal ? w : h
                        guard along >= 2 else {
                            XCTAssertEqual(p, .none, "\(w) × \(h): too small along the direction")
                            continue
                        }
                        XCTAssertLessThanOrEqual(p.workload, budget, "\(w) × \(h) span \(span)")
                        if p.runs {
                            ran += 1
                            XCTAssertTrue(PixelSort.spans.contains(p.effectiveSpan))
                            XCTAssertLessThanOrEqual(p.effectiveSpan, span)
                            XCTAssertEqual(p.workload, w * h * p.effectiveSpan)
                            let larger: [Int] = PixelSort.spans.filter { $0 > p.effectiveSpan && $0 <= span }
                            for l in larger { XCTAssertGreaterThan(w * h * l, budget, "\(l) would fit: not the largest") }
                        } else {
                            skipped += 1
                            XCTAssertTrue(p.budgetSkipped)
                            XCTAssertGreaterThan(w * h * 4, budget, "\(w) × \(h): skipped only when span 4 does not fit")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(ran, 0)
        XCTAssertGreaterThan(skipped, 0, "the largest frames are skipped")
    }

    func testCommonDisplaysUseTheExpectedSpan() {
        let sort = PixelSort(isEnabled: true, span: 64)
        XCTAssertEqual(sort.plan(width: 1920, height: 1080).effectiveSpan, 64)
        XCTAssertEqual(sort.plan(width: 1290, height: 2796).effectiveSpan, 32)
        XCTAssertEqual(sort.plan(width: 3840, height: 2160).effectiveSpan, 16)
        XCTAssertEqual(sort.plan(width: 7680, height: 4320).effectiveSpan, 4, "the largest external output fits at span 4")
        XCTAssertTrue(sort.plan(width: 7681, height: 4320).budgetSkipped)
        XCTAssertTrue(sort.plan(width: 16384, height: 16384).budgetSkipped)
        XCTAssertEqual(PixelSort.off.plan(width: 64, height: 64), .none, "off: no pass")
        XCTAssertFalse(PixelSort(isEnabled: true, direction: .vertical).isActive(width: 64, height: 1))
        XCTAssertTrue(PixelSort(isEnabled: true, direction: .horizontal).isActive(width: 64, height: 1))
        XCTAssertEqual(PixelSort(isEnabled: true).block(effectiveSpan: 16),
                       PixelSort.Block(threshold: 0.5, span: 16, vertical: 0, pad: 0))
        XCTAssertEqual(MemoryLayout<PixelSort.Block>.stride, 16)
    }

    // MARK: - CPU reference (FX-011-R3, R4, S1, S4)

    func testReferenceSortsSegmentsAndLeavesOtherPixels() {
        let line: [SIMD4<Float>] = [0.9, 0.1, 0.7, 0.6, 0.8, 0.2, 0.95, 0.55].map(Self.gray)
        let sorted: [SIMD4<Float>] = PixelSort.referenceLine(line, span: 8, threshold: 0.5)
        XCTAssertEqual(sorted.map(\.x), [0.9, 0.1, 0.6, 0.7, 0.8, 0.2, 0.55, 0.95])
        let tiled: [SIMD4<Float>] = PixelSort.referenceLine(line, span: 4, threshold: 0.5)
        XCTAssertEqual(tiled.map(\.x), [0.9, 0.1, 0.6, 0.7, 0.8, 0.2, 0.55, 0.95], "runs end at the tile edge")
        let all: [SIMD4<Float>] = PixelSort.referenceLine(line, span: 4, threshold: 0)
        XCTAssertEqual(all.map(\.x), [0.1, 0.6, 0.7, 0.9, 0.2, 0.55, 0.8, 0.95], "each tile sorted on its own")
        var nonFinite: [SIMD4<Float>] = line
        nonFinite[3] = SIMD4<Float>(.nan, 0, 0, 1)
        let kept: [SIMD4<Float>] = PixelSort.referenceLine(nonFinite, span: 8, threshold: 0.5)
        XCTAssertTrue(kept[3].x.isNaN, "a non-finite pixel never qualifies and stays")
        let stable: [SIMD4<Float>] = PixelSort.referenceLine([SIMD4<Float>(0.6, 0.6, 0.6, 1), SIMD4<Float>(0.6, 0.6, 0.6, 0.5)],
                                                              span: 4, threshold: 0.5)
        XCTAssertEqual(stable.map(\.w), [1, 0.5], "equal luminance keeps the original order")
    }

    func testThresholdChangesTheOrdering() {
        let w = 37, h = 13
        let input: [SIMD4<Float>] = Self.grayPicture(width: w, height: h, seed: 11)
        for direction in PixelSort.Direction.allCases {
            let high: [SIMD4<Float>] = PixelSort(isEnabled: true, threshold: 0.5, span: 8, direction: direction)
                .reference(input, width: w, height: h)
            let low: [SIMD4<Float>] = PixelSort(isEnabled: true, threshold: 0.2, span: 8, direction: direction)
                .reference(input, width: w, height: h)
            XCTAssertNotEqual(high, low, "\(direction): two thresholds, two orderings")
            XCTAssertNotEqual(high, input, "\(direction): something moved")
            Self.assertSorted(input: input, output: high, width: w, height: h, span: 8, threshold: 0.5, direction: direction)
            Self.assertSorted(input: input, output: low, width: w, height: h, span: 8, threshold: 0.2, direction: direction)
        }
    }

    /// Every segment non-decreasing in luminance, every other pixel unchanged, every tile a permutation of its input.
    static func assertSorted(input: [SIMD4<Float>], output: [SIMD4<Float>], width: Int, height: Int, span: Int,
                             threshold: Float, direction: PixelSort.Direction, file: StaticString = #filePath,
                             line: UInt = #line) {
        let lines: Int = direction == .horizontal ? height : width
        let length: Int = direction == .horizontal ? width : height
        func at(_ l: Int, _ k: Int) -> Int { direction == .horizontal ? l * width + k : k * width + l }
        for l in 0..<lines {
            var tile = 0
            while tile < length {
                let end: Int = min(tile + span, length)
                var before: [[Float]] = [], after: [[Float]] = []
                for k in tile..<end {
                    let i: Int = at(l, k)
                    before.append([input[i].x, input[i].y, input[i].z, input[i].w])
                    after.append([output[i].x, output[i].y, output[i].z, output[i].w])
                    if !PixelSort.qualifies(input[i], threshold: threshold) {
                        XCTAssertEqual(output[i], input[i], "a pixel outside every segment is untouched", file: file, line: line)
                    } else if k > tile && PixelSort.qualifies(input[at(l, k - 1)], threshold: threshold) {
                        XCTAssertLessThanOrEqual(PixelSort.luminance(output[at(l, k - 1)]), PixelSort.luminance(output[i]),
                                                 "segment non-decreasing", file: file, line: line)
                    }
                }
                let key: ([Float], [Float]) -> Bool = { (a: [Float], b: [Float]) -> Bool in a.lexicographicallyPrecedes(b) }
                XCTAssertEqual(before.sorted(by: key), after.sorted(by: key), "a tile is a permutation", file: file, line: line)
                tile = end
            }
        }
    }
}
