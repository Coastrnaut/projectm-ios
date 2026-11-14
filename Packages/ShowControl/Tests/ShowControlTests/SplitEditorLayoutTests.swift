// SplitEditorLayoutTests.swift — UIX-007-T03 (UIX-007-S1): the split editor's geometry. The acceptance
// sweep covers representative editor widths (minimum, each snap point, maximum, odd and out-of-range
// values) in landscape, portrait and odd window sizes and three output aspects (owner rule 7: a few
// hundred layouts, well under a second).
import ShowControl
import XCTest

final class SplitEditorLayoutTests: XCTestCase {
    private typealias Layout = SplitEditorLayout

    private static let windows: [(name: String, width: Double, height: Double)] = [
        ("13-inch landscape", 1376, 1032), ("13-inch portrait", 1032, 1376), ("11-inch portrait", 834, 1210),
        ("11-inch landscape", 1210, 834), ("narrow split", 700, 1032), ("odd", 1024.5, 700.25),
    ]
    private static let editorWidths: [Double] = [320, 400, 480, 560, 333.3, 517.7, 401, 100, 9_999, -5, .nan, .infinity]

    /// UIX-007-S1: aspect within 1e-6 of the output aspect, inside the pane, touching it on one axis, centred.
    func testResizingNeverDistortsTheOutputAspect() {
        var checked = 0
        for window in Self.windows {
            let aspects: [Double?] = [nil, 16.0 / 9.0, 4.0 / 3.0]
            for aspect in aspects {
                for requested in Self.editorWidths {
                    let layout = Layout(containerWidth: window.width, containerHeight: window.height,
                                        editorWidth: requested, outputAspect: aspect)
                    let label = "\(window.name) aspect \(aspect.map { String($0) } ?? "window") editor \(requested)"
                    let expected: Double = aspect ?? window.width / window.height
                    XCTAssertEqual(layout.outputRect.aspect, expected, accuracy: 1e-6, label)
                    XCTAssertTrue(layout.outputPane.contains(layout.outputRect, tolerance: 1e-9), label)
                    let touchesWidth: Bool = abs(layout.outputRect.width - layout.outputPane.width) < 1e-9
                    let touchesHeight: Bool = abs(layout.outputRect.height - layout.outputPane.height) < 1e-9
                    XCTAssertTrue(touchesWidth || touchesHeight, "fills the pane on one axis: \(label)")
                    XCTAssertEqual(layout.outputRect.x + layout.outputRect.width / 2, layout.outputPane.width / 2, accuracy: 1e-9, label)
                    XCTAssertEqual(layout.outputRect.y + layout.outputRect.height / 2, window.height / 2, accuracy: 1e-9, label)
                    XCTAssertEqual(layout.outputRect.width, expected * window.height * layout.scale, accuracy: 1e-6, label)
                    XCTAssertGreaterThanOrEqual(layout.editorWidth, Layout.minEditorWidth, label)
                    XCTAssertLessThanOrEqual(layout.editorWidth, layout.maxEditorWidth, label)
                    if layout.fits {
                        XCTAssertGreaterThanOrEqual(layout.outputPane.width, Layout.minOutputWidth - 1e-9, label)
                        XCTAssertEqual(layout.editorPane.maxX, window.width, accuracy: 1e-9, label)
                    }
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, Self.windows.count * 3 * Self.editorWidths.count)
    }

    func testBoundsAndFit() {
        let wide = Layout(containerWidth: 1376, containerHeight: 1032, editorWidth: 9_999)
        XCTAssertTrue(wide.fits)
        XCTAssertEqual(wide.maxEditorWidth, 560)
        XCTAssertEqual(wide.editorWidth, 560)
        XCTAssertEqual(wide.outputPane.width, 1376 - 24 - 560)
        let elevenPortrait = Layout(containerWidth: 834, containerHeight: 1210, editorWidth: 560)
        XCTAssertEqual(elevenPortrait.maxEditorWidth, 834 - 24 - 320)
        XCTAssertEqual(elevenPortrait.outputPane.width, 320)
        XCTAssertTrue(Layout(containerWidth: 664, containerHeight: 900, editorWidth: 400).fits)
        XCTAssertFalse(Layout(containerWidth: 663.5, containerHeight: 900, editorWidth: 400).fits)
        XCTAssertFalse(Layout(containerWidth: 402, containerHeight: 874, editorWidth: 400).fits, "iPhone")
        XCTAssertEqual(Layout(containerWidth: 1376, containerHeight: 1032, editorWidth: .nan).editorWidth, 400)
    }

    /// 13-inch landscape at Standard: the 4:3 window shape is letterboxed into a 952 × 1032 pane.
    func testLandscapeStandardIsLetterboxed() {
        let layout = Layout(containerWidth: 1376, containerHeight: 1032, editorWidth: 400)
        XCTAssertEqual(layout.outputPane.width, 952)
        XCTAssertEqual(layout.outputRect.width, 952, accuracy: 1e-9)
        XCTAssertEqual(layout.outputRect.height, 952 * 1032 / 1376, accuracy: 1e-9)
        XCTAssertEqual(layout.scale, 952.0 / 1376.0, accuracy: 1e-12)
        XCTAssertEqual(layout.divider, SplitEditorLayout.Rect(x: 952, y: 0, width: 24, height: 1032))
    }

    func testSnapping() {
        let layout = Layout(containerWidth: 1376, containerHeight: 1032, editorWidth: 400)
        XCTAssertEqual(layout.snapped(415), 400)
        XCTAssertEqual(layout.snapped(424), 400)
        XCTAssertEqual(layout.snapped(440), 440, "between snaps: stays where released")
        XCTAssertEqual(layout.snapped(462), 480)
        XCTAssertEqual(layout.snapped(200), 320, "clamped, then snapped")
        XCTAssertEqual(layout.snapped(700), 560)
        let small = Layout(containerWidth: 790, containerHeight: 1000, editorWidth: 400)
        XCTAssertEqual(small.maxEditorWidth, 446)
        XCTAssertEqual(small.snapped(445), 445, "480 is out of reach: no snap beyond the bound")
        XCTAssertEqual(small.snapped(330), 320)
    }

    func testSteppingThroughSnapPoints() {
        let layout = Layout(containerWidth: 1376, containerHeight: 1032, editorWidth: 400)
        XCTAssertEqual(layout.nextSnap(after: 320), 400)
        XCTAssertEqual(layout.nextSnap(after: 400), 480)
        XCTAssertEqual(layout.nextSnap(after: 480), 560)
        XCTAssertEqual(layout.nextSnap(after: 560), 560)
        XCTAssertEqual(layout.previousSnap(before: 560), 480)
        XCTAssertEqual(layout.previousSnap(before: 440), 400)
        XCTAssertEqual(layout.previousSnap(before: 320), 320)
        XCTAssertEqual(SplitEditorLayout.snapName(for: 400), "Standard")
        XCTAssertEqual(SplitEditorLayout.snapName(for: 480), "Wide")
        XCTAssertNil(SplitEditorLayout.snapName(for: 440))
    }
}
