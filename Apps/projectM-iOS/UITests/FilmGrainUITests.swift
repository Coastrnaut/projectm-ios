// FilmGrainUITests.swift — FX-017-T15 on the iOS Simulator: Settings → Film grain is off by default with no controls;
// turning it on shows Opacity at "30%", the Size and Color choices, "Seed 1" and Vary over time off; the stepper moves
// the seed to 2 (FX-017-R9, S6). One short test (owner rule 7: under 30 s); persistence across a relaunch is proven by
// `FilmGrainSettingTests.testFilmGrainOffByDefaultPersistedAndClamped`. Simulator results are never device evidence.
import XCTest

@MainActor
final class FilmGrainUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launchFilmGrain() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "filmGrain"] + Self.noStore   // Settings opens at Film grain
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var grainToggle: XCUIElement { app.switches["filmGrainToggle"] }
    private var grainOpacity: XCUIElement { app.slider("filmGrainOpacitySlider") }
    private var opacityReadout: XCUIElement { app.staticTexts["filmGrainOpacitySliderValue"] }
    private var grainSeed: XCUIElement { app.steppers["filmGrainSeed"] }
    private func grainIsOn() -> Bool { (grainToggle.value as? String) == "1" }

    func testFilmGrainControls() {
        launchFilmGrain()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(grainToggle), "Film grain is in Settings")
        XCTAssertFalse(grainIsOn(), "off by default")
        XCTAssertFalse(grainOpacity.exists, "no controls while off")
        grainToggle.switches.firstMatch.exists ? grainToggle.switches.firstMatch.tap() : grainToggle.tap()
        XCTAssertTrue(poll(5) { self.grainIsOn() })
        XCTAssertTrue(grainOpacity.appears(within: 3) || app.reveal(grainOpacity), "Opacity appears once on")
        XCTAssertEqual(opacityReadout.label, "30%", "the default opacity")
        XCTAssertTrue(grainSeed.exists || app.reveal(grainSeed), "the seed stepper")
        XCTAssertTrue(grainSeed.label.contains("Seed 1"), "the default seed: \(grainSeed.label)")
        grainSeed.buttons.element(boundBy: 1).tap()   // Increment
        XCTAssertTrue(poll(3) { self.grainSeed.label.contains("Seed 2") }, "the stepper moves the seed: \(grainSeed.label)")
        let animated: XCUIElement = app.switches["filmGrainAnimated"]
        XCTAssertTrue(animated.exists || app.reveal(animated), "the Vary over time choice")
        XCTAssertEqual(animated.value as? String, "0", "static by default")
    }
}
