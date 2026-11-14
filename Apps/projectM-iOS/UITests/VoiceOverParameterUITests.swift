// VoiceOverParameterUITests.swift — ACC-005-T11 on the iOS Simulator (S2). XCTest's
// `XCUIElement.increment()`/`decrement()` exist only on macOS, and on iOS
// `adjust(toNormalizedSliderPosition:)` drags by touch and never reaches the adjustable action
// (research D2). With `-uitestAccessibilityActions` (DEBUG), each accessible slider gets two probe
// buttons; a tap finds the slider's element in the app's accessibility tree by identifier and calls
// `accessibilityIncrement()` / `accessibilityDecrement()` on it, the UIAccessibility entry points
// VoiceOver's swipe up and down call (UITestAccessibilityActionProbe.swift).
//
// The glow intensity starts at 50 %: our step gives 55 % ("55 percent"); the system's own slider step
// (10 % of the range) would give 60 %, so the value proves the app's action ran. The input trim's
// decrement from 0 dB gives "minus 1 decibel". A relaunch reads both back (persisted setting).
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
        let common: [String] = ["-uitestDiagnostics", "-uitestAccessibilityActions", "-autostart", "inAppPlayback"]
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
    private var trim: XCUIElement { app.slider("inputTrimSlider") }
    private var glowToggle: XCUIElement { app.switches["glowToggle"] }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    /// The accessibility increment (or decrement) of the slider `id`, through its probe button.
    private func step(_ id: String, up: Bool) {
        let suffix: String = up ? ".uitestIncrement" : ".uitestDecrement"
        let probe = app.buttons[id + suffix]
        XCTAssertTrue(probe.appears(within: 2) || app.reveal(probe), "probe \(id + suffix)")
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
        XCTAssertTrue(intensity.appears(within: 2) || app.reveal(intensity))
        XCTAssertEqual(value(intensity), "50 percent")
        step("glowIntensitySlider", up: true)
        XCTAssertTrue(poll(5) { self.value(self.intensity) == "55 percent" }, "one 5 % step: \(value(intensity)); probe: \(app.buttons["glowIntensitySlider.uitestIncrement"].value ?? "nil")")

        XCTAssertTrue(app.reveal(trim), "Input trim is in Settings")
        XCTAssertEqual(value(trim), "0 decibels")
        step("inputTrimSlider", up: false)
        XCTAssertTrue(poll(5) { self.value(self.trim) == "minus 1 decibel" }, "one 1 dB step: \(value(trim))")
        XCTAssertEqual(app.staticTexts["inputTrimValue"].label, "\u{2212}1 dB", "the visible readout keeps its short form")
        step("inputTrimSlider", up: true)
        step("inputTrimSlider", up: true)
        XCTAssertTrue(poll(5) { self.value(self.trim) == "plus 1 decibel" }, "two steps up: \(value(trim))")
        app.terminate()

        launch(reset: false)
        openSettings()
        XCTAssertTrue(intensity.appears(within: 2) || app.reveal(intensity))
        XCTAssertEqual(value(intensity), "55 percent", "the stepped intensity persisted")
        XCTAssertTrue(app.reveal(trim))
        XCTAssertEqual(value(trim), "plus 1 decibel", "the stepped trim persisted")
    }
}
