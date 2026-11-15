// DirectionalBlurUITests.swift — FX-007-T15 on the iOS Simulator: Settings → Directional blur is off by default with no
// sliders; turning it on shows Radius at "0.5%" and Angle at "0°"; moving Radius to the end reads "2.0%" (FX-007-R9,
// S7). One short test (owner rule 7: under 30 s); persistence across a relaunch is proven by
// `DirectionalBlurSettingTests.testOffByDefaultPersistedAndClamped`. Simulator results are never device evidence.
import XCTest

@MainActor
final class DirectionalBlurUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "directionalBlur"] + Self.noStore   // Settings opens at the blur (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var toggle: XCUIElement { app.switches["directionalBlurToggle"] }
    private var radius: XCUIElement { app.slider("directionalBlurRadiusSlider") }
    private var angle: XCUIElement { app.slider("directionalBlurAngleSlider") }
    private func isOn(_ toggle: XCUIElement) -> Bool { (toggle.value as? String) == "1" }

    private func flip(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    func testDirectionalBlurControls() {
        launch()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(toggle), "Directional blur is in Settings")
        XCTAssertFalse(isOn(toggle), "off by default")
        XCTAssertFalse(radius.exists, "no sliders while off")
        flip(toggle)
        XCTAssertTrue(poll(5) { self.isOn(self.toggle) })
        XCTAssertTrue(radius.appears(within: 3) || app.reveal(radius), "Radius appears once on")
        XCTAssertEqual(app.staticTexts["directionalBlurRadiusSliderValue"].label, "0.5%", "the default radius")
        XCTAssertTrue(angle.exists || app.reveal(angle))
        XCTAssertEqual(app.staticTexts["directionalBlurAngleSliderValue"].label, "0\u{00B0}")
        radius.dragSlider(from: 0.25, to: 1)
        XCTAssertTrue(poll(3) { self.app.staticTexts["directionalBlurRadiusSliderValue"].label == "2.0%" }, "capped at 2%")
    }
}
