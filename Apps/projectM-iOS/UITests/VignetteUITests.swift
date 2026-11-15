// VignetteUITests.swift — FX-015-T11 on the iOS Simulator: Settings → Vignette is off by default with no controls;
// turning it on shows Intensity at "50%" and Center X at "0.50"; moving the Intensity slider to the end reads "100%"
// (FX-015-R8, S6). One short test (owner rule 7: under 30 s); persistence across a relaunch is proven by
// `VignetteSettingTests.testVignetteOffByDefaultPersistedAndClamped`. Simulator results are never device evidence.
import XCTest

@MainActor
final class VignetteUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launchVignette() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "vignette"] + Self.noStore   // Settings opens at Vignette (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var vignetteToggle: XCUIElement { app.switches["vignetteToggle"] }
    private var vignetteIntensity: XCUIElement { app.slider("vignetteIntensitySlider") }
    private var intensityReadout: XCUIElement { app.staticTexts["vignetteIntensitySliderValue"] }
    private func vignetteIsOn() -> Bool { (vignetteToggle.value as? String) == "1" }

    func testVignetteControls() {
        launchVignette()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(vignetteToggle), "Vignette is in Settings")
        XCTAssertFalse(vignetteIsOn(), "off by default")
        XCTAssertFalse(vignetteIntensity.exists, "no controls while off")
        vignetteToggle.switches.firstMatch.exists ? vignetteToggle.switches.firstMatch.tap() : vignetteToggle.tap()
        XCTAssertTrue(poll(5) { self.vignetteIsOn() })
        XCTAssertTrue(vignetteIntensity.appears(within: 3) || app.reveal(vignetteIntensity), "Intensity appears once on")
        XCTAssertEqual(intensityReadout.label, "50%", "the default intensity")
        let centerX: XCUIElement = app.staticTexts["vignetteCenterXSliderValue"]
        XCTAssertTrue(centerX.exists || app.reveal(centerX), "the centre controls")
        XCTAssertEqual(centerX.label, "0.50", "the default centre")
        // Drag from the thumb's current place to the end; retried while the row settles (at most three drags).
        for _ in 0..<3 where intensityReadout.label != "100%" {
            let shown: Int = Int(intensityReadout.label.dropLast()) ?? 50
            vignetteIntensity.dragSlider(from: CGFloat(shown) / 100, to: 1)
            _ = poll(3) { self.intensityReadout.label == "100%" }
        }
        XCTAssertEqual(intensityReadout.label, "100%", "capped at 100%")
    }
}
