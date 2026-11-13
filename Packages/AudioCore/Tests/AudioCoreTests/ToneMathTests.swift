// ToneMathTests.swift — accuracy of the generator's own sine, exponential and logarithm
// (AUD-016-T02; research AUD-016-D1). These are tolerance tests against Foundation; determinism
// is tested by the golden hashes (ReferenceToneCatalogTests), never here.
import Foundation
import XCTest
@testable import AudioCore

final class ToneMathTests: XCTestCase {
    private func ulp(_ value: Double) -> Double { value.ulp }

    func testSineMatchesFoundationOverOneCycle() {
        let count = 100_003
        var worst = 0.0
        for i in 0..<count {
            let c = Double(i) / Double(count)
            let difference = abs(ToneMath.sin2pi(c) - sin(2 * Double.pi * c))
            worst = max(worst, difference)
        }
        XCTAssertLessThanOrEqual(worst, 2e-15, "largest difference from Foundation sin")
    }

    func testSineIsExactAtTheQuarterPoints() {
        XCTAssertEqual(ToneMath.sin2pi(0), 0)
        XCTAssertEqual(ToneMath.sin2pi(0.25), 1)
        XCTAssertEqual(ToneMath.sin2pi(0.5), 0)
        XCTAssertEqual(ToneMath.sin2pi(0.75), -1)
        // Whole cycles are reduced first: 3.25 cycles is a quarter cycle.
        XCTAssertEqual(ToneMath.sin2pi(3.25), 1)
    }

    func testSineIsOddAndPeriodic() {
        for c in stride(from: 0.0, to: 1.0, by: 0.0371) {
            XCTAssertEqual(ToneMath.sin2pi(c + 1), ToneMath.sin2pi(c), accuracy: 1e-15)
            XCTAssertEqual(ToneMath.sin2pi(1 - c), -ToneMath.sin2pi(c), accuracy: 2e-15)
        }
    }

    func testExpMatchesFoundation() {
        var worstUlps = 0.0
        for i in 0...40_000 {
            let x = -20 + Double(i) * 0.001
            let reference = exp(x)
            worstUlps = max(worstUlps, abs(ToneMath.exp(x) - reference) / ulp(reference))
        }
        XCTAssertLessThanOrEqual(worstUlps, 4, "largest difference from Foundation exp, in ulp")
        XCTAssertEqual(ToneMath.exp(0), 1)
    }

    func testExpLimits() {
        XCTAssertEqual(ToneMath.exp(-800), 0)
        XCTAssertEqual(ToneMath.exp(800), .infinity)
        XCTAssertTrue(ToneMath.exp(.nan).isNaN)
    }

    func testLogMatchesFoundation() {
        var worstUlps = 0.0
        var x = 1e-6
        while x < 1e6 {
            let reference = log(x)
            let error = abs(ToneMath.log(x) - reference)
            worstUlps = max(worstUlps, error / max(ulp(reference), ulp(1)))
            x *= 1.000_731
        }
        XCTAssertLessThanOrEqual(worstUlps, 4, "largest difference from Foundation log, in ulp")
        XCTAssertEqual(ToneMath.log(1), 0)
        XCTAssertEqual(ToneMath.log(1000), log(1000), accuracy: 4 * ulp(log(1000)))
    }

    func testLogOfInvalidInputIsNaN() {
        XCTAssertTrue(ToneMath.log(0).isNaN || ToneMath.log(0) == -.infinity)
        XCTAssertTrue(ToneMath.log(-1).isNaN)
    }
}
