// SensorySafetyUITests.swift — ACC-012-T18 (ACC-012-S5): choose Strict in Settings → Sensory safety and the
// DEBUG probe shows the clamp applied (glow 0.50 → 0.25, 1 flash per second, 0.10/s rise, intensity 0.25);
// Custom shows its controls. Budget: under 30 s (owner rule 7). Simulator results are never device evidence.
import XCTest

@MainActor
final class SensorySafetyUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testChoosingStrictClampsWhatTheVisualReceives() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let picker = app.segmentedControls["sensorySafetyProfilePicker"]
        XCTAssertTrue(picker.appears(within: 2) || app.reveal(picker, long: true), "the Sensory safety section")
        let probe = app.staticTexts["sensorySafetyProbe"]
        XCTAssertTrue(probe.exists || app.reveal(probe, long: true))
        XCTAssertEqual(probe.label, "glow 0.50 flashes 3/s rise none intensity 1.00", "Standard: today's values")

        picker.buttons["Strict"].tap()
        XCTAssertTrue(poll(3) { probe.label == "glow 0.25 flashes 1/s rise 0.10 intensity 0.25" }, "Strict: \(probe.label)")

        picker.buttons["Custom"].tap()
        let intensity = app.slider("sensorySafetyIntensitySlider")   // ACC-005: an "other" element
        XCTAssertTrue(intensity.appears(within: 2) || app.reveal(intensity, long: true), "Custom shows its sliders")
        XCTAssertTrue(app.slider("sensorySafetyRiseSlider").exists)
        XCTAssertTrue(poll(3) { probe.label == "glow 0.25 flashes 1/s rise 0.10 intensity 0.25" },
                      "Custom starts from Strict: \(probe.label)")
    }

}
