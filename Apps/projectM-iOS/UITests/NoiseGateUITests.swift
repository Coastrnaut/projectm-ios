// NoiseGateUITests.swift — AUD-011-T09 on the iOS Simulator: Settings → Noise gate is off with the
// threshold slider disabled at "−50 dBFS"; turning it on enables the slider, and moving the slider
// changes the readout (AUD-011 User Story 2; AUD-011-R7, R10; S7). One short test (owner rule 7:
// under 30 s); persistence across a relaunch is proven by
// `NoiseGateSettingTests.testDefaultsAndPersistence` (a new store on the same defaults), as AUD-009
// did. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class NoiseGateUITests: XCTestCase {
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

    private var toggle: XCUIElement { app.switches["noiseGateToggle"] }
    private var slider: XCUIElement { app.sliders["noiseGateThresholdSlider"] }
    private var readout: XCUIElement { app.staticTexts["noiseGateThresholdValue"] }

    func testNoiseGateControlsInSettings() {
        launch()
        openSettings()
        XCTAssertTrue(app.reveal(slider), "Gate threshold is in Settings")
        XCTAssertTrue(app.reveal(toggle), "Noise gate is in Settings")
        XCTAssertEqual(toggle.value as? String, "0", "off by default")
        XCTAssertFalse(slider.isEnabled, "the threshold is disabled while off")
        XCTAssertEqual(readout.label, "\u{2212}50 dBFS")
        XCTAssertEqual(slider.label, "Gate threshold")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()   // the switch inside the row
        XCTAssertTrue(poll(5) { (self.toggle.value as? String) == "1" }, "toggle: \(String(describing: toggle.value))")
        XCTAssertTrue(poll(5) { self.slider.isEnabled }, "enabled once on")
        slider.adjust(toNormalizedSliderPosition: 0.9)
        XCTAssertTrue(poll(5) { self.readout.label != "\u{2212}50 dBFS" }, "readout: \(readout.label)")
    }
}
