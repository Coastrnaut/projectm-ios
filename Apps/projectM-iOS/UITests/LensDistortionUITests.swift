// LensDistortionUITests.swift — FX-016-T15 on the iOS Simulator: Settings → Lens distortion is off by default with no
// controls; turning it on shows Strength at "+30%" and Zoom to fill on; moving the slider to the start reads "-100%"
// (pincushion) (FX-016-R8, S7). One short test (owner rule 7: under 30 s); persistence across a relaunch is proven by
// `LensDistortionSettingTests.testLensDistortionOffByDefaultPersistedAndClamped`. Simulator results are never device
// evidence.
import XCTest

@MainActor
final class LensDistortionUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launchLensDistortion() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "lensDistortion"] + Self.noStore   // Settings opens at Lens distortion
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var lensToggle: XCUIElement { app.switches["lensDistortionToggle"] }
    private var lensStrength: XCUIElement { app.slider("lensDistortionStrengthSlider") }
    private var strengthReadout: XCUIElement { app.staticTexts["lensDistortionStrengthSliderValue"] }
    private func lensIsOn() -> Bool { (lensToggle.value as? String) == "1" }

    func testLensDistortionControls() {
        launchLensDistortion()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(lensToggle), "Lens distortion is in Settings")
        XCTAssertFalse(lensIsOn(), "off by default")
        XCTAssertFalse(lensStrength.exists, "no controls while off")
        lensToggle.switches.firstMatch.exists ? lensToggle.switches.firstMatch.tap() : lensToggle.tap()
        XCTAssertTrue(poll(5) { self.lensIsOn() })
        XCTAssertTrue(lensStrength.appears(within: 3) || app.reveal(lensStrength), "Strength appears once on")
        XCTAssertEqual(strengthReadout.label, "+30%", "the default strength")
        let zoom: XCUIElement = app.switches["lensDistortionZoomToggle"]
        XCTAssertTrue(zoom.exists || app.reveal(zoom), "the zoom choice")
        XCTAssertEqual(zoom.value as? String, "1", "zoom to fill is on by default")
        // Drag from the thumb's current place to the start; a drag that lands off the thumb is retried (at most three).
        for _ in 0..<3 where strengthReadout.label != "-100%" {
            let shown: Double = Double(strengthReadout.label.dropLast().replacingOccurrences(of: "+", with: "")) ?? 30
            lensStrength.dragSlider(from: CGFloat((shown + 100) / 200), to: 0)
            _ = poll(3) { self.strengthReadout.label == "-100%" }
        }
        XCTAssertEqual(strengthReadout.label, "-100%", "the strongest pincushion")
    }
}
