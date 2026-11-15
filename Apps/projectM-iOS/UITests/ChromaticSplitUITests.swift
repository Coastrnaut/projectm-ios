// ChromaticSplitUITests.swift — FX-006-T15 on the iOS Simulator: Settings → Chromatic split is off by default with no
// sliders; turning it on shows Amount at "0.5%" and Angle at "0°"; moving Amount to the end reads "2.0%"; Radial hides
// Angle (FX-006-R8, S6). One short test (owner rule 7: under 30 s); persistence across a relaunch is proven by
// `ChromaticSplitSettingTests.testOffByDefaultPersistedAndClamped`. Simulator results are never device evidence.
import XCTest

@MainActor
final class ChromaticSplitUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "chromatic"] + Self.noStore   // Settings opens at the split (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var toggle: XCUIElement { app.switches["chromaticToggle"] }
    private var radial: XCUIElement { app.switches["chromaticRadialToggle"] }
    private var amount: XCUIElement { app.slider("chromaticAmountSlider") }
    private var angle: XCUIElement { app.slider("chromaticAngleSlider") }
    private func isOn(_ toggle: XCUIElement) -> Bool { (toggle.value as? String) == "1" }

    private func flip(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    func testChromaticSplitControls() {
        launch()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(toggle), "Chromatic split is in Settings")
        XCTAssertFalse(isOn(toggle), "off by default")
        XCTAssertFalse(amount.exists, "no sliders while off")
        flip(toggle)
        XCTAssertTrue(poll(5) { self.isOn(self.toggle) })
        XCTAssertTrue(amount.appears(within: 3) || app.reveal(amount), "Amount appears once on")
        XCTAssertEqual(app.staticTexts["chromaticAmountSliderValue"].label, "0.5%", "the default amount")
        XCTAssertTrue(angle.exists || app.reveal(angle))
        XCTAssertEqual(app.staticTexts["chromaticAngleSliderValue"].label, "0\u{00B0}")
        amount.dragSlider(from: 0.25, to: 1)
        XCTAssertTrue(poll(3) { self.app.staticTexts["chromaticAmountSliderValue"].label == "2.0%" }, "capped at 2%")
        XCTAssertTrue(radial.exists || app.reveal(radial))
        flip(radial)
        XCTAssertTrue(poll(3) { !self.angle.exists }, "Radial hides Angle")
    }
}
