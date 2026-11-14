// MIDI-008-T10: learn a CC button for Next cue and press it twice with the DEBUG stand-in MIDI system
// (`-uitestFakeMIDI`) and the SHOW-001 seed (`-uitestShowSeed`: five cues over five scenes, standing on cue 1)
// (MIDI-008-R7, R9; S5). Listening on at launch and no stored mappings; plug Fake Keys in Settings' MIDI section, open
// MIDI Mappings, tap Learn on Next cue in "Transport", tap Send CC Button (CC 20: 127 then 0), read the result, tap it
// twice more, close Settings: cue 3's scene is applied (the learning press stepped nothing). Simulator results are
// never device evidence; a physical controller is the {device} task MIDI-008-T12. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class MIDITransportUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    private var applied: String? { app.staticTexts["showAppliedScene"].value as? String }

    func testLearnACCButtonForNextCueAndPressItTwice() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestFakeMIDI", "-settings.midi.enabled", "YES", "-settings.midi.mappings", "()",
                               "-uitestSettingsSection", "midi"]   // Settings opens at the MIDI section (owner rule 7)
            + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(poll(3) { self.applied == "\(Self.sceneID(1))|circularSpectrum" }, "seed on cue 1")

        let controls = app.otherElements["controls"]
        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
        app.buttons["settings"].tap()
        let plug = app.buttons["midiFakePlug"]
        XCTAssertTrue(app.reveal(plug, long: true), "the MIDI section's stand-in panel")
        plug.tap()
        let link = app.buttons["midiMappingsLink"]
        XCTAssertTrue(app.reveal(link), "the MIDI Mappings row")
        link.tap()
        XCTAssertTrue(app.navigationBars["MIDI Mappings"].appears(within: 5))

        let row = app.descendants(matching: .any)["midiNote.cue.next"]
        XCTAssertTrue(app.reveal(row), "the Transport section")
        XCTAssertEqual(row.label, "Next cue, not mapped")
        app.buttons["midiNoteLearn.cue.next"].tap()

        let send = app.buttons["midiFakeSendCCButton"]
        let status = app.staticTexts["midiMappingsStatus"]
        XCTAssertTrue(app.reveal(status, down: true), "the status line at the top")
        XCTAssertTrue(poll(5) { ((status.value as? String) ?? "").hasPrefix("Press a key or pad") },
                      "learning: \(String(describing: status.value))")
        XCTAssertTrue(app.reveal(send, down: true), "the stand-in input")
        send.tap()   // CC 20 = 127 then 0, channel 1: learns, steps nothing
        XCTAssertTrue(app.reveal(status, down: true), "the status line")
        XCTAssertTrue(poll(5) { (status.value as? String) == "Next cue mapped to CC button 20 on channel 1." },
                      "status: \(String(describing: status.value))")
        XCTAssertFalse(app.buttons["midiMappingsCancel"].exists, "learn mode exited")

        XCTAssertTrue(app.reveal(send, down: true), "the stand-in input")
        send.tap()   // press 1 → cue 2
        send.tap()   // press 2 → cue 3
        app.navigationBars["MIDI Mappings"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(poll(5) { (self.applied ?? "").hasPrefix(Self.sceneID(3)) }, "two presses, two steps: \(applied ?? "nil")")
    }
}
