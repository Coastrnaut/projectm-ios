// DisplayCalibrationUITests.swift — OUT-009-T13 on the iOS Simulator: with the fake external display
// (`-uitestExternalDisplay`), Settings › External Display › Color calibration… opens the editor; a drag of Gamma
// (ACC-005's slider) stores a custom calibration that the visual on the display applies
// (hidden `calibrationProbe`: the stored values and the display's summary); Reset returns to the identity, and Done
// keeps it (hidden `externalCalibration` probe). Simulator results are never device evidence (OUT-009-T14 is).
// Owner rule 7: under 30 s.
import XCTest

@MainActor
final class DisplayCalibrationUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var editorProbe: String { (app.descendants(matching: .any)["calibrationProbe"].firstMatch.value as? String) ?? "nil" }
    private var displayProbe: String { (app.descendants(matching: .any)["externalCalibration"].firstMatch.value as? String) ?? "nil" }

    func testTheEditorCalibratesTheDisplayAndResets() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestExternalDisplay", "-uitestSettingsSection", "externalDisplay"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(poll(5) { self.displayProbe.hasPrefix("cal=identity") }, "identity: \(displayProbe)")

        app.tapFreshControl("settings")   // retries when the controls auto-hide mid-tap
        let row = app.buttons["externalCalibrationButton"]
        XCTAssertTrue(app.reveal(row), "Color calibration… is reachable")
        row.tap()
        let gamma = app.slider("calibrationGamma")
        XCTAssertTrue(gamma.appears(within: 10), "the editor is open")
        XCTAssertFalse(app.buttons["calibrationReset"].isEnabled, "Reset is off at the identity")

        // 1.0 on 0.5…2.5 sits at one quarter; a drag can be lost under load, so retry until it lands.
        for _ in 0..<3 where !editorProbe.contains("|cal=custom") {
            gamma.dragSlider(from: 0.25, to: 0.5)
            _ = poll(2) { self.editorProbe.contains("|cal=custom") }
        }
        XCTAssertTrue(poll(3) { self.editorProbe.contains("|cal=custom applied=yes") },
                      "a custom calibration, applied by the visual on the display: \(editorProbe)")

        app.buttons["calibrationReset"].tap()
        XCTAssertTrue(poll(3) { self.editorProbe.hasPrefix("1,1,1,1|cal=identity") }, "reset: \(editorProbe)")
        app.buttons["calibrationDone"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(poll(5) { self.displayProbe.hasPrefix("cal=identity") }, "Done keeps the identity: \(displayProbe)")
    }
}
