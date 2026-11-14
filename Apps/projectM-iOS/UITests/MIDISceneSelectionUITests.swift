// MIDI-007-T13: assign a program change to a scene and trigger it with the DEBUG stand-in MIDI system
// (`-uitestFakeMIDI`) and the SHOW-001 seed (`-uitestShowSeed`: five cues over five scenes, standing on cue 1)
// (MIDI-007-R8, R12; S5). Listening on at launch and no stored mappings; plug Fake Keys in Settings' MIDI section, open
// Settings › Show, swipe cue 3 ("Drop") and pick MIDI (Assign MIDI…), send program 5 through the stand-in input, read
// the result, send it again, close the sheet: cue 3 is the active cue. Simulator results are never device evidence; a physical
// controller is the {device} task MIDI-007-T15. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class MIDISceneSelectionUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    private var applied: String? { app.staticTexts["showAppliedScene"].value as? String }
    private var controls: XCUIElement { app.otherElements["controls"] }

    private func showControls() {
        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
    }

    /// A short right swipe on a cue row (never a full swipe, which runs Go), then one of its leading actions.
    private func swipeAction(_ row: XCUIElement, id: String, titles: [String]) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let predicate = NSPredicate(format: "identifier == %@ OR label IN %@", id, titles)
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(button.appears(within: 3), "\(id) is offered")
        button.tap()
    }

    func testAssignAProgramToASceneAndTriggerIt() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestFakeMIDI", "-settings.midi.enabled", "YES", "-settings.midi.mappings", "()",
                               "-uitestSettingsSection", "midi"]   // Settings opens at the MIDI section (owner rule 7)
            + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(poll(3) { self.applied == "\(Self.sceneID(1))|circularSpectrum" }, "seed on cue 1")

        showControls()
        app.buttons["settings"].tap()
        let plug = app.buttons["midiFakePlug"]
        XCTAssertTrue(app.reveal(plug, long: true), "the MIDI section's stand-in panel")
        plug.tap()
        let link = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(link, long: true), "the Show row")
        link.tap()

        let drop = app.descendants(matching: .any)["showCue3"]
        XCTAssertTrue(drop.appears(within: 5))
        XCTAssertEqual(drop.value as? String, "Cue 3 of 5")
        swipeAction(drop, id: "showAssignMIDI", titles: ["MIDI", "Assign MIDI"])

        let status = app.staticTexts["midiSceneAssignStatus"]
        XCTAssertTrue(poll(5) { ((status.value as? String) ?? "").hasPrefix("Send a program change") },
                      "learning: \(String(describing: status.value))")
        let send = app.buttons["midiFakeSendProgram"]
        XCTAssertTrue(app.reveal(send), "the stand-in input in the sheet")
        send.tap()   // program 5, channel 1
        XCTAssertTrue(poll(5) { (status.value as? String) == "Drop mapped to program 5 on channel 1." },
                      "status: \(String(describing: status.value))")
        XCTAssertEqual(app.descendants(matching: .any)["midiSceneAssignControl"].value as? String, "Program 5 · Ch 1")

        XCTAssertTrue(app.buttons["midiSceneAssignLearn"].exists, "learn mode exited")
        send.tap()   // learning is over: the mapping now selects Drop (the learning message itself: app tests)
        app.buttons["midiSceneAssignDone"].tap()
        XCTAssertTrue(poll(5) { (drop.value as? String) == "Cue 3 of 5, active" }, "cue 3 is active: \(drop.value ?? "nil")")
    }
}
