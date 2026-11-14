// OscilloscopeUITests.swift — VIS-003-T14 on the iOS Simulator: choosing Oscilloscope, a thick line and
// the 40 ms window in Settings, the visual and its window persisting across a relaunch, Bars not
// offered, the source started once (VIS-003 User Story 1; VIS-003-R10, R11, R13; S6). One short test
// (owner rule 7: under 30 s).
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class OscilloscopeUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var oscilloscope: XCUIElement { app.descendants(matching: .any)["oscilloscope"].firstMatch }

    private func openSettings() {
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    private var value: String { oscilloscope.value as? String ?? "" }

    func testChoosingOscilloscopeThickAnd40msPersists() {
        launch(reset: true)
        openSettings()
        let row = app.buttons["visual.oscilloscope"]
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let line = app.segmentedControls["oscilloscopeLinePicker"]
        let window = app.segmentedControls["oscilloscopeWindowPicker"]
        XCTAssertTrue(line.appears(within: 5), "Line offered for the oscilloscope")
        XCTAssertTrue(line.buttons["Medium"].isSelected, "Medium by default")
        XCTAssertTrue(window.buttons["20 ms"].isSelected, "20 ms by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply to the oscilloscope")
        line.buttons["Thick"].tap()
        window.buttons["40 ms"].tap()
        XCTAssertTrue(line.buttons["Thick"].isSelected)
        closeSettings()
        XCTAssertTrue(oscilloscope.appears(within: 10), "the oscilloscope is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("40 ms") }, "40 ms: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
        app.terminate()

        launch(reset: false)
        XCTAssertTrue(oscilloscope.appears(within: 10), "the choice persisted")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("40 ms") }, "the window persisted: \(value)")
        // The line's persistence is checked by OscilloscopeAppTests; reopening Settings here would push
        // this test past its 30 s budget (the first Settings query alone takes about 8 s).
    }
}
