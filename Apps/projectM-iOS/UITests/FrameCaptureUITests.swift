// FrameCaptureUITests.swift — REC-001-T15 on the iOS Simulator: Save Frame → PNG writes the shown
// visual's next frame; the DEBUG `-uitestCaptureDirectory` option replaces the Files sheet (which
// cannot be automated) and `frameCaptureProbe` reports what ImageIO reads back. Simulator results
// are never device evidence (Constitution X). Owner rule 7: under 30 s.
import XCTest

@MainActor
final class FrameCaptureUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// Circular Spectrum (an opaque native visual, through the argument domain) or projectM, with
    /// in-app playback.
    private func launch(visual: String = "circularSpectrum", identifier: String = "circularSpectrum") {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", visual,
                               "-uitestCaptureDirectory", "FrameCaptureUITests"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.appears(within: 10))
    }

    private func saveFrameAsPNG() {
        showControls()
        let save = app.buttons["saveFrame"]
        XCTAssertTrue(save.exists)
        XCTAssertEqual(save.label, "Save Frame")
        save.tap()
        let png = app.buttons["PNG"].firstMatch
        XCTAssertTrue(png.appears(within: 5), "the format choice")
        png.tap()
    }

    /// projectM (ANGLE): the frame after the post-pass at the surface size; while the output is
    /// blacked out Save Frame refuses with a notice and writes nothing (REC-001-R12).
    func testProjectMFrameAndBlackoutRefusal() {
        launch(visual: "projectM", identifier: "visualizer")
        let screen = app.windows.firstMatch.frame.size
        saveFrameAsPNG()
        XCTAssertTrue(poll(10) { self.probe.hasPrefix("png ") }, "probe: \(probe)")
        let parts = probe.split(separator: " ")
        XCTAssertEqual(parts.last, "opaque")
        let size = parts.count == 3 ? parts[1].split(separator: "x").compactMap { Int($0) } : []
        XCTAssertEqual(size.count, 2)
        if size.count == 2 { XCTAssertGreaterThanOrEqual(Double(size[0]) / Double(screen.width), 2, "pixels, not points") }
        showControls()
        app.buttons["blackout"].tap()
        showControls()
        app.buttons["saveFrame"].tap()
        XCTAssertTrue(poll(5) { self.probe == "refused: outputBlackedOut" }, "probe: \(probe)")
        XCTAssertEqual(app.staticTexts["frameCaptureNoticeText"].label, "Restore the output to save a frame.")
        XCTAssertFalse(app.buttons["PNG"].exists, "no format choice while blacked out")
    }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private var probe: String { (app.staticTexts["frameCaptureProbe"].value as? String) ?? "" }

    func testSaveFrameAsPNGWritesTheVisualsPixelSize() {
        launch()
        let screen = app.windows.firstMatch.frame.size
        saveFrameAsPNG()
        XCTAssertTrue(poll(10) { self.probe.hasPrefix("png ") }, "probe: \(probe)")
        // "png <w>x<h> opaque": an opaque native visual at its drawable size (points × display scale;
        // the quality governor's render scale is 1 on the simulator).
        let parts = probe.split(separator: " ")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts.last, "opaque")
        let size = parts[1].split(separator: "x").compactMap { Int($0) }
        XCTAssertEqual(size.count, 2)
        let scale = Double(size[0]) / Double(screen.width)
        XCTAssertGreaterThanOrEqual(scale, 2, "pixels, not points")
        XCTAssertEqual(Double(size[1]) / Double(screen.height), scale, accuracy: 0.01, "the full-screen drawable's aspect")
        XCTAssertTrue(app.otherElements["frameCaptureNotice"].appears(within: 5), "Frame saved.")
    }
}
