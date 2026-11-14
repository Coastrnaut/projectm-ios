// MIDI-003-T10: MIDI learn with the DEBUG stand-in MIDI system (`-uitestFakeMIDI`; MIDI-003-R10, R14, S7).
// Listening on at launch and no stored mappings; plug Fake Keys (an input) in Settings, open MIDI Mappings, tap
// Learn on Glow intensity, send a control change through the stand-in input, and read the mapped row. Simulator
// results are never device evidence; a physical controller is the {device} task MIDI-003-T17. Budget: under 30 s
// (owner rule 7).
import XCTest

@MainActor
final class MIDILearnUITests: XCTestCase {
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

    func testLearnThenSendCCCreatesTheMappingRow() {
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

        let row = app.descendants(matching: .any)["midiMapping.effect.bloom.intensity"]
        XCTAssertTrue(row.appears(within: 5))
        XCTAssertEqual(row.label, "Glow intensity, not mapped")
        app.buttons["midiLearn.effect.bloom.intensity"].tap()
        let status = app.staticTexts["midiMappingsStatus"]
        XCTAssertTrue(poll(5) { ((status.value as? String) ?? "").hasPrefix("Move a control") },
                      "learning: \(String(describing: status.value))")

        app.buttons["midiFakeSendCC"].tap()   // CC 7, channel 1, value 100
        XCTAssertTrue(poll(5) { row.label == "Glow intensity, CC 7, channel 1" }, "row: \(row.label)")
        XCTAssertEqual(status.value as? String, "Glow intensity mapped to CC 7 on channel 1.")
        XCTAssertFalse(app.buttons["midiMappingsCancel"].exists, "learn mode exited")
    }
}
