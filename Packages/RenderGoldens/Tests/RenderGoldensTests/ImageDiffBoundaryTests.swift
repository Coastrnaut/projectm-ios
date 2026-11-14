// ImageDiffBoundaryTests.swift — QA-003-T07, T09: thresholds at their boundaries, size mismatch, an
// all-different image, determinism, the report and the diff image (QA-003-S2, S3; contract I1-I3).
// Plain Swift: runs on Linux.
import GoldenImages
import XCTest

final class ImageDiffBoundaryTests: XCTestCase {
    private let width = 128, height = 96

    func testColourToleranceBoundary() {
        let base = ImageDiffFixture.flat(width, height)
        let all = Array(0..<(width * height))
        let atTolerance = ImageDiff.compare(expected: base, actual: ImageDiffFixture.bumped(base, pixels: all, delta: 2))
        XCTAssertTrue(atTolerance.passed, atTolerance.summary)
        XCTAssertEqual(atTolerance.exceedingPixels, 0)
        XCTAssertEqual(atTolerance.changedPixels, width * height)
        let above = ImageDiff.compare(expected: base, actual: ImageDiffFixture.bumped(base, pixels: [500], delta: 3))
        XCTAssertEqual(above.exceedingPixels, 1)
        XCTAssertEqual(above.maxChannelDifference, 3)
        XCTAssertTrue(above.passed, "one exceeding pixel is within the allowance")
    }

    func testAllowedCountBoundary() {
        let base = ImageDiffFixture.flat(width, height)
        for tolerance in [ImageDiffTolerance.qa002, .golden] {
            let twelve = ImageDiffFixture.bumped(base, pixels: ImageDiffFixture.scattered(count: 12, width: width), delta: 50)
            let thirteen = ImageDiffFixture.bumped(base, pixels: ImageDiffFixture.scattered(count: 13, width: width), delta: 50)
            let pass = ImageDiff.compare(expected: base, actual: twelve, tolerance: tolerance)
            XCTAssertTrue(pass.passed, pass.summary)
            XCTAssertEqual(pass.allowedPixels, 12)
            let fail = ImageDiff.compare(expected: base, actual: thirteen, tolerance: tolerance)
            XCTAssertEqual(fail.failures, [.count], fail.summary)
            XCTAssertEqual(fail.unmatchedPixels, 13)
        }
    }

    func testMaxExceedingPixelsCapsTheFraction() {
        let tolerance = ImageDiffTolerance(channelThreshold: 2, allowedFraction: 1, maxExceedingPixels: 3)
        XCTAssertEqual(tolerance.allowedPixels(total: 12_288), 3)
        let base = ImageDiffFixture.flat(width, height)
        let three = ImageDiffFixture.bumped(base, pixels: ImageDiffFixture.scattered(count: 3, width: width), delta: 9)
        let four = ImageDiffFixture.bumped(base, pixels: ImageDiffFixture.scattered(count: 4, width: width), delta: 9)
        XCTAssertTrue(ImageDiff.compare(expected: base, actual: three, tolerance: tolerance).passed)
        XCTAssertFalse(ImageDiff.compare(expected: base, actual: four, tolerance: tolerance).passed)
    }

    func testClusterLimitBoundary() {
        let base = ImageDiffFixture.flat(width, height)
        let eight = ImageDiffFixture.bumped(base, pixels: ImageDiffFixture.block(x: 10, y: 10, w: 4, h: 2, width: width), delta: 60)
        let atLimit = ImageDiff.compare(expected: base, actual: eight, tolerance: .golden)
        XCTAssertEqual(atLimit.largestCluster, 8)
        XCTAssertTrue(atLimit.passed, atLimit.summary)
        // Diagonal neighbours join a cluster (8-connectivity).
        let diagonal = ImageDiffFixture.bumped(base, pixels: (0..<9).map { (i: Int) -> Int in (20 + i) * width + 20 + i }, delta: 60)
        let joined = ImageDiff.compare(expected: base, actual: diagonal, tolerance: .golden)
        XCTAssertEqual(joined.largestCluster, 9)
        XCTAssertEqual(joined.failures, [.cluster])
    }

