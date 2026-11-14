// SourceSwitchUITests.swift — AUD-012-T13 on the iOS Simulator: "Switch sources mid-session" with two
// fake sources (`-uitestFake inAppPlayback,systemAppCapture -uitestFakeLevel loud`, DEBUG). The
// indicator leaves the old source at the request, reads "Switching source…" and then names the new
// source; the visualizer stays and its frame loop keeps ticking; the source started twice (the
// switch), never through the chooser. Simulator results are never device evidence (AUD-012-T20).
import XCTest

@MainActor
final class SourceSwitchUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var indicator: XCUIElement { app.staticTexts["sourceIndicator"] }
    private func value(_ id: String) -> String { (app.staticTexts[id].value as? String) ?? "" }
    private func number(_ id: String) -> Int { Int(value(id)) ?? -1 }

    func testSwitchMidSessionKeepsTheVisualAndRelabelsTheSource() {
        XCUIDevice.shared.orientation = .portrait
        // `-uitestRenderFaults none` shows PERF-014's DEBUG readout (renderTicks) with no fault armed.
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestKeepControls", "-uitestRenderFaults", "none",
                               "-uitestFake", "inAppPlayback,systemAppCapture", "-uitestFakeLevel", "loud",
                               "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(indicator.appears(within: 30))   // a ceiling for a loaded Mac
        XCTAssertTrue(poll(10) { self.indicator.label == "In-App Playback · Active audio" }, indicator.label)
        XCTAssertEqual(value("sourceStarts"), "1")

        let switchButton = app.buttons["switchSource"]
        XCTAssertTrue(switchButton.appears(within: 5), "Switch Source is in the controls")
        switchButton.tap()
        let target = app.buttons["switchSource:systemAppCapture"].firstMatch   // the dialog may list it twice (popover and sheet)
        XCTAssertTrue(target.appears(within: 5), "the other available source is offered")
        XCTAssertFalse(app.buttons["switchSource:inAppPlayback"].exists, "the current source is not offered")
        target.tap()

        // The old label is gone from the request on; the new one appears once its audio flows.
        XCTAssertTrue(poll(10) { self.indicator.label.hasPrefix("System/App Capture · ") }, indicator.label)
        XCTAssertFalse(indicator.label.contains("In-App Playback"))
        XCTAssertTrue(poll(10) { self.indicator.label == "System/App Capture · Active audio" }, indicator.label)

        // Still on the visualizer, never through the chooser; the frame loop keeps ticking.
        XCTAssertTrue(app.buttons["switchSource"].exists)
        XCTAssertEqual(value("sourceStarts"), "2")
        let ticks = number("renderTicks")
        XCTAssertTrue(poll(10) { self.number("renderTicks") > ticks }, "the visual keeps rendering (\(ticks) → \(number("renderTicks")))")
    }
}
