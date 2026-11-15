// MIDI-010-T09: Follow MIDI clock with the DEBUG stand-in MIDI system (`-uitestFakeMIDI`) (MIDI-010-R6; S6). Listening
// on at launch; Settings opens at the MIDI section; plug Fake Keys, turn on Follow MIDI clock, turn on the stand-in's
// "Fake Clock 120" (Start, then Timing Clock on a 120 BPM grid) and read "MIDI clock: 120.0 BPM" in the status row;
// turning following off hides the row. Simulator results are never device evidence; a physical clock source is the
// {device} task MIDI-010-T12. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class MIDIClockUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testFollowMIDIClockShowsTheClocksTempo() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestFakeMIDI", "-settings.midi.enabled", "YES", "-uitestSettingsSection", "midi"]
            + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let controls = app.otherElements["controls"]
        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
        app.buttons["settings"].tap()

        let plug = app.buttons["midiFakePlug"]
        XCTAssertTrue(app.reveal(plug, long: true), "the MIDI section's stand-in panel")
        plug.tap()
        let follow = app.switches["midiFollowClockToggle"]
        XCTAssertTrue(app.reveal(follow), "Follow MIDI clock")
        XCTAssertEqual(follow.value as? String, "0", "off by default")
        follow.switches.firstMatch.tap()
        let status = app.staticTexts["midiClockStatus"]
        XCTAssertTrue(status.appears(within: 3), "the status row appears while following")
        XCTAssertEqual(status.value as? String, "No MIDI clock")

        let fake = app.switches["midiFakeClockToggle"]
        XCTAssertTrue(app.reveal(fake), "the stand-in clock")
        fake.switches.firstMatch.tap()
        XCTAssertTrue(poll(5) { (status.value as? String) == "MIDI clock: 120.0 BPM" },
                      "status: \(String(describing: status.value))")

        fake.switches.firstMatch.tap()   // the stand-in stops
        XCTAssertTrue(app.reveal(follow, down: true), "Follow MIDI clock")
        follow.switches.firstMatch.tap()
        XCTAssertTrue(poll(3) { !status.exists }, "the status row hides when following is off")
    }
}
