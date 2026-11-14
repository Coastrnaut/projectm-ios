// ImageDiffAcceptanceTests.swift — QA-003-T06, the row's acceptance: "One-pixel noise passes while
// major geometry regression fails" (QA-003-S1; spec User Story 1). Plain Swift: runs on Linux.
import GoldenImages
import XCTest

final class ImageDiffAcceptanceTests: XCTestCase {
    /// Seeded salt-and-pepper (within the allowed count) on top of ±2 everywhere passes with `.golden`,
    /// at both golden resolutions.
    func testSinglePixelNoisePasses() {
        for (width, height, count) in [(128, 96, 10), (256, 192, 40)] {
            let reference = ImageDiffFixture.reference(width: width, height: height)
            let jittered = ImageDiffFixture.jitter(reference, delta: 2, seed: 3_003)
            let noisy = ImageDiffFixture.saltAndPepper(jittered, count: count, seed: 33).image
            let report = ImageDiff.compare(expected: reference, actual: noisy, tolerance: .golden)
            XCTAssertTrue(report.passed, report.summary)
            XCTAssertEqual(report.unmatchedPixels, count, "every noise pixel is unmatched")
            XCTAssertEqual(report.largestCluster, 1, "noise pixels are isolated")
            XCTAssertGreaterThan(report.changedPixels, width * height / 2, "the ±2 jitter touched most pixels")
            XCTAssertLessThanOrEqual(report.maxChannelDifference, 255)
        }
    }

    /// A shape moved by 12 pixels, scaled by 1.5 or removed fails, and names the geometry rule.
    func testMajorGeometryRegressionsFail() {
        let width = 128, height = 96
        let reference = ImageDiffFixture.reference(width: width, height: height)
        var moved = ImageDiffFixture.shapes(width: width)
        moved.rectX += 12
        var scaled = ImageDiffFixture.shapes(width: width)
        scaled.circleRadius = scaled.circleRadius * 3 / 2
        var removed = ImageDiffFixture.shapes(width: width)
        removed.rectVisible = false
        let cases: [(String, ImageDiffFixture.Shapes)] = [("moved 12 px", moved), ("scaled 1.5x", scaled), ("removed", removed)]
        for (name, shapes) in cases {
            let actual = ImageDiffFixture.jitter(ImageDiffFixture.render(width: width, height: height, shapes: shapes), delta: 2,
                                                 seed: 3_003)
            let report = ImageDiff.compare(expected: reference, actual: actual, tolerance: .golden)
            XCTAssertFalse(report.passed, "\(name): \(report.summary)")
            XCTAssertTrue(report.failures.contains(.cluster), "\(name): \(report.failures)")
            XCTAssertGreaterThan(report.largestCluster, 100, name)
            XCTAssertNotNil(report.boundingBox, name)
        }
    }

    /// Geometry fails even when the regression's pixel count alone would be allowed: a removed 3 × 3
    /// dot (9 pixels, under the 12 allowed) fails on its cluster.
    func testSmallCompactRegressionFailsOnClusterNotCount() {
        let reference = ImageDiffFixture.flat(128, 96)
        let actual = ImageDiffFixture.bumped(reference, pixels: ImageDiffFixture.block(x: 60, y: 40, w: 3, h: 3, width: 128), delta: 80)
        let report = ImageDiff.compare(expected: reference, actual: actual, tolerance: .golden)
        XCTAssertEqual(report.failures, [.cluster], report.summary)
        XCTAssertTrue(GoldenComparison.compare(expected: reference, actual: actual, tolerance: .qa002).passed,
                      "QA-002's colour-only rule let this through")
    }

    /// A one-pixel rasterization shift of the whole image is forgiven with radius 1, and fails QA-002's
    /// rule (which has no geometry tolerance).
    func testOnePixelShiftIsForgiven() {
        let reference = ImageDiffFixture.reference()
        let shifted = ImageDiffFixture.shiftedRight(reference, by: 1)
        let golden = ImageDiff.compare(expected: reference, actual: shifted, tolerance: .golden)
        XCTAssertTrue(golden.passed, golden.summary)
        XCTAssertGreaterThan(golden.forgivenPixels, 12)
        XCTAssertEqual(golden.unmatchedPixels, 0)
        XCTAssertFalse(ImageDiff.compare(expected: reference, actual: shifted, tolerance: .qa002).passed)
        // Twelve pixels is not a rasterization shift.
        XCTAssertFalse(ImageDiff.compare(expected: reference, actual: ImageDiffFixture.shiftedRight(reference, by: 12),
                                         tolerance: .golden).passed)
    }
}
