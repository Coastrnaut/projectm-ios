// ColorGradeUITests.swift — FX-003-T16 on the iOS Simulator: Settings → Color shows five sliders at neutral with
// "Reset to neutral" disabled; moving the gain slider changes its readout and enables the reset, which returns the
// readout to "1.00×" (FX-003-R9, S6); FX-004-T09: the Hue slider is there too, at "0°", and the reset covers it. One short test (owner rule 7: under 30 s); persistence across a relaunch is
// proven by `ColorGradeSettingTests.testNeutralByDefaultAndPersisted`. Simulator results are never device evidence.
// FX-005-T10: the Contrast picker starts at Linear with no strength slider; choosing S-curve shows the strength at "50%"
// and enables the reset, which returns the picker to Linear and hides the slider (one short test).
// FX-013-T12: the Posterize switch starts off with no levels slider; turning it on shows "6 levels" and the Dither
// switch and enables the reset, which turns it off again (one short test).
import XCTest

@MainActor
final class ColorGradeUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        let common: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                                 "-uitestSettingsSection", "color"]   // Settings opens at Color (owner rule 7)
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

    private var gain: XCUIElement { app.slider("colorGainSlider") }
    private var gainReadout: XCUIElement { app.staticTexts["colorGainSliderValue"] }
    private var reset: XCUIElement { app.buttons["colorResetButton"] }

    func testColorSectionAdjustAndReset() {
        launch()
        openSettings()
        XCTAssertTrue(app.reveal(gain), "Gain is in Settings → Color")
        for id in ["colorTemperatureSlider", "colorLiftSlider", "colorGammaSlider", "colorSaturationSlider", "colorHueSlider"] {
            XCTAssertTrue(app.slider(id).exists, "\(id) is in the section")
        }
        XCTAssertEqual(app.slider("colorHueSlider").label, "Hue")
        XCTAssertEqual(app.staticTexts["colorHueSliderValue"].label, "0\u{00B0}", "hue neutral by default")
        XCTAssertEqual(gain.label, "Gain")
        XCTAssertEqual(gainReadout.label, "1.00\u{00D7}", "neutral by default")
        XCTAssertTrue(app.reveal(reset))
        XCTAssertFalse(reset.isEnabled, "nothing to reset at neutral")
        XCTAssertTrue(app.reveal(gain, down: true), "back up to Gain after revealing the reset")
        gain.dragSlider(from: 0.33, to: 0.9)   // 1.0 on 0.5…2 sits at one third
        XCTAssertTrue(poll(5) { self.gainReadout.label != "1.00\u{00D7}" }, "readout: \(gainReadout.label)")
        XCTAssertTrue(app.reveal(reset))
        XCTAssertTrue(poll(5) { self.reset.isEnabled }, "reset enabled once graded")
        reset.tap()
        XCTAssertTrue(poll(5) { self.gainReadout.label == "1.00\u{00D7}" }, "readout after reset: \(gainReadout.label)")
        XCTAssertFalse(reset.isEnabled)
        XCTAssertEqual(app.staticTexts["colorHueSliderValue"].label, "0\u{00B0}", "the reset covers the hue")
    }

    // MARK: - FX-005: Contrast

    private var contrastPicker: XCUIElement { app.segmentedControls["colorContrastPicker"] }
    private var strengthReadout: XCUIElement { app.staticTexts["colorContrastStrengthSliderValue"] }

    func testContrastPickerShowsStrengthAndResets() {
        launch()
        openSettings()
        XCTAssertTrue(app.reveal(contrastPicker), "Contrast is in Settings → Color")
        XCTAssertTrue(contrastPicker.buttons["Linear"].isSelected, "Linear by default")
        XCTAssertFalse(app.slider("colorContrastStrengthSlider").exists, "no strength while Linear")
        contrastPicker.buttons["S-curve"].tap()
        XCTAssertTrue(strengthReadout.appears(within: 5), "the strength appears once a curve is chosen")
        XCTAssertEqual(strengthReadout.label, "50%")
        XCTAssertEqual(app.slider("colorContrastStrengthSlider").label, "Contrast strength")
        XCTAssertTrue(app.reveal(reset))
        XCTAssertTrue(poll(5) { self.reset.isEnabled }, "a curve is not neutral")
        reset.tap()
        XCTAssertTrue(poll(5) { !self.reset.isEnabled }, "reset to neutral")
        XCTAssertTrue(app.reveal(contrastPicker, down: true))
        XCTAssertTrue(poll(5) { self.contrastPicker.buttons["Linear"].isSelected }, "the reset covers the curve")
        XCTAssertFalse(app.slider("colorContrastStrengthSlider").exists)
    }

    // MARK: - FX-013: Posterize

    private var posterizeToggle: XCUIElement { app.switches["colorPosterizeToggle"] }
    private var levelsReadout: XCUIElement { app.staticTexts["colorPosterizeLevelsSliderValue"] }

    private func isOn(_ element: XCUIElement) -> Bool { (element.value as? String) == "1" }

    func testPosterizeSwitchShowsLevelsAndResets() {
        launch()
        openSettings()
        XCTAssertTrue(app.reveal(posterizeToggle), "Posterize is in Settings → Color")
        XCTAssertFalse(isOn(posterizeToggle), "off by default")
        XCTAssertFalse(app.slider("colorPosterizeLevelsSlider").exists, "no levels while off")
        posterizeToggle.switches.firstMatch.exists ? posterizeToggle.switches.firstMatch.tap() : posterizeToggle.tap()
        XCTAssertTrue(levelsReadout.appears(within: 5), "the levels appear once posterize is on")
        XCTAssertEqual(levelsReadout.label, "6 levels")
        XCTAssertEqual(app.slider("colorPosterizeLevelsSlider").label, "Posterize levels")
        XCTAssertTrue(app.switches["colorPosterizeDitherToggle"].exists, "the Dither switch is shown")
        XCTAssertTrue(app.reveal(reset))
        XCTAssertTrue(poll(5) { self.reset.isEnabled }, "posterize is not neutral")
        reset.tap()
        XCTAssertTrue(poll(5) { !self.reset.isEnabled }, "reset to neutral")
        XCTAssertTrue(app.reveal(posterizeToggle, down: true))
        XCTAssertTrue(poll(5) { !self.isOn(self.posterizeToggle) }, "the reset turns posterize off")
        XCTAssertFalse(app.slider("colorPosterizeLevelsSlider").exists)
    }
}
