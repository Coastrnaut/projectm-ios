// NoiseFieldUITests.swift — VIS-013-T13 on the iOS Simulator: choosing Noise Field in Settings, Frequency offered with
// Medium selected plus Octaves and New Seed, Bars not offered, choosing High, the visual shown with "High frequency" in
// its value and the source started once (VIS-013 User Story 3; VIS-013-R9, R12; S6). One short test (owner rule 7:
// under 30 s); persistence across a relaunch is NoiseFieldAppTests' unit test.
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class NoiseFieldUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var field: XCUIElement { app.descendants(matching: .any)["noiseField"].firstMatch }
    private var value: String { field.value as? String ?? "" }

    func testChoosingNoiseFieldAndHighFrequency() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.noiseField"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let frequency = app.segmentedControls["noiseFieldFrequencyPicker"]
        if !frequency.appears(within: 2) { app.reveal(frequency) }
        XCTAssertTrue(frequency.appears(within: 5), "Frequency offered for the field")
        XCTAssertTrue(frequency.buttons["Medium"].isSelected, "Medium by default")
        XCTAssertTrue(app.buttons["noiseFieldNewSeedButton"].exists || app.descendants(matching: .any)["noiseFieldOctavesStepper"].exists,
                      "Octaves and New Seed offered")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply to the field")
        frequency.buttons["High"].tap()
        XCTAssertTrue(frequency.buttons["High"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(field.appears(within: 10), "the field is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("High frequency") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
