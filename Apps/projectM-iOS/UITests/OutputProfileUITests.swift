// OutputProfileUITests.swift — OUT-014-T11 on the iOS Simulator: with the fake external display (`-uitestExternalDisplay`)
// and a stored custom calibration, Settings › External Display › Export output profile… (DEBUG
// `-uitestOutputProfileSimulation`: the document is kept instead of the system file export), Color calibration… › Reset
// (the display shows the identity), then Import output profile… (the kept document instead of the picker): the same
// display class applies without a warning and the display's calibration is the exported one again (hidden
// `externalCalibration` probe). Simulator results are never device evidence (OUT-014-T13 is). Owner rule 7: under 30 s.
import XCTest

@MainActor
final class OutputProfileUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var editorProbe: String { (app.descendants(matching: .any)["calibrationProbe"].firstMatch.value as? String) ?? "nil" }
    private var displayProbe: String { (app.descendants(matching: .any)["externalCalibration"].firstMatch.value as? String) ?? "nil" }
    private var message: String { app.staticTexts["outputProfileMessage"].firstMatch.label }

    private func tapRow(_ identifier: String) {
        let row = app.buttons[identifier]
        XCTAssertTrue(app.reveal(row), "\(identifier) is reachable")
        row.tap()
    }

    func testExportResetImportRestoresTheCalibration() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestExternalDisplay", "-uitestSettingsSection", "externalDisplay",
                               "-uitestOutputProfileSimulation",
                               "-settings.externalDisplay.calibration", "1.5,0.8,1,1.2"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(poll(5) { self.displayProbe.hasSuffix("values=1.5,0.8,1,1.2") }, "custom at launch: \(displayProbe)")

        app.tapFreshControl("settings")
        tapRow("outputProfileExport")
        XCTAssertTrue(poll(3) { self.message == "Exported output profile." }, "exported: \(message)")

        tapRow("externalCalibrationButton")
        let reset = app.buttons["calibrationReset"]
        XCTAssertTrue(reset.appears(within: 10), "the editor is open")
        reset.tap()
        XCTAssertTrue(poll(3) { self.editorProbe.hasPrefix("1,1,1,1|cal=identity") }, "reset: \(editorProbe)")
        app.buttons["calibrationDone"].tap()

        tapRow("outputProfileImport")
        XCTAssertTrue(poll(3) { self.message == "Applied output profile." }, "same display class, no warning: \(message)")
        XCTAssertFalse(app.buttons["outputProfileApplyAnyway"].exists, "no different-display warning")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(poll(5) { self.displayProbe.hasSuffix("values=1.5,0.8,1,1.2") }, "restored: \(displayProbe)")
    }
}
