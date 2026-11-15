// ScanlinesUITests.swift — FX-018-T11 on the iOS Simulator: Settings → Scanlines is off by default with no controls;
// turning it on shows Spacing at "3 px", Thickness at "1 px" and Intensity at "50%"; moving the Spacing slider to the end
// reads "16 px" (FX-018-R8, S5). One short test (owner rule 7: under 30 s); persistence across a relaunch is proven by
// `ScanlinesSettingTests.testScanlinesOffByDefaultPersistedAndClamped`. Simulator results are never device evidence.
import XCTest

@MainActor
final class ScanlinesUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launchScanlines() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "scanlines"] + Self.noStore   // Settings opens at Scanlines (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var scanlinesToggle: XCUIElement { app.switches["scanlinesToggle"] }
    private var spacingSlider: XCUIElement { app.slider("scanlinesSpacingSlider") }
    private var spacingReadout: XCUIElement { app.staticTexts["scanlinesSpacingSliderValue"] }
    private func scanlinesIsOn() -> Bool { (scanlinesToggle.value as? String) == "1" }

    func testScanlinesControls() {
        launchScanlines()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(scanlinesToggle), "Scanlines is in Settings")
        XCTAssertFalse(scanlinesIsOn(), "off by default")
        XCTAssertFalse(spacingSlider.exists, "no controls while off")
        scanlinesToggle.switches.firstMatch.exists ? scanlinesToggle.switches.firstMatch.tap() : scanlinesToggle.tap()
        XCTAssertTrue(poll(5) { self.scanlinesIsOn() })
        XCTAssertTrue(spacingSlider.appears(within: 3) || app.reveal(spacingSlider), "Spacing appears once on")
        XCTAssertEqual(spacingReadout.label, "3 px", "the default spacing")
        XCTAssertEqual(spacingSlider.value as? String, "3 pixels", "spoken in pixels")
        let thickness: XCUIElement = app.staticTexts["scanlinesThicknessSliderValue"]
        XCTAssertTrue(thickness.exists || app.reveal(thickness), "the thickness control")
        XCTAssertEqual(thickness.label, "1 px", "the default thickness")
        let intensity: XCUIElement = app.staticTexts["scanlinesIntensitySliderValue"]
        XCTAssertTrue(intensity.exists || app.reveal(intensity), "the intensity control")
        XCTAssertEqual(intensity.label, "50%", "the default intensity")
        // Drag from the thumb's current place to the end; retried while the row settles (at most three drags).
        for _ in 0..<3 where spacingReadout.label != "16 px" {
            let shown: Int = Int(spacingReadout.label.dropLast(3)) ?? 3
            spacingSlider.dragSlider(from: CGFloat(shown - 2) / 14, to: 1)
            _ = poll(3) { self.spacingReadout.label == "16 px" }
        }
        XCTAssertEqual(spacingReadout.label, "16 px", "capped at 16 px")
    }
}
