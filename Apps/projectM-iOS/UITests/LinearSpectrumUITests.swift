// LinearSpectrumUITests.swift — VIS-002-T13 on the iOS Simulator: choosing Linear Spectrum and its
// orientation in Settings, both persisting across a relaunch, the source started once (VIS-002 User
// Story 1; VIS-002-R11 to R13; VIS-002-S6). One short test (owner rule 7: under 30 s). Simulator
// results are never device evidence (Constitution X).
import XCTest

@MainActor
final class LinearSpectrumUITests: XCTestCase {
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

    private var linearSpectrum: XCUIElement { app.descendants(matching: .any)["linearSpectrum"].firstMatch }

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

    private var value: String { linearSpectrum.value as? String ?? "" }

    func testChoosingLinearSpectrumAndHorizontalPersists() {
        launch(reset: true)
        openSettings()
        XCTAssertTrue(app.visualRow("Linear Spectrum").appears(within: 5))
        app.visualRow("Linear Spectrum").tap()
        let orientation = app.segmentedControls["orientationPicker"]
        XCTAssertTrue(orientation.appears(within: 5), "Orientation offered for the linear spectrum")
        XCTAssertTrue(orientation.buttons["Vertical"].isSelected, "vertical by default")
        XCTAssertTrue(app.segmentedControls["spacingPicker"].buttons["Narrow"].isSelected, "Narrow by default")
        XCTAssertTrue(app.segmentedControls["barsPicker"].exists, "Bars shared with the circular spectrum")
        orientation.buttons["Horizontal"].tap()
        closeSettings()
        XCTAssertTrue(linearSpectrum.appears(within: 10), "the linear spectrum is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Horizontal") }, "horizontal: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
        app.terminate()

        launch(reset: false)
        XCTAssertTrue(linearSpectrum.appears(within: 10), "the choice persisted")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Horizontal") }, "the orientation persisted: \(value)")
        openSettings()
        XCTAssertTrue(app.segmentedControls["orientationPicker"].buttons["Horizontal"].isSelected)
        closeSettings()
    }
}
