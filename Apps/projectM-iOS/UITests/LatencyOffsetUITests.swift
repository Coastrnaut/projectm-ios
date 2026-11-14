// LatencyOffsetUITests.swift — AUD-013-T12 on the iOS Simulator: Settings → Visual Delay starts on the
// active source (In-App Playback) at "0 ms"; moving the slider changes the readout and Reset returns
// it to "0 ms" (AUD-013 User Stories 1 and 3; R10, R12; S7). One short test (owner rule 7: under
// 30 s); persistence across a relaunch and per-source independence are proven by
// `LatencyOffsetSettingTests` (a new store on the same defaults). Simulator results are never device
// evidence (Constitution X).
import XCTest

@MainActor
final class LatencyOffsetUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        let common: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"]
        app.launchArguments = common + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func openSettings() {
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private var slider: XCUIElement { app.slider("latencyOffsetSlider") }
    private var readout: XCUIElement { app.staticTexts["latencyOffsetValue"] }
    private var reset: XCUIElement { app.buttons["latencyOffsetReset"] }

    func testVisualDelayControlsInSettings() {
        launch()
        openSettings()
        XCTAssertTrue(app.reveal(reset), "Reset is in Settings")
        XCTAssertTrue(app.reveal(slider), "Visual delay is in Settings")
        XCTAssertTrue(app.buttons["latencyOffsetEstimate"].exists, "Estimate from Output is offered")
        let picker: XCUIElement = app.descendants(matching: .any)["latencyOffsetSource"].firstMatch
        XCTAssertTrue(picker.exists, "the source picker is in Settings")
        XCTAssertEqual(readout.label, "0 ms", "0 ms by default")
        XCTAssertEqual(slider.label, "Visual delay")
        slider.dragSlider(from: 0, to: 0.6)   // ACC-005: dragged by touch
        XCTAssertTrue(poll(5) { self.readout.label != "0 ms" }, "readout: \(readout.label)")
        XCTAssertEqual(slider.value as? String, readout.label.replacingOccurrences(of: " ms", with: " milliseconds"),
                       "VoiceOver reads the readout with the unit spelled out (ACC-005-R2)")
        XCTAssertTrue(app.reveal(reset))
        reset.tap()
        XCTAssertTrue(poll(5) { self.readout.label == "0 ms" }, "after Reset: \(readout.label)")
    }
}
