// ColorGradeUITests.swift — FX-003-T16 on the iOS Simulator: Settings → Color shows five sliders at neutral with
// "Reset to neutral" disabled; moving the gain slider changes its readout and enables the reset, which returns the
// readout to "1.00×" (FX-003-R9, S6); FX-004-T09: the Hue slider is there too, at "0°", and the reset covers it. One short test (owner rule 7: under 30 s); persistence across a relaunch is
// proven by `ColorGradeSettingTests.testNeutralByDefaultAndPersisted`. Simulator results are never device evidence.
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
}
