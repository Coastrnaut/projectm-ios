// PlaybackBalanceUITests.swift — AUD-010-T14 on the iOS Simulator: Settings → Playback Balance is
// enabled under In-App Playback, moves to full left, offers Center, and returns to centre by
// double-tap; it is disabled under the Microphone (AUD-010-R6, R8; S3). Two short tests (owner rule 7:
// under 30 s each). Simulator results are never device evidence (Constitution X): what is heard is
// proven offline in CaptureKit's PlaybackBalanceTests.
import XCTest

@MainActor
final class PlaybackBalanceUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ source: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics"] + source + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func openSettings() {
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private var slider: XCUIElement { app.slider("playbackBalanceSlider") }
    private var readout: XCUIElement { app.staticTexts["playbackBalanceValue"] }

    func testBalanceMovesAndCentresUnderInAppPlayback() {
        launch(["-autostart", "inAppPlayback"])
        openSettings()
        XCTAssertTrue(app.reveal(slider), "Balance is in Settings")
        XCTAssertTrue(slider.isEnabled, "enabled for In-App Playback")
        XCTAssertEqual(readout.label, "Centered")
        XCTAssertEqual(slider.value as? String, "centered", "VoiceOver: Balance, centered (ACC-005)")
        let center = app.buttons["playbackBalanceCenter"]
        XCTAssertFalse(center.isEnabled, "nothing to reset at centre")

        slider.dragSlider(from: 0.5, to: 0)   // the end stop: exactly full left
        XCTAssertTrue(poll(5) { self.readout.label == "100% left" }, "readout: \(readout.label)")
        XCTAssertEqual(slider.value as? String, "100 percent left")
        XCTAssertTrue(center.isEnabled, "Center is offered off centre (its action, reset(), is unit-tested)")
        slider.doubleTap()
        XCTAssertTrue(poll(5) { self.readout.label == "Centered" }, "double-tap centres: \(readout.label)")
        XCTAssertFalse(center.isEnabled)
    }

    func testBalanceIsDisabledUnderTheMicrophone() {
        launch(["-uitestFake", "microphone", "-autostart", "microphone"])
        openSettings()
        XCTAssertTrue(app.reveal(slider), "the row stays discoverable")
        XCTAssertFalse(slider.isEnabled, "the app does not play the microphone aloud")
        XCTAssertFalse(app.buttons["playbackBalanceCenter"].isEnabled)
    }
}
