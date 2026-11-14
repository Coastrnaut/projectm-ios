// PerformanceLayoutTests.swift — UIX-005-T02 (UIX-005-S4): the performance pad's geometry per size
// class, a few representative areas (owner rule 7).
import ShowControl
import XCTest

final class PerformanceLayoutTests: XCTestCase {
    /// iPhone 17 portrait (safe area about 402 × 794): one row of 60 pt targets.
    func testIPhonePortraitIsABottomBarOfSixtyPointTargets() {
        let layout = PerformanceLayout(width: 402, height: 794, regular: false)
        XCTAssertEqual(layout.arrangement, .bottomBar)
        XCTAssertEqual(layout.target, 60)
        XCTAssertGreaterThanOrEqual(layout.target, 44, "larger than Apple's minimum on purpose")
        XCTAssertEqual(layout.reservedInsets(barHeight: 110), PerformanceLayout.Insets(bottom: 118))
    }

    /// iPhone 17 landscape (safe area about 750 × 381; compact height): side columns, both reserved.
    func testIPhoneLandscapeIsTwoSideColumns() {
        let layout = PerformanceLayout(width: 750, height: 381, regular: false)
        XCTAssertEqual(layout.arrangement, .sideColumns)
        XCTAssertEqual(layout.target, 60)
        XCTAssertEqual(layout.columnWidth, 76)
        XCTAssertEqual(layout.reservedInsets(barHeight: 999), PerformanceLayout.Insets(leading: 76, trailing: 76),
                       "columns ignore the bar height")
        // The visual centre stays clear: two columns take at most a quarter of the width each.
        XCTAssertLessThan(2 * layout.columnWidth, 750 / 2)
    }

    /// iPad (both size classes regular): larger targets, in either shape.
    func testIPadRegularUsesSeventyTwoPointTargets() {
        let portrait = PerformanceLayout(width: 820, height: 1140, regular: true)
        XCTAssertEqual(portrait.arrangement, .bottomBar)
        XCTAssertEqual(portrait.target, 72)
        XCTAssertEqual(portrait.spacing, 16)
        let landscape = PerformanceLayout(width: 1180, height: 780, regular: true)
        XCTAssertEqual(landscape.arrangement, .sideColumns)
        XCTAssertEqual(landscape.columnWidth, 88)
    }

    /// A narrow window (iPad Slide Over, a small split) that cannot hold one row wraps to two rows.
    func testANarrowAreaWrapsToTwoRows() {
        XCTAssertEqual(PerformanceLayout.rowWidth(target: 60, spacing: 12), 292)
        XCTAssertEqual(PerformanceLayout(width: 292, height: 700, regular: false).arrangement, .bottomBar, "exactly fits")
        let narrow = PerformanceLayout(width: 280, height: 700, regular: false)
        XCTAssertEqual(narrow.arrangement, .bottomGrid)
        XCTAssertEqual(narrow.target, 60, "targets never shrink")
    }

    /// A square area counts as portrait (a bar), and a negative measured height reserves only the margin.
    func testASquareAreaIsABar() {
        let layout = PerformanceLayout(width: 500, height: 500, regular: false)
        XCTAssertEqual(layout.arrangement, .bottomBar)
        XCTAssertEqual(layout.reservedInsets(barHeight: -5), PerformanceLayout.Insets(bottom: 8))
    }
}
