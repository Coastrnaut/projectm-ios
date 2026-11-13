// CameraPrivacyStatusUITests.swift — CAM-012-T10 on the iOS Simulator with the stand-in camera
// (`-uitestCamera granted`, DEBUG only): the roadmap acceptance "Stop releases session and returns to
// fallback visual without freeze" (CAM-012-S1 to S4). Simulator results are never device evidence
// (Constitution X); CAM-012-T13 checks iOS's own indicator on D1. Waits use generous ceilings, never
// frame budgets; every tap on a control follows `showControls()`.
import XCTest

@MainActor
final class CameraPrivacyStatusUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var cameraVisual: XCUIElement { app.descendants(matching: .any)["cameraVisual"].firstMatch }
    private var circularSpectrum: XCUIElement { app.descendants(matching: .any)["circularSpectrum"].firstMatch }
    private var indicator: XCUIElement { app.otherElements["cameraIndicator"] }
    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }

    /// See NativeVisualUITests.showControls: ends on a tap that shows the controls with a fresh 5 s hide.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func choose(_ title: String) {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow(title)
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    /// S1-S4: the badge shows while the camera runs; Stop camera removes it, returns to the visual
    /// chosen before Camera, keeps the source and the controls working, and the camera stays off.
    func testStopCameraReturnsToThePreviousVisualAndKeepsRunning() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestCamera", "granted"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertFalse(indicator.exists, "no badge before the camera runs")

        choose("Circular Spectrum")
        XCTAssertTrue(circularSpectrum.appears(within: 10))
        choose("Camera")
        XCTAssertTrue(cameraVisual.appears(within: 10))
        XCTAssertTrue(indicator.appears(within: 5), "the badge appears while the camera runs")
        let status = app.descendants(matching: .any)["cameraIndicatorStatus"].firstMatch
        XCTAssertEqual(status.label, "Camera on")
        XCTAssertTrue(poll(5) { (status.value as? String) == "Live" }, "value: \(String(describing: status.value))")
        XCTAssertTrue(poll(8) { !self.app.otherElements["controls"].exists }, "the controls hide")
        XCTAssertTrue(indicator.exists, "the badge stays when the controls hide")

        let stop = app.buttons["stopCamera"]
        XCTAssertEqual(stop.label, "Stop camera")
        stop.tap()
        XCTAssertTrue(indicator.disappears(within: 5), "the badge goes")
        XCTAssertTrue(cameraVisual.disappears(within: 5), "the Camera visual is released")
        XCTAssertTrue(circularSpectrum.appears(within: 10), "the visual chosen before Camera is shown")
        XCTAssertEqual(starts, "1", "the source is not restarted")

        showControls()   // the controls respond; pause and resume do not bring the camera back
        app.buttons["pauseResume"].tap()
        XCTAssertTrue(app.staticTexts["pausedLabel"].appears(within: 5))
        showControls()
        app.buttons["pauseResume"].tap()
        XCTAssertTrue(app.staticTexts["pausedLabel"].disappears(within: 5))
        XCTAssertFalse(cameraVisual.exists, "the camera stays off")
        XCTAssertFalse(indicator.exists)
        XCTAssertEqual(starts, "1")
    }
}
