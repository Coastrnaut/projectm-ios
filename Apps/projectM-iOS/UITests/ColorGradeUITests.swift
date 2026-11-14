// ColorGradeUITests.swift — FX-003-T16 on the iOS Simulator: Settings → Color shows five sliders at neutral with
// "Reset to neutral" disabled; moving the gain slider changes its readout and enables the reset, which returns the
// readout to "1.00×" (FX-003-R9, S6). One short test (owner rule 7: under 30 s); persistence across a relaunch is
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
        let common: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"]
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
        for id in ["colorTemperatureSlider", "colorLiftSlider", "colorGammaSlider", "colorSaturationSlider"] {
            XCTAssertTrue(app.slider(id).exists, "\(id) is in the section")
        }
        XCTAssertEqual(gain.label, "Gain")
        XCTAssertEqual(gainReadout.label, "1.00\u{00D7}", "neutral by default")
        XCTAssertTrue(app.reveal(reset))
        XCTAssertFalse(reset.isEnabled, "nothing to reset at neutral")
        XCTAssertTrue(app.reveal(gain))
        gain.dragSlider(from: 0.33, to: 0.9)   // 1.0 on 0.5…2 sits at one third
        XCTAssertTrue(poll(5) { self.gainReadout.label != "1.00\u{00D7}" }, "readout: \(gainReadout.label)")
        XCTAssertTrue(app.reveal(reset))
        XCTAssertTrue(poll(5) { self.reset.isEnabled }, "reset enabled once graded")
        reset.tap()
        XCTAssertTrue(poll(5) { self.gainReadout.label == "1.00\u{00D7}" }, "readout after reset: \(gainReadout.label)")
        XCTAssertFalse(reset.isEnabled)
    }
}
