// RadialBlurUITests.swift — FX-008-T15 on the iOS Simulator: Settings → Radial blur is off by default with no sliders;
// turning it on shows Strength at "10%" and Focus X/Y at "50%"; moving Strength to the end reads "25%" (FX-008-R8, S6).
// One short test (owner rule 7: under 30 s); persistence across a relaunch is proven by
// `RadialBlurSettingTests.testOffByDefaultPersistedAndClamped`. Simulator results are never device evidence.
import XCTest

@MainActor
final class RadialBlurUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "radialBlur"] + Self.noStore   // Settings opens at the blur (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var toggle: XCUIElement { app.switches["radialBlurToggle"] }
    private var strength: XCUIElement { app.slider("radialBlurStrengthSlider") }
    private func isOn(_ toggle: XCUIElement) -> Bool { (toggle.value as? String) == "1" }

    private func flip(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    func testRadialBlurControls() {
        launch()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(toggle), "Radial blur is in Settings")
        XCTAssertFalse(isOn(toggle), "off by default")
        XCTAssertFalse(strength.exists, "no sliders while off")
        flip(toggle)
        XCTAssertTrue(poll(5) { self.isOn(self.toggle) })
        XCTAssertTrue(strength.appears(within: 3) || app.reveal(strength), "Strength appears once on")
        XCTAssertEqual(app.staticTexts["radialBlurStrengthSliderValue"].label, "10%", "the default strength")
        let focusX: XCUIElement = app.slider("radialBlurFocusXSlider")
        XCTAssertTrue(focusX.exists || app.reveal(focusX))
        XCTAssertEqual(app.staticTexts["radialBlurFocusXSliderValue"].label, "50%", "the focus starts at the centre")
        strength.dragSlider(from: 0.4, to: 1)
        XCTAssertTrue(poll(3) { self.app.staticTexts["radialBlurStrengthSliderValue"].label == "25%" }, "capped at 25%")
    }
}
