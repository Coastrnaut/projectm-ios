// CameraLensUITests.swift — CAM-003-T09 on the iOS Simulator with the stand-in camera
// (`-uitestCamera granted -uitestCameraLenses <list> -uitestCameraLensFails <list>`, DEBUG only): the
// roadmap acceptance "Unavailable lens is hidden; switching never crashes active session" in the app
// (CAM-003-R2, R6, R11; S1, S2). Simulator results are never device evidence; real lens switching is
// CAM-003-T11 on D1.
import XCTest

@MainActor
final class CameraLensUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var cameraVisual: XCUIElement { app.descendants(matching: .any)["cameraVisual"].firstMatch }
    private var positionPicker: XCUIElement { app.segmentedControls["cameraPositionPicker"] }
    private var lensPicker: XCUIElement { app.segmentedControls["cameraLensPicker"] }

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

    /// Launches with the stand-in's lenses, chooses Camera and waits for the camera to be live.
    private func launchWithCamera(lenses: String, failing: String? = nil) {
        XCUIDevice.shared.orientation = .portrait
        var arguments: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                                   "-uitestCamera", "granted", "-uitestCameraLenses", lenses]
        if let failing { arguments += ["-uitestCameraLensFails", failing] }
        app.launchArguments = arguments + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()
        let row = app.visualRow("Camera")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        XCTAssertTrue(app.reveal(positionPicker), "the Camera section appears")
    }

    /// S1: one back lens → no Lens row at all (hidden, not disabled).
    func testSingleLensDeviceShowsNoLensRow() {
        launchWithCamera(lenses: "wide")
        XCTAssertFalse(lensPicker.exists, "one lens: no Lens row")
        XCTAssertFalse(app.buttons["Ultra Wide"].exists)
        XCTAssertFalse(app.buttons["Telephoto"].exists)
    }

    /// S1, S2: three lenses → exactly three segments; switching through them while the camera runs,
    /// including to a lens that cannot be opened, keeps the camera live and the source running.
    func testSwitchingLensesKeepsTheCameraLive() {
        launchWithCamera(lenses: "wide,ultraWide,telephoto", failing: "telephoto")
        // Choosing Camera starts the stand-in at once (the visualizer stays under the Settings sheet),
        // so every switch below happens on the running session; the app tests check that directly.
        XCTAssertTrue(app.reveal(lensPicker), "the Lens row is shown")
        XCTAssertEqual(lensPicker.buttons.count, 3)
        XCTAssertEqual(lensPicker.buttons.allElementsBoundByIndex.map(\.label), ["Ultra Wide", "Wide", "Telephoto"])
        XCTAssertTrue(lensPicker.buttons["Wide"].isSelected, "Wide by default")
        lensPicker.buttons["Ultra Wide"].tap()
        XCTAssertTrue(poll(3) { self.lensPicker.buttons["Ultra Wide"].isSelected }, "Ultra Wide chosen")
        lensPicker.buttons["Telephoto"].tap()   // its input cannot be opened
        XCTAssertTrue(poll(3) { self.lensPicker.buttons["Ultra Wide"].isSelected }, "failing lens: back to the previous one")
        lensPicker.buttons["Wide"].tap()
        XCTAssertTrue(poll(3) { self.lensPicker.buttons["Wide"].isSelected }, "Wide chosen")
        closeSettings()
        XCTAssertTrue(poll(10) { (self.cameraVisual.value as? String) == "Live" }, "still live: \(String(describing: cameraVisual.value))")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
