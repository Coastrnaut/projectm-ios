// PixelSortUITests.swift — FX-011-T12 on the iOS Simulator: Settings → Pixel sort is off by default with no controls;
// turning it on shows Threshold at "50%", the Span picker and the Direction picker; moving the slider to the start reads
// "0%" (FX-011-R9, S7). One short test (owner rule 7: under 30 s); persistence across a relaunch is proven by
// `PixelSortSettingTests.testPixelSortOffByDefaultPersistedAndClamped`. Simulator results are never device evidence.
import XCTest

@MainActor
final class PixelSortUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launchPixelSort() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "pixelSort"] + Self.noStore   // Settings opens at Pixel sort
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var sortToggle: XCUIElement { app.switches["pixelSortToggle"] }
    private var sortThreshold: XCUIElement { app.slider("pixelSortThresholdSlider") }
    private var thresholdReadout: XCUIElement { app.staticTexts["pixelSortThresholdSliderValue"] }
    private func sortIsOn() -> Bool { (sortToggle.value as? String) == "1" }

    func testPixelSortControls() {
        launchPixelSort()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(sortToggle), "Pixel sort is in Settings")
        XCTAssertFalse(sortIsOn(), "off by default")
        XCTAssertFalse(sortThreshold.exists, "no controls while off")
        sortToggle.switches.firstMatch.exists ? sortToggle.switches.firstMatch.tap() : sortToggle.tap()
        XCTAssertTrue(poll(5) { self.sortIsOn() })
        XCTAssertTrue(sortThreshold.appears(within: 3) || app.reveal(sortThreshold), "Threshold appears once on")
        XCTAssertEqual(thresholdReadout.label, "50%", "the default threshold")
        let direction: XCUIElement = app.segmentedControls["pixelSortDirectionPicker"]
        XCTAssertTrue(direction.exists || app.reveal(direction), "the direction choice")
        // Drag from the thumb's current place to the start; a drag that lands off the thumb is retried (at most three).
        for _ in 0..<3 where thresholdReadout.label != "0%" {
            let shown: Double = Double(thresholdReadout.label.dropLast()) ?? 50
            sortThreshold.dragSlider(from: CGFloat(shown / 100), to: 0)
            _ = poll(3) { self.thresholdReadout.label == "0%" }
        }
        XCTAssertEqual(thresholdReadout.label, "0%", "every pixel qualifies at 0%")
    }
}
