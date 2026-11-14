// CameraCropUITests.swift — CAM-007-T11 on the iOS Simulator with the stand-in camera
// (`-uitestCamera granted`, DEBUG only): Settings › Camera offers Crop, Anchor and Zoom with their
// defaults (Fill, Center, 1 times), and choosing Fit, Top and 2× shows in the controls' values
// (CAM-007-R7; S4). The framing itself is checked from pixels by CameraCropLayerTests and
// CameraCropTests; simulator results are never device evidence.
import XCTest

@MainActor
final class CameraCropUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var mode: XCUIElement { app.segmentedControls["cameraCropModePicker"] }
    private var anchor: XCUIElement { app.segmentedControls["cameraCropAnchorPicker"] }
    private var zoom: XCUIElement { app.segmentedControls["cameraZoomPicker"] }

    /// Taps a segment and waits for the picker's value; taps once more if the first tap was lost
    /// (seen once under heavy load on the merged tree, 2026-11-14: Zoom stayed "1 times").
    private func choose(_ segment: XCUIElement, in picker: XCUIElement, expect value: String) -> Bool {
        for _ in 0..<2 {
            _ = poll(2) { segment.isHittable }
            segment.tap()
            if poll(3, { (picker.value as? String) == value }) { return true }
        }
        return false
    }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testChooseFitTopAndTwiceZoom() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestCamera", "granted"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))

        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertFalse(mode.exists, "no crop controls before Camera is chosen")
        let row = app.visualRow("Camera")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()

        XCTAssertTrue(app.reveal(mode), "Crop appears in the Camera section")
        XCTAssertEqual(mode.label, "Crop")
        XCTAssertEqual(mode.value as? String, "Fill", "Fill by default")
        XCTAssertTrue(choose(mode.buttons["Fit"], in: mode, expect: "Fit"), "Crop: \(String(describing: mode.value))")

        XCTAssertTrue(app.reveal(anchor))
        XCTAssertEqual(anchor.value as? String, "Center", "Center by default")
        XCTAssertTrue(choose(anchor.buttons["Top"], in: anchor, expect: "Top"), "Anchor: \(String(describing: anchor.value))")

        XCTAssertTrue(app.reveal(zoom))
        XCTAssertEqual(zoom.value as? String, "1 times", "1× by default")
        XCTAssertEqual(zoom.buttons.count, 4, "1×, 1.5×, 2×, 3×")
        XCTAssertTrue(choose(zoom.buttons.element(boundBy: 2), in: zoom, expect: "2 times"), "Zoom: \(String(describing: zoom.value))")

        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(app.descendants(matching: .any)["cameraVisual"].firstMatch.appears(within: 10), "the Camera visual is shown")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
