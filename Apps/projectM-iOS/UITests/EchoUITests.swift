// EchoUITests.swift — FX-010-T15 on the iOS Simulator: Settings → Echo is off by default with no sliders; turning it on
// shows Echoes at "3", Delay at "100 ms" and Fade at "0.60"; dragging Echoes to the end reads "4", the cap (FX-010-R12,
// S6). One short test (owner rule 7: under 30 s); persistence across a relaunch is proven by
// `EchoSettingTests.testOffByDefaultPersistedAndCapped`. Simulator results are never device evidence.
import XCTest

@MainActor
final class EchoUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "echo"] + Self.noStore   // Settings opens at Echo (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var toggle: XCUIElement { app.switches["echoToggle"] }
    private var count: XCUIElement { app.slider("echoCountSlider") }
    private func isOn(_ toggle: XCUIElement) -> Bool { (toggle.value as? String) == "1" }

    private func flip(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    func testEchoControls() {
        launch()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(toggle), "Echo is in Settings")
        XCTAssertFalse(isOn(toggle), "off by default")
        XCTAssertFalse(count.exists, "no sliders while off")
        flip(toggle)
        XCTAssertTrue(poll(5) { self.isOn(self.toggle) })
        XCTAssertTrue(count.appears(within: 3) || app.reveal(count), "Echoes appears once on")
        XCTAssertEqual(app.staticTexts["echoCountSliderValue"].label, "3", "the default count")
        XCTAssertTrue(app.staticTexts["echoDelaySliderValue"].exists || app.reveal(app.staticTexts["echoDelaySliderValue"]))
        XCTAssertEqual(app.staticTexts["echoDelaySliderValue"].label, "100 ms")
        XCTAssertEqual(app.staticTexts["echoDecaySliderValue"].label, "0.60")
        count.dragSlider(from: 0.67, to: 1)
        XCTAssertTrue(poll(3) { self.app.staticTexts["echoCountSliderValue"].label == "4" }, "capped at 4")
    }
}
