// TrailsUITests.swift — FX-009-T15 on the iOS Simulator: Settings → Trails is off by default with no Length slider;
// turning it on shows the Length slider at "0.20 s" (FX-009-R9, S7). One short test (owner rule 7: under 30 s); a
// relaunch would add about 10 s, so persistence is proven by `MotionFeedbackSettingTests.testOffByDefaultAndPersisted`.
// Simulator results are never device evidence.
import XCTest

@MainActor
final class TrailsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "trails"] + Self.noStore   // Settings opens at Trails (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    /// The controls hide 5 s after the last use and a tap toggles them, so the shared helper shows them freshly first.
    private func openSettings() {
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private var toggle: XCUIElement { app.switches["trailsToggle"] }
    private var length: XCUIElement { app.slider("trailsLengthSlider") }
    private var readout: XCUIElement { app.staticTexts["trailsLengthSliderValue"] }
    private func isOn(_ toggle: XCUIElement) -> Bool { (toggle.value as? String) == "1" }

    private func flip(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    func testTrailsToggleShowsLength() {
        launch()
        openSettings()
        XCTAssertTrue(app.reveal(toggle), "Trails is in Settings")
        XCTAssertFalse(isOn(toggle), "off by default")
        XCTAssertFalse(length.exists, "no Length slider while off")
        flip(toggle)
        XCTAssertTrue(poll(5) { self.isOn(self.toggle) })
        XCTAssertTrue(length.appears(within: 3) || app.reveal(length), "Length appears once on")
        XCTAssertEqual(length.label, "Length")
        XCTAssertEqual(readout.label, "0.20 s", "the default length")
    }
}
