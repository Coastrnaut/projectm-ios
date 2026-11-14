// ChannelSelectionUITests.swift — AUD-009-T10 on the iOS Simulator: Settings → Analysis Channel shows
// Mix by default, read as "Stereo mix", and choosing Left updates the readout and the selection
// (AUD-009 User Story 1; AUD-009-R7, R8; S6). One short test (owner rule 7: under 30 s). The version
// with a relaunch took 26-30 s (two app launches of about 10 s each), too close to the budget, so
// persistence across a relaunch is proven by `ChannelSelectionSettingTests.testDefaultsToMixAndPersists`
// (a new store on the same defaults), as ANL-003 did. Simulator results are never device evidence
// (Constitution X).
import XCTest

@MainActor
final class ChannelSelectionUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        let common: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                                "-uitestSettingsSection", "channel"]   // Settings opens at Analysis channel (owner rule 7)
        app.launchArguments = common + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func openSettings() {
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private var picker: XCUIElement { app.segmentedControls["analysisChannelPicker"] }
    private var readout: XCUIElement { app.staticTexts["analysisChannelValue"] }

    func testChannelChoiceShowsInSettings() {
        launch()
        openSettings()
        XCTAssertTrue(app.reveal(picker), "Analysis channel is in Settings")
        XCTAssertEqual(readout.label, "Stereo mix", "Mix by default")
        let mix = picker.buttons["Stereo mix"]
        XCTAssertTrue(mix.exists, "the Mix segment is read as \"Stereo mix\" (AUD-009-R8)")
        XCTAssertTrue(mix.isSelected)
        picker.buttons["Left"].tap()
        XCTAssertTrue(poll(5) { self.readout.label == "Left" }, "readout: \(readout.label)")
        XCTAssertTrue(picker.buttons["Left"].isSelected)
        XCTAssertFalse(mix.isSelected)
    }
}
