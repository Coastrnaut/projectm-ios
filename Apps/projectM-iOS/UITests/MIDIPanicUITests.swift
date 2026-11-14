// MIDI-013-T10: the MIDI panic with the DEBUG stand-in MIDI system (`-uitestFakeMIDI`; MIDI-013-R7, S5). Listening on
// at launch with one stored note mapping (note 60 → Next cue; no show, so it steps nothing); Settings opens at MIDI.
// Plug Fake Keys, tap Hold Note (note on 60, no release): the probe reads "1 held"; tap MIDI Panic: "0 held". Hold again
// and press ⌘⇧M: "0 held". Simulator results are never device evidence; a physical controller is the {device} task
// MIDI-013-T13. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class MIDIPanicUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testPanicReleasesAHeldNote() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestFakeMIDI",
                               "-settings.midi.enabled", "YES", "-settings.midi.mappings", "(\"note:0:60=cue.next\")",
                               "-uitestSettingsSection", "midi"] + Self.noStore   // Settings opens at MIDI (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let controls = app.otherElements["controls"]
        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
        app.buttons["settings"].tap()

        let plug = app.buttons["midiFakePlug"]
        XCTAssertTrue(app.reveal(plug, long: true), "the MIDI section's stand-in panel")
        plug.tap()
        let hold = app.buttons["midiFakeHoldNote"]
        let probe = app.staticTexts["midiHeldProbe"]
        let panic = app.buttons["midiPanicButton"]
        XCTAssertTrue(app.reveal(hold), "the panic probe")
        XCTAssertTrue(panic.exists, "the MIDI Panic button")

        hold.tap()
        XCTAssertTrue(poll(5) { probe.label == "1 held" }, "held: \(probe.label)")
        panic.tap()
        XCTAssertTrue(poll(3) { probe.label == "0 held" }, "after panic: \(probe.label)")

        hold.tap()   // a fresh press after panic
        XCTAssertTrue(poll(5) { probe.label == "1 held" }, "held again: \(probe.label)")
        app.typeKey("m", modifierFlags: [.command, .shift])   // MIDI-013-R7: ⌘⇧M
        XCTAssertTrue(poll(3) { probe.label == "0 held" }, "after ⌘⇧M: \(probe.label)")
    }
}
