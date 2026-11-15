// EdgeOutlineUITests.swift — FX-014-T15 on the iOS Simulator: Settings → Edge outline is off by default with no
// controls; turning it on shows Threshold at "0.20", the width and mode choices; moving the slider to the end reads
// "1.00" and Outline only can be chosen (FX-014-R9, S6). One short test (owner rule 7: under 30 s); persistence across
// a relaunch is proven by `EdgeOutlineSettingTests.testEdgeOutlineOffByDefaultPersistedAndClamped`. Simulator results
// are never device evidence.
import XCTest

@MainActor
final class EdgeOutlineUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launchEdgeOutline() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "edgeOutline"] + Self.noStore   // Settings opens at Edge outline
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var outlineToggle: XCUIElement { app.switches["edgeOutlineToggle"] }
    private var outlineThreshold: XCUIElement { app.slider("edgeOutlineThresholdSlider") }
    private var thresholdReadout: XCUIElement { app.staticTexts["edgeOutlineThresholdSliderValue"] }
    private func outlineIsOn() -> Bool { (outlineToggle.value as? String) == "1" }

    func testEdgeOutlineControls() {
        launchEdgeOutline()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(outlineToggle), "Edge outline is in Settings")
        XCTAssertFalse(outlineIsOn(), "off by default")
        XCTAssertFalse(outlineThreshold.exists, "no controls while off")
        outlineToggle.switches.firstMatch.exists ? outlineToggle.switches.firstMatch.tap() : outlineToggle.tap()
        XCTAssertTrue(poll(5) { self.outlineIsOn() })
        XCTAssertTrue(outlineThreshold.appears(within: 3) || app.reveal(outlineThreshold), "Threshold appears once on")
        XCTAssertEqual(thresholdReadout.label, "0.20", "the default threshold")
        // Drag from the thumb's current place to the end; a drag that lands off the thumb is retried (at most three).
        for _ in 0..<3 where thresholdReadout.label != "1.00" {
            let shown: Double = Double(thresholdReadout.label) ?? 0.2
            outlineThreshold.dragSlider(from: CGFloat((shown - 0.02) / 0.98), to: 1)
            _ = poll(3) { self.thresholdReadout.label == "1.00" }
        }
        XCTAssertEqual(thresholdReadout.label, "1.00", "capped at 1")
        let only: XCUIElement = app.segmentedControls["edgeOutlineModePicker"].buttons["Outline only"]
        XCTAssertTrue(only.exists || app.reveal(only), "the mode choice")
        only.tap()
        XCTAssertTrue(poll(3) { only.isSelected }, "Outline only chosen")
        XCTAssertTrue(app.segmentedControls["edgeOutlineWidthPicker"].exists, "the width choice")
    }
}
