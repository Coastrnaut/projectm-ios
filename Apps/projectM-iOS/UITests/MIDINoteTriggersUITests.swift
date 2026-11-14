// MIDI-006-T14: learn a note to a trigger with the DEBUG stand-in MIDI system (`-uitestFakeMIDI`; MIDI-006-R8, R11;
// S5). Listening on at launch and no stored mappings; plug Fake Keys (an input) in Settings, open MIDI Mappings, tap
// Learn on Next cue in "Note triggers", send a note (note on 60, velocity 100) through the stand-in input, and read
// the mapped row. Simulator results are never device evidence; a physical controller is the {device} task
// MIDI-006-T16. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class MIDINoteTriggersUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openSettings() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    func testLearnANoteToNextCue() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestFakeMIDI",
                               "-settings.midi.enabled", "YES", "-settings.midi.mappings", "()"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let plug = app.buttons["midiFakePlug"]
        XCTAssertTrue(app.reveal(plug, long: true), "the MIDI section's stand-in panel")
        plug.tap()
        let link = app.buttons["midiMappingsLink"]
        XCTAssertTrue(app.reveal(link), "the MIDI Mappings row")
        link.tap()
        XCTAssertTrue(app.navigationBars["MIDI Mappings"].appears(within: 5))

        let row = app.descendants(matching: .any)["midiNote.cue.next"]
        XCTAssertTrue(app.reveal(row), "the Note triggers section")
        XCTAssertEqual(row.label, "Next cue, not mapped")
        app.buttons["midiNoteLearn.cue.next"].tap()

        let send = app.buttons["midiFakeSendNote"]
        XCTAssertTrue(app.reveal(send, down: true), "the stand-in input at the top")
        let status = app.staticTexts["midiMappingsStatus"]
        XCTAssertTrue(poll(5) { ((status.value as? String) ?? "").hasPrefix("Press a key or pad") },
                      "learning: \(String(describing: status.value))")
        send.tap()   // note on 60 (C4), channel 1, velocity 100
        XCTAssertTrue(poll(5) { (status.value as? String) == "Next cue mapped to note C4 on channel 1." },
                      "status: \(String(describing: status.value))")
        XCTAssertFalse(app.buttons["midiMappingsCancel"].exists, "learn mode exited")
        XCTAssertTrue(app.reveal(row), "the mapped row")
        XCTAssertEqual(row.label, "Next cue, note C4, channel 1")
    }
}