    func testSSIMGateAndTinyImages() {
        let base = ImageDiffFixture.flat(width, height)
        let blob = ImageDiffFixture.bumped(base, pixels: ImageDiffFixture.block(x: 40, y: 40, w: 3, h: 3, width: width), delta: 120)
        let tolerance = ImageDiffTolerance(channelThreshold: 2, allowedFraction: 0.001, minimumSSIM: 0.999)
        let report = ImageDiff.compare(expected: base, actual: blob, tolerance: tolerance)
        XCTAssertEqual(report.failures, [.ssim], report.summary)
        XCTAssertEqual(try XCTUnwrap(ImageDiff.compare(expected: base, actual: base, tolerance: tolerance).ssim), 1, accuracy: 1e-9)
        // Below one 8 × 8 window SSIM is not computed and the minimum does not fail.
        let tiny = ImageDiffFixture.flat(4, 4)
        let tinyReport = ImageDiff.compare(expected: tiny, actual: ImageDiffFixture.bumped(tiny, pixels: [0], delta: 90),
                                           tolerance: tolerance)
        XCTAssertNil(tinyReport.ssim)
        XCTAssertFalse(tinyReport.failures.contains(.ssim))
    }

    func testAllDifferentImageFailsWithWholeImageBox() {
        let report = ImageDiff.compare(expected: ImageDiffFixture.flat(width, height, value: 100),
                                       actual: ImageDiffFixture.flat(width, height, value: 200))
        XCTAssertEqual(report.failures, [.count, .cluster])
        XCTAssertEqual(report.unmatchedPixels, width * height)
        XCTAssertEqual(report.largestCluster, width * height)
        XCTAssertEqual(report.boundingBox, ImageDiffBoundingBox(minX: 0, minY: 0, maxX: width - 1, maxY: height - 1))
        XCTAssertEqual(report.maxChannelDifference, 100)
        let result = GoldenComparisonResult(report: report)
        XCTAssertEqual(result.outcome, .exceedsTolerance)
    }

    func testSizeMismatchFails() {
        let report = ImageDiff.compare(expected: ImageDiffFixture.flat(128, 96), actual: ImageDiffFixture.flat(256, 192))
        XCTAssertEqual(report.failures, [.size])
        XCTAssertEqual(report.summary, "FAIL [size]: expected 128x96, actual 256x192")
        XCTAssertEqual(GoldenComparisonResult(report: report).outcome, .sizeMismatch)
    }

    func testExactRejectsAnyChange() {
        let base = ImageDiffFixture.reference()
        XCTAssertTrue(ImageDiff.compare(expected: base, actual: base, tolerance: .exact).identical)
        let one = ImageDiffFixture.bumped(base, pixels: [7], delta: 1)
        XCTAssertEqual(ImageDiff.compare(expected: base, actual: one, tolerance: .exact).failures, [.count])
    }

