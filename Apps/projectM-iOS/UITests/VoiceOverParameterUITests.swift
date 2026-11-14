// VoiceOverParameterUITests.swift — ACC-005-T11 on the iOS Simulator (S2). XCTest's
// `XCUIElement.increment()`/`decrement()` exist only on macOS, and on iOS
// `adjust(toNormalizedSliderPosition:)` drags by touch and never reaches the adjustable action
// (research D2). With `-uitestAccessibilityActions` (DEBUG), each accessible slider gets two probe
// buttons; a tap finds the slider's element in the app's accessibility tree by identifier and calls
// `accessibilityIncrement()` / `accessibilityDecrement()` on it, the UIAccessibility entry points
// VoiceOver's swipe up and down call (UITestAccessibilityActionProbe.swift).
//
// The glow intensity starts at 50 %: our step gives 55 % ("55 percent"); the system's own slider step
// (10 % of the range) would give 60 %, so the value proves the app's action ran. The glow radius's
// decrement from 2.0 % gives "1.5 percent" (one 0.5 % step). A relaunch reads both back (persisted
// setting). Both sliders sit near the top of Settings (one short scroll per launch, instead of the
// input trim's several); the trim's spoken decibels are covered by InputTrimUITests and unit tests.
// Run it on a simulator no other lane uses: installing another checkout's test runner on the same
// simulator SIGKILLs this runner ("Test crashed with signal kill", integration 2026-11-14).
// One short test (owner rule 7: under 30 s). Simulator results are never device evidence.
import XCTest

@MainActor
final class VoiceOverParameterUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) {
        XCUIDevice.shared.orientation = .portrait
        let resetArguments: [String] = reset ? ["-uitestResetNotice"] : []
        // The scene autosave restores the glow at launch, so its 1 s quiet time is shortened and the test
        // waits for the commit before terminating (a step right before a kill was otherwise lost).
        let common: [String] = ["-uitestDiagnostics", "-uitestAccessibilityActions", "-uitestSceneAutosaveQuiet", "0.1",
                                "-autostart", "inAppPlayback"]
        app.launchArguments = resetArguments + common + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func openSettings() {
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private var intensity: XCUIElement { app.slider("glowIntensitySlider") }
    private var radius: XCUIElement { app.slider("glowRadiusSlider") }
    private var glowToggle: XCUIElement { app.switches["glowToggle"] }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    /// The accessibility increment (or decrement) of the slider `id`, through its probe button.
    private func step(_ id: String, up: Bool) {
        let suffix: String = up ? ".uitestIncrement" : ".uitestDecrement"
        let probe = app.buttons[id + suffix]
        XCTAssertTrue(probe.appears(within: 10) && (probe.isHittable || app.reveal(probe)), "probe \(id + suffix)")
        probe.tap()
        XCTAssertTrue(poll(3) { (probe.value as? String ?? "").hasPrefix("performed") }, "probe result: \(probe.value ?? "nil")")
    }

    func testIncrementAndDecrementChangeTheStoredSettingByOneStep() {
        launch(reset: true)
        openSettings()
        let row = app.visualRow("Circular Spectrum")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        XCTAssertTrue(glowToggle.appears(within: 2) || app.reveal(glowToggle))
        glowToggle.switches.firstMatch.exists ? glowToggle.switches.firstMatch.tap() : glowToggle.tap()
        XCTAssertTrue(intensity.appears(within: 10))   // reading the value needs no scroll
        XCTAssertEqual(value(intensity), "50 percent")
        step("glowIntensitySlider", up: true)
        XCTAssertTrue(poll(5) { self.value(self.intensity) == "55 percent" }, "one 5 % step: \(value(intensity))")

        // The radius sits just below, so the test never scrolls (each scroll costs about 3.5 s).
        XCTAssertTrue(app.reveal(radius))   // the row below is built only once it scrolls into view
        XCTAssertEqual(value(radius), "2.0 percent")
        step("glowRadiusSlider", up: false)
        XCTAssertTrue(poll(5) { self.value(self.radius) == "1.5 percent" }, "one 0.5 % step: \(value(radius))")
        app.navigationBars["Settings"].buttons["Done"].tap()
        let autosave = app.staticTexts["sceneAutosave"]
        XCTAssertTrue(poll(5) { (autosave.value as? String ?? "").contains("pending=0") },
                      "the scene autosave committed the steps: \(autosave.value ?? "nil")")
        app.terminate()

        launch(reset: false)
        openSettings()
        XCTAssertTrue(intensity.appears(within: 10))   // reading the value needs no scroll
        XCTAssertEqual(value(intensity), "55 percent", "the stepped intensity persisted")
        XCTAssertTrue(app.reveal(radius))   // the row below is built only once it scrolls into view
        XCTAssertEqual(value(radius), "1.5 percent", "the stepped radius persisted")
    }
}
