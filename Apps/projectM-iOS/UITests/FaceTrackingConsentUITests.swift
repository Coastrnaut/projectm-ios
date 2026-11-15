// FaceTrackingConsentUITests.swift — CAM-009-T12 on the iOS Simulator with the stand-in camera and a stand-in face
// detector (`-uitestCamera granted -uitestFaceDetector stub`, DEBUG only): turning Face tracking on shows the
// explanation sheet before anything runs; Cancel leaves the switch off; Confirm turns it on (CAM-009-R1, R2; S5).
// Simulator results are never device evidence; real faces are CAM-009-T16 on D1.
import XCTest

@MainActor
final class FaceTrackingConsentUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var toggle: XCUIElement { app.switches["cameraFaceTrackingToggle"] }
    private var confirm: XCUIElement { app.buttons["faceTrackingConfirm"] }
    private var cancel: XCUIElement { app.buttons["faceTrackingCancel"] }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func flip(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    private func toggleValue() -> String { (toggle.value as? String) ?? "" }

    /// The sheet comes before activation; Cancel leaves it off; Confirm turns it on.
    func testConsentSheetPrecedesFaceTracking() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestCamera", "granted", "-uitestFaceDetector", "stub"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow("Camera")
        XCTAssertTrue(app.reveal(row), "the Camera visual row")
        row.tap()
        XCTAssertTrue(app.reveal(toggle), "the Face tracking switch")
        XCTAssertEqual(toggleValue(), "0", "off by default")

        flip(toggle)
        XCTAssertTrue(cancel.appears(within: 5), "the explanation sheet appears first")
        XCTAssertTrue(confirm.exists)
        cancel.tap()
        XCTAssertTrue(poll(3) { !self.cancel.exists }, "the sheet closes")
        XCTAssertEqual(toggleValue(), "0", "Cancel leaves face tracking off")

        flip(toggle)
        XCTAssertTrue(confirm.appears(within: 5))
        confirm.tap()
        XCTAssertTrue(poll(3) { self.toggleValue() == "1" }, "Confirm turns it on")
    }
}