    func testDeterminism() {
        let reference = ImageDiffFixture.reference()
        let noisy = ImageDiffFixture.saltAndPepper(ImageDiffFixture.jitter(reference, delta: 2, seed: 9), count: 10, seed: 10).image
        XCTAssertEqual(noisy, ImageDiffFixture.saltAndPepper(ImageDiffFixture.jitter(reference, delta: 2, seed: 9), count: 10,
                                                             seed: 10).image, "fixtures are seeded")
        let first = ImageDiff.compare(expected: reference, actual: noisy)
        let second = ImageDiff.compare(expected: reference, actual: noisy)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.summary, second.summary)
        // Without forgiveness the counts are symmetric.
        let ab = ImageDiff.compare(expected: reference, actual: noisy, tolerance: .qa002)
        let ba = ImageDiff.compare(expected: noisy, actual: reference, tolerance: .qa002)
        XCTAssertEqual(ab.exceedingPixels, ba.exceedingPixels)
        XCTAssertEqual(ab.changedPixels, ba.changedPixels)
    }

    func testToleranceClampsAndPresets() {
        let t = ImageDiffTolerance(channelThreshold: 999, allowedFraction: -1, maxExceedingPixels: -4, neighborhoodRadius: 99,
                                   maxClusterPixels: -1)
        XCTAssertEqual(t.channelThreshold, 255)
        XCTAssertEqual(t.allowedFraction, 0)
        XCTAssertEqual(t.maxExceedingPixels, 0)
        XCTAssertEqual(t.neighborhoodRadius, 8)
        XCTAssertEqual(t.maxClusterPixels, 0)
        XCTAssertEqual(GoldenTolerance.golden.channelThreshold, GoldenTolerance.qa002.channelThreshold)
        XCTAssertEqual(GoldenTolerance.golden.allowedFraction, GoldenTolerance.qa002.allowedFraction)
        XCTAssertEqual(GoldenTolerance.golden.neighborhoodRadius, 1)
        XCTAssertEqual(GoldenTolerance.golden.maxClusterPixels, 8)
        XCTAssertNil(GoldenTolerance.golden.minimumSSIM)
    }

    func testReportSummaryIsReadable() {
        let base = ImageDiffFixture.flat(width, height)
        let actual = ImageDiffFixture.bumped(base, pixels: ImageDiffFixture.block(x: 30, y: 20, w: 5, h: 4, width: width), delta: 40)
        let report = ImageDiff.compare(expected: base, actual: actual)
        let summary = report.summary
        XCTAssertTrue(summary.hasPrefix("FAIL [count, cluster]: "), summary)
        for part in ["20 of 12288 pixels changed", "20 above the threshold 2/255", "20 unmatched, allowed 12",
                     "largest channel difference 40/255", "largest cluster 20 (limit 8)", "box x 30-34, y 20-23", "SSIM 0."] {
            XCTAssertTrue(summary.contains(part), "missing \"\(part)\" in \(summary)")
        }
        let golden = GoldenComparison.compare(expected: base, actual: actual)
        XCTAssertEqual(golden.outcome, .exceedsTolerance)
        XCTAssertEqual(golden.exceedingPixels, 20)
        XCTAssertTrue(golden.summary.hasPrefix("exceedsTolerance: FAIL"), golden.summary)
        XCTAssertTrue(GoldenComparison.compare(expected: base, actual: base).summary.hasPrefix("identical: PASS"))
    }

    func testDiffImageMarksForgivenUnmatchedAndBox() {
        let reference = ImageDiffFixture.reference()
        // Forgiven: the one-pixel shift turns shape edges orange.
        let shifted = ImageDiffFixture.shiftedRight(reference, by: 1)
        let shiftDiff = GoldenDiffImage.make(expected: reference, actual: shifted)
        let shapes = ImageDiffFixture.shapes(width: width)
        let edge = shiftDiff.pixel(x: shapes.rectX, y: shapes.rectY + 5)
        XCTAssertEqual([edge.r, edge.g, edge.b], [GoldenDiffImage.forgivenColor.0, GoldenDiffImage.forgivenColor.1,
                                                  GoldenDiffImage.forgivenColor.2])
        // Unmatched red inside a cyan outline.
        let base = ImageDiffFixture.flat(width, height)
        let blob = ImageDiffFixture.bumped(base, pixels: ImageDiffFixture.block(x: 50, y: 30, w: 4, h: 4, width: width), delta: 100)
        let diff = GoldenDiffImage.make(expected: base, actual: blob)
        XCTAssertEqual(diff.pixel(x: 51, y: 31).r, 255)
        XCTAssertEqual(diff.pixel(x: 51, y: 31).g, 0)
        let outline = diff.pixel(x: 49, y: 31)
        XCTAssertEqual([outline.r, outline.g, outline.b], [GoldenDiffImage.boxColor.0, GoldenDiffImage.boxColor.1,
                                                           GoldenDiffImage.boxColor.2])
        let outside = diff.pixel(x: 10, y: 10)
        XCTAssertEqual(outside.r, outside.g, "far from the box stays grey")
        XCTAssertNotEqual(outside.g, GoldenDiffImage.boxColor.1)
    }
}
