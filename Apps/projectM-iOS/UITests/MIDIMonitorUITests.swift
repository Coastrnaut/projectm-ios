// MIDI-002-T14: the MIDI Monitor with the DEBUG stand-in MIDI system (`-uitestFakeMIDI`; MIDI-002-R6, R12, S6).
// Listening on at launch; plug Fake Keys (an input) in Settings, open MIDI Monitor, send a control change and a
// note through the stand-in input, and read both rows' combined labels, newest first. Simulator results are never
// device evidence; a physical controller is the {device} task MIDI-002-T20. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class MIDIMonitorUITests: XCTestCase {
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

    private func rowLabels() -> [String] {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'midiMonitorEntry.'"))
        return rows.allElementsBoundByIndex.map { (row: XCUIElement) -> String in row.label }
    }

    func testInjectedControlChangeAndNoteAppearInTheMonitor() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestFakeMIDI",
                               "-settings.midi.enabled", "YES"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let plug = app.buttons["midiFakePlug"]
        XCTAssertTrue(app.reveal(plug, long: true), "the MIDI section's stand-in panel")
        plug.tap()
        let link = app.buttons["midiMonitorLink"]
        XCTAssertTrue(app.reveal(link), "the MIDI Monitor row")
        link.tap()
        XCTAssertTrue(app.navigationBars["MIDI Monitor"].appears(within: 5))

        let status = app.staticTexts["midiMonitorStatus"]
        XCTAssertTrue(poll(5) { ((status.value as? String) ?? "") == "Waiting for MIDI messages" },
                      "receiving: \(String(describing: status.value))")
        app.buttons["midiFakeSendCC"].tap()
        app.buttons["midiFakeSendNote"].tap()
        let expected = ["Note on, channel 1, note 60 C4, velocity 100",
                        "Control change, channel 1, controller 7, value 100"]
        XCTAssertTrue(poll(5) { self.rowLabels() == expected }, "rows: \(rowLabels())")
    }
}
