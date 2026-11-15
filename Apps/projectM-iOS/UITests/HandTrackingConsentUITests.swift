// HandTrackingConsentUITests.swift — CAM-010-T12 on the iOS Simulator with the stand-in camera and a stand-in hand
// detector (`-uitestCamera granted -uitestHandDetector stub`, DEBUG only): turning Hand tracking on shows its own
// explanation sheet before anything runs; Cancel leaves the switch off; Confirm turns it on (CAM-010-R1, R2; S6).
// Simulator results are never device evidence; real hands are CAM-010-T17 on D1.
import XCTest

@MainActor
final class HandTrackingConsentUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var toggle: XCUIElement { app.switches["cameraHandTrackingToggle"] }
    private var confirm: XCUIElement { app.buttons["handTrackingConfirm"] }
    private var cancel: XCUIElement { app.buttons["handTrackingCancel"] }

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
    func testConsentSheetPrecedesHandTracking() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestCamera", "granted", "-uitestHandDetector", "stub"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow("Camera")
        XCTAssertTrue(app.reveal(row), "the Camera visual row")
        row.tap()
        XCTAssertTrue(app.reveal(toggle), "the Hand tracking switch")
        XCTAssertEqual(toggleValue(), "0", "off by default")

        flip(toggle)
        XCTAssertTrue(cancel.appears(within: 5), "the explanation sheet appears first")
        XCTAssertTrue(confirm.exists)
        cancel.tap()
        XCTAssertTrue(poll(3) { !self.cancel.exists }, "the sheet closes")
        XCTAssertEqual(toggleValue(), "0", "Cancel leaves hand tracking off")

        flip(toggle)
        XCTAssertTrue(confirm.appears(within: 5))
        confirm.tap()
        XCTAssertTrue(poll(3) { self.toggleValue() == "1" }, "Confirm turns it on")
    }
}
