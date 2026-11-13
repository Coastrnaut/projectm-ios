// GlowUITests.swift — FX-001-T18, T22 on the iOS Simulator: the circular spectrum's Glow controls in
// Settings, persistence across relaunch without restarting the source, and the forced-failure
// notice (FX-001 User Stories 1 and 4; FX-001-R11 to R13). The circular spectrum's accessibility
// value reports the glow state ("Glow on", "Glow off", "Glow unavailable"). Simulator results are
// never device evidence (Constitution X). Waits use generous ceilings, never frame budgets.
// Shortened 2026-11-13 under owner rule 7: `-autostart inAppPlayback` replaces the notice and chooser
// taps, and waits poll every 0.1 s (UITestWaits.swift) instead of about once a second.
import XCTest

@MainActor
final class GlowUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// `reset` starts from fresh settings; `-autostart inAppPlayback` (Debug) starts the reference
    /// track as the chooser's In-App Playback row does.
    private func launch(reset: Bool, extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics", "-autostart", "inAppPlayback"]
            + extra + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var circularSpectrum: XCUIElement { app.descendants(matching: .any)["circularSpectrum"].firstMatch }
    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }
    private var glowToggle: XCUIElement { app.switches["glowToggle"] }

    private func openSettings() {
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    private func isOn(_ toggle: XCUIElement) -> Bool { (toggle.value as? String) == "1" }

    private func flip(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    /// Polls `condition` for up to 30 s.
    private func waitUntil(_ condition: () -> Bool) -> Bool { poll(30, condition) }

    private func chooseCircularSpectrum() {
        let row = app.visualRow("Circular Spectrum")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
    }

    func testGlowControlsAppearOnlyForTheCircularSpectrumAndPersist() {
        launch(reset: true)
        openSettings()
        XCTAssertFalse(glowToggle.exists, "no glow controls for projectM")
        chooseCircularSpectrum()
        XCTAssertTrue(glowToggle.appears(within: 5))
        XCTAssertFalse(isOn(glowToggle), "Glow is off by default")
        XCTAssertFalse(app.sliders["glowIntensitySlider"].exists)
        flip(glowToggle)
        XCTAssertTrue(isOn(glowToggle))
        let intensity = app.sliders["glowIntensitySlider"]
        XCTAssertTrue(intensity.appears(within: 5))
        XCTAssertEqual(intensity.label, "Intensity")
        XCTAssertEqual(intensity.value as? String, "50%")
        let radius = app.sliders["glowRadiusSlider"]
        XCTAssertTrue(radius.exists)
        XCTAssertEqual(radius.label, "Radius")
        XCTAssertEqual(radius.value as? String, "2.0%")
        let threshold = app.sliders["glowThresholdSlider"]
        XCTAssertTrue(threshold.exists)
        XCTAssertEqual(threshold.label, "Threshold")
        XCTAssertEqual(threshold.value as? String, "70%")
        intensity.adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue(waitUntil { (intensity.value as? String) == "100%" }, "intensity moved: \(String(describing: intensity.value))")
        closeSettings()
        XCTAssertTrue(circularSpectrum.appears(within: 10))
        XCTAssertTrue(waitUntil { (self.circularSpectrum.value as? String) == "Glow on" },
                      "the running visual uses the glow: \(String(describing: circularSpectrum.value))")
        XCTAssertEqual(starts, "1", "changing the glow does not restart the source")
        app.terminate()

        launch(reset: false)
        XCTAssertTrue(circularSpectrum.appears(within: 10))
        XCTAssertTrue(waitUntil { (self.circularSpectrum.value as? String) == "Glow on" }, "the glow persisted")
        openSettings()
        XCTAssertTrue(glowToggle.appears(within: 5))
        XCTAssertTrue(isOn(glowToggle), "the toggle persisted")
        XCTAssertEqual(app.sliders["glowIntensitySlider"].value as? String, "100%", "the intensity persisted")
        flip(glowToggle)
        XCTAssertTrue(app.sliders["glowIntensitySlider"].disappears(within: 2))
        closeSettings()
        XCTAssertTrue(waitUntil { (self.circularSpectrum.value as? String) == "Glow off" })
        XCTAssertEqual(starts, "1")
    }

    func testAGlowFailureKeepsTheCircularSpectrumWithANotice() {
        launch(reset: true, extra: ["-uitestGlowFailure"])
        openSettings()
        chooseCircularSpectrum()
        closeSettings()
        XCTAssertTrue(circularSpectrum.appears(within: 10), "the visual itself is not affected")
        openSettings()
        XCTAssertTrue(glowToggle.appears(within: 5))
        flip(glowToggle)
        let footer = app.staticTexts["glowUnavailableFooter"]
        XCTAssertTrue(footer.appears(within: 5), "visible notice (FX-001-R13)")
        XCTAssertEqual(footer.label, "Glow isn't available on this device.")
        closeSettings()
        XCTAssertTrue(circularSpectrum.exists, "never a black screen: the circular spectrum keeps rendering")
        XCTAssertTrue(waitUntil { (self.circularSpectrum.value as? String) == "Glow unavailable" })
        XCTAssertEqual(starts, "1")
    }
}
