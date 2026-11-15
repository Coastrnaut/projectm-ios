// MIDI-009-T13: a mapping's "Send feedback" switch (MIDI-009-R12; S7). A mapping on CC 7 is seeded by launch argument
// (with the DEBUG stand-in MIDI system, so no system MIDI is touched and feedback is recorded, not sent); open MIDI
// Mappings, open the mapping's Curve row, turn the switch on and read the row's summary. Simulator results are never
// device evidence; a physical controller with LEDs or motor faders is the {device} task MIDI-009-T15. Budget: under 30 s
// (owner rule 7).
import XCTest

@MainActor
final class MIDIFeedbackUITests: XCTestCase {
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

    func testTurnOnFeedbackOnASeededMapping() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestFakeMIDI",
                               "-settings.midi.enabled", "YES",
                               "-settings.midi.mappings", "(\"cc:0:7=effect.bloom.intensity\")",
                               "-uitestSettingsSection", "midi"] + Self.noStore   // Settings opens at MIDI (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let link = app.buttons["midiMappingsLink"]
        XCTAssertTrue(app.reveal(link), "the MIDI Mappings row")
        link.tap()
        XCTAssertTrue(app.navigationBars["MIDI Mappings"].appears(within: 5))

        let curveRow = app.buttons["midiCurve.effect.bloom.intensity"]
        XCTAssertTrue(curveRow.appears(within: 5), "the seeded mapping has a Curve row")
        XCTAssertEqual(curveRow.value as? String, "Linear")
        curveRow.tap()
        XCTAssertTrue(app.navigationBars["Glow intensity"].appears(within: 5))

        let toggle = app.switches["midiFeedback"]
        XCTAssertTrue(app.reveal(toggle), "the Send feedback switch")
        XCTAssertEqual(toggle.value as? String, "0", "off by default")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(5) { (toggle.value as? String) == "1" }, "feedback is on")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["MIDI Mappings"].appears(within: 5))
        XCTAssertTrue(poll(5) { (curveRow.value as? String) == "Linear, feedback" }, "row: \(String(describing: curveRow.value))")
    }
}
