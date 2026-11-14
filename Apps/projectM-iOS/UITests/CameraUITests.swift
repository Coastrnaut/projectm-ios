// CameraUITests.swift — CAM-001-T15, T18 on the iOS Simulator with the stand-in camera
// (`-uitestCamera <scenario>`, DEBUG only): the roadmap acceptance "User grant shows frames; denial
// shows nonblocking fallback" (CAM-001-S1, S2). The real permission prompt is never shown. Simulator
// results are never device evidence (Constitution X); the device stage covers the real camera.
// Waits use generous ceilings, never frame budgets; every tap on a control follows `showControls()`.
import XCTest

@MainActor
final class CameraUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(camera scenario: String) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestCamera", scenario] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var cameraVisual: XCUIElement { app.descendants(matching: .any)["cameraVisual"].firstMatch }
    private var framesShown: Int { Int(app.staticTexts["cameraFramesShown"].value as? String ?? "") ?? -1 }
    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }

    /// See NativeVisualUITests.showControls: ends on a tap that shows the controls with a fresh 5 s hide.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func openSettings() {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    private func choose(_ title: String) {
        openSettings()
        let row = app.visualRow(title)
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        closeSettings()
    }

    /// S1: with access allowed, Camera shows camera pictures (the shown-frame count grows) and the
    /// source is not restarted; another visual releases the camera.
    func testGrantedCameraShowsFrames() {
        launch(camera: "granted")
        XCTAssertFalse(cameraVisual.exists, "the camera never starts by itself")
        choose("Camera")
        XCTAssertTrue(cameraVisual.appears(within: 10), "the Camera visual is shown")
        XCTAssertTrue(poll(10) { (self.cameraVisual.value as? String) == "Live" }, "VoiceOver value: \(String(describing: cameraVisual.value))")
        XCTAssertTrue(poll(10) { self.framesShown > 0 }, "camera frames are shown")
        let first = framesShown
        XCTAssertTrue(poll(10) { self.framesShown > first }, "and keep coming (\(first) → \(framesShown))")
        XCTAssertFalse(app.otherElements["cameraNotice"].exists, "no notice while live")
        XCTAssertEqual(starts, "1", "choosing Camera does not restart the source")

        choose("Circular Spectrum")
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 10))
        XCTAssertTrue(cameraVisual.disappears(within: 5), "another visual releases the camera")
        XCTAssertFalse(app.staticTexts["cameraFramesShown"].exists)
    }

    /// S2: with access denied, the notice explains how to allow it, nothing waits for an answer, and
    /// the controls, Settings and the source keep working.
    func testDeniedCameraShowsNoticeAndAppStaysUsable() {
        launch(camera: "denied")
        choose("Camera")
        let notice = app.otherElements["cameraNotice"]
        XCTAssertTrue(notice.appears(within: 5), "the non-blocking notice appears")
        XCTAssertEqual(app.staticTexts["cameraNoticeText"].label, "Camera access is off. To show the camera, allow it in Settings.")
        XCTAssertTrue(app.buttons["cameraOpenSettings"].exists, "Open Settings is offered")
        XCTAssertTrue(cameraVisual.exists, "the visual keeps running (spectrum without the camera)")
        XCTAssertEqual(cameraVisual.value as? String, "Camera access off")
        XCTAssertEqual(framesShown, 0, "no camera picture")

        showControls()   // the app stays usable: controls, Settings
        XCTAssertTrue(app.buttons["pauseResume"].exists)
        openSettings()
        closeSettings()
        XCTAssertTrue(notice.exists, "the notice stays while access is off until dismissed (UIX-015-R7)")
        XCTAssertEqual(starts, "1", "the source is not restarted")
    }
}
