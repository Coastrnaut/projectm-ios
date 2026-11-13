// BloomPlanTests.swift — FX-001-T04: the bloom's downsample factor, tap radius, weights and halo
// extent for an output size (FX-001-R7 a, R15; research FX-001-D3 steps 2-3). Runs on Linux.
import XCTest
@testable import VisualEffects

final class BloomPlanTests: XCTestCase {
    private let sizes = [(1179, 2556), (2556, 1179), (2064, 2752), (256, 256), (97, 61), (1, 1)]
    private let radii: [Float] = [0.005, 0.02, 0.04, 0.06]

    /// The rule of research FX-001-D3, recomputed in Double.
    private func expected(radius: Float, width: Int, height: Int) -> (d: Int, r: Int) {
        let px = Double(radius) * Double(min(width, height))
        let d = [2, 4, 8].first { Int((px / Double($0)).rounded(.up)) <= 16 } ?? 8
        let r = min(max(Int((px / Double(d)).rounded()), 1), 16)
        return (d, r)
    }

    func testFactorRadiusSizesAndExtent() {
        var table: [String] = []
        for (w, h) in sizes {
            for radius in radii {
                let plan = BloomPlan(parameters: BloomParameters(enabled: true, radius: radius), width: w, height: h)
                let e = expected(radius: radius, width: w, height: h)
                XCTAssertEqual(plan.downsample, e.d, "\(w)×\(h) ρ=\(radius)")
                XCTAssertEqual(plan.blurRadius, e.r, "\(w)×\(h) ρ=\(radius)")
                XCTAssertLessThanOrEqual(plan.blurRadius, BloomPlan.maxTapsPerSide)
                XCTAssertEqual(plan.reducedWidth, (w + e.d - 1) / e.d)
                XCTAssertEqual(plan.reducedHeight, (h + e.d - 1) / e.d)
                XCTAssertEqual(plan.haloExtent, (e.r + 2) * e.d)
                table.append("\(w)x\(h) radius=\(radius): D=\(plan.downsample) R=\(plan.blurRadius) E=\(plan.haloExtent)px reduced=\(plan.reducedWidth)x\(plan.reducedHeight)")
            }
        }
        print("FX-001 plan:\n" + table.joined(separator: "\n"))
    }

    func testWeightsAreNormalizedPositiveAndDecreasing() {
        for r in 1...16 {
            // Pick a size that gives blur radius r at D = 2: ρ·min/2 = r → min = 2r/ρ with ρ = 0.06.
            let side = Int((Double(2 * r) / 0.06).rounded())
            let plan = BloomPlan(parameters: BloomParameters(enabled: true, radius: 0.06), width: side, height: side)
            let w = plan.weights
            XCTAssertEqual(w.count, plan.blurRadius + 1)
            let sum = w[0] + 2 * w.dropFirst().reduce(0, +)
            XCTAssertEqual(sum, 1, accuracy: 1e-6)
            for i in 0..<w.count { XCTAssertGreaterThan(w[i], 0) }
            for i in 1..<w.count { XCTAssertLessThan(w[i], w[i - 1]) }
        }
    }

    func testPlansAreDeterministicAndSizeClamped() {
        let p = BloomParameters(enabled: true, radius: 0.03)
        XCTAssertEqual(BloomPlan(parameters: p, width: 800, height: 600), BloomPlan(parameters: p, width: 800, height: 600))
        let tiny = BloomPlan(parameters: p, width: 0, height: -4)
        XCTAssertEqual(tiny.width, 1); XCTAssertEqual(tiny.height, 1)
        XCTAssertEqual(tiny.reducedWidth, 1); XCTAssertEqual(tiny.reducedHeight, 1)
        XCTAssertEqual(tiny.blurRadius, 1)
    }

    func testLargestScreensStayWithinTheTapBudget() {
        // iPad Pro 13" at full scale: 0.06 · 2064 = 123.8 px → D = 8, R = 15 (≤ 16).
        let plan = BloomPlan(parameters: BloomParameters(enabled: true, radius: 0.06), width: 2064, height: 2752)
        XCTAssertEqual(plan.downsample, 8)
        XCTAssertEqual(plan.blurRadius, 15)
    }
}
