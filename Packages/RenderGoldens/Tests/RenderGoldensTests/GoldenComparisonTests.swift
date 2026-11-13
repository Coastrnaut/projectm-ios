// QA-002-T11: the fixed QA-002 rule at its boundaries and the diff image's colors (QA-002-R7, R8;
// research D7, D8). Plain Swift: runs on Linux.
import GoldenImages
import XCTest

final class GoldenComparisonTests: XCTestCase {
    private func image(_ width: Int = 128, _ height: Int = 96, fill: UInt8 = 100) -> GoldenImage {
        GoldenImage(width: width, height: height, rgba: [UInt8](repeating: fill, count: width * height * 4))!
    }

    /// `image` with the first `count` pixels' red channel raised by `delta`.
    private func changed(_ base: GoldenImage, count: Int, delta: Int) -> GoldenImage {
        var rgba = base.rgba
        for p in 0..<count { rgba[p * 4] = UInt8(Int(rgba[p * 4]) + delta) }
        return GoldenImage(width: base.width, height: base.height, rgba: rgba)!
    }

    func testImageValidation() {
        XCTAssertNil(GoldenImage(width: 0, height: 1, rgba: []))
        XCTAssertNil(GoldenImage(width: 2, height: 2, rgba: [0, 0, 0]))
        XCTAssertNotNil(GoldenImage(width: 1, height: 1, rgba: [1, 2, 3, 4]))
    }

    func testAllowedPixelsRoundDown() {
        XCTAssertEqual(GoldenTolerance.qa002.allowedPixels(total: 12_288), 12)
        XCTAssertEqual(GoldenTolerance.qa002.allowedPixels(total: 49_152), 49)
        XCTAssertEqual(GoldenTolerance.qa002.allowedPixels(total: 999), 0)
    }

    func testIdenticalAndWithinTolerance() {
        let base = image()
        let same = GoldenComparison.compare(expected: base, actual: base)
        XCTAssertEqual(same.outcome, .identical)
        XCTAssertTrue(same.passed)
        // Rounding noise everywhere (±2) passes.
        let noisy = changed(base, count: base.pixelCount, delta: 2)
        let r = GoldenComparison.compare(expected: base, actual: noisy)
        XCTAssertEqual(r.outcome, .withinTolerance)
        XCTAssertEqual(r.changedPixels, base.pixelCount)
        XCTAssertEqual(r.exceedingPixels, 0)
        XCTAssertEqual(r.maxChannelDifference, 2)
    }

    func testBoundaryCounts() {
        let base = image()
        XCTAssertEqual(GoldenComparison.compare(expected: base, actual: changed(base, count: 12, delta: 3)).outcome, .withinTolerance)
        let over = GoldenComparison.compare(expected: base, actual: changed(base, count: 13, delta: 3))
        XCTAssertEqual(over.outcome, .exceedsTolerance)
        XCTAssertFalse(over.passed)
        XCTAssertEqual(over.exceedingPixels, 13)
        XCTAssertTrue(over.summary.contains("13 above the threshold"))
    }

    func testAlphaCountsAndCountsAreSymmetric() {
        let base = image()
        var rgba = base.rgba
        for p in 0..<20 { rgba[p * 4 + 3] = 0 }
        let transparent = GoldenImage(width: base.width, height: base.height, rgba: rgba)!
        let ab = GoldenComparison.compare(expected: base, actual: transparent)
        let ba = GoldenComparison.compare(expected: transparent, actual: base)
        XCTAssertEqual(ab.outcome, .exceedsTolerance)
        XCTAssertEqual(ab, ba)
    }

    func testSizeMismatchFails() {
        let r = GoldenComparison.compare(expected: image(128, 96), actual: image(256, 192))
        XCTAssertEqual(r.outcome, .sizeMismatch)
        XCTAssertFalse(r.passed)
    }

    func testDiffImageColors() {
        let base = image(4, 1, fill: 200)
        var rgba = base.rgba
        rgba[4] = 202     // pixel 1: within (2)
        rgba[8] = 100     // pixel 2: above (100)
        let actual = GoldenImage(width: 4, height: 1, rgba: rgba)!
        let diff = GoldenDiffImage.make(expected: base, actual: actual)
        let unchanged = diff.pixel(x: 0, y: 0)
        XCTAssertEqual(unchanged.r, unchanged.g)
        XCTAssertLessThan(Int(unchanged.r), 80, "unchanged pixels are dimmed grey")
        XCTAssertEqual(diff.pixel(x: 1, y: 0).r, GoldenDiffImage.withinColor.0)
        XCTAssertEqual(diff.pixel(x: 1, y: 0).g, GoldenDiffImage.withinColor.1)
        let above = diff.pixel(x: 2, y: 0)
        XCTAssertEqual(above.r, 255)
        XCTAssertEqual(above.g, 0)
        XCTAssertEqual(diff.pixel(x: 3, y: 0).a, 255, "opaque")
        // Different sizes: the larger size, magenta outside the overlap.
        let wide = GoldenDiffImage.make(expected: image(2, 1), actual: image(3, 2))
        XCTAssertEqual(wide.width, 3)
        XCTAssertEqual(wide.height, 2)
        XCTAssertEqual(wide.pixel(x: 2, y: 1).r, GoldenDiffImage.outsideColor.0)
        XCTAssertEqual(wide.pixel(x: 2, y: 1).b, GoldenDiffImage.outsideColor.2)
    }
}
