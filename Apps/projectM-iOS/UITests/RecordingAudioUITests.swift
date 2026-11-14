// RecordingAudioUITests.swift — REC-004-T17 on the iOS Simulator: Settings → Recording shows
// "Include microphone audio" off by default and the next recording's audio status ("Recording includes
// app audio." with In-App Playback running); the toggle turns on and off and the status stays the
// app-audio text (the setting only concerns the microphone). One short test (owner rule 7: under 30 s);
// persistence is proven by `RecordingAudioAppTests.testSettingDefaultsOffAndPersists`. Simulator
// results are never device evidence (Constitution X).
import XCTest

@MainActor
final class RecordingAudioUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        let common: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                                "-uitestSettingsSection", "recording"]   // Settings opens at Recording (owner rule 7)
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

    private var toggle: XCUIElement { app.switches["recordingMicrophoneToggle"] }
    private var status: XCUIElement { app.staticTexts["recordingAudioStatus"] }

    private func tapToggle() {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()   // the switch inside the row
    }

    func testIncludeMicrophoneAudioToggleInSettings() {
        launch()
        openSettings()
        XCTAssertTrue(app.reveal(status), "the audio status is in Settings › Recording")
        XCTAssertTrue(app.reveal(toggle), "Include microphone audio is in Settings › Recording")
        XCTAssertEqual(toggle.value as? String, "0", "off by default")
        XCTAssertEqual(status.label, "Recording includes app audio.")
        tapToggle()
        XCTAssertTrue(poll(5) { (self.toggle.value as? String) == "1" }, "toggle: \(String(describing: toggle.value))")
        XCTAssertEqual(status.label, "Recording includes app audio.", "the setting concerns only the microphone")
        tapToggle()
        XCTAssertTrue(poll(5) { (self.toggle.value as? String) == "0" })
    }
}
