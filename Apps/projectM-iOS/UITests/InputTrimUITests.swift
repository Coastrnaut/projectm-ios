// InputTrimUITests.swift — AUD-008-T10 on the iOS Simulator: Settings → Audio Analysis → Input trim set
// to +24 dB persists across a relaunch, and "Reset to 0 dB" returns it to 0 dB (AUD-008 User Story 1;
// AUD-008-R6, R8, R9; S6). One short test (owner rule 7: under 30 s).
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class InputTrimUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) {
        XCUIDevice.shared.orientation = .portrait
        let resetArguments: [String] = reset ? ["-uitestResetNotice"] : []
        let common: [String] = ["-uitestDiagnostics", "-autostart", "inAppPlayback",
                                "-uitestSettingsSection", "trim"]   // Settings opens at Input trim (owner rule 7)
        app.launchArguments = resetArguments + common + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func openSettings() {
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private var slider: XCUIElement { app.slider("inputTrimSlider") }
    private var readout: XCUIElement { app.staticTexts["inputTrimValue"] }

    func testTrimPersistsAcrossRelaunchAndResets() {
        launch(reset: true)
        openSettings()
        XCTAssertTrue(app.reveal(slider), "Input trim is in Settings")
        XCTAssertEqual(readout.label, "0 dB", "0 dB by default")
        // XCUITest's slider drag lands only within a few steps of a mid position (measured: 0.5 gave
        // +8 dB, corrections oscillated), so the test drags to the end stop: exactly +24 dB.
        slider.dragSlider(from: 12.0 / 36.0, to: 1)   // 0 dB on −12…+24; ACC-005: dragged by touch
        XCTAssertTrue(poll(5) { self.readout.label == "+24 dB" }, "readout: \(readout.label)")
        XCTAssertEqual(slider.value as? String, "plus 24 decibels", "VoiceOver reads the signed value (AUD-008-R9, ACC-005-R2)")
        app.terminate()

        launch(reset: false)
        openSettings()
        XCTAssertTrue(app.reveal(slider))
        XCTAssertEqual(readout.label, "+24 dB", "the trim persisted")
        let reset = app.buttons["inputTrimReset"]
        XCTAssertEqual(reset.label, "Reset to 0 dB")
        reset.tap()
        XCTAssertTrue(poll(5) { self.readout.label == "0 dB" }, "reset: \(readout.label)")
        XCTAssertEqual(slider.value as? String, "0 decibels")
    }
}
