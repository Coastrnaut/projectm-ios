// MIDI-001-T13: MIDI endpoint discovery in Settings with the DEBUG stand-in MIDI system (`-uitestFakeMIDI`;
// MIDI-001-R8, R9, R15, S6). Off at start; on → the virtual "Fake Synth" output is listed; Plug Fake Keys →
// its input and output appear; Unplug → they leave; Plug again → the same rows (same IDs). Simulator
// results are never device evidence; a physical controller is the {device} task MIDI-001-T18.
// Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class MIDIDiscoveryUITests: XCTestCase {
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

    /// Read in place: the section is revealed once, and the status sits right under the toggle.
    private func status() -> String {
        let element = app.staticTexts["midiStatus"]
        return (element.value as? String) ?? element.label
    }

    private func readout() -> String {
        let element = app.staticTexts["midiFakeRows"]
        return element.exists ? element.label : ""
    }

    private func row(_ id: Int32) -> XCUIElement {
        app.descendants(matching: .any)["midiEndpoint.midi:" + String(id)]
    }

    func testFakeDeviceAppearsAndDisappearsInSettings() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestFakeMIDI",
                               "-settings.midi.enabled", "NO"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let toggle = app.switches["midiListenToggle"]
        XCTAssertTrue(app.reveal(toggle), "the MIDI section is in Settings")
        XCTAssertEqual(toggle.value as? String, "0", "off at start")
        XCTAssertEqual(status(), "Off")

        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(5) { self.status() == "Listening — 1 device" }, "status: \(status())")
        // The DEBUG panel sits under the status, above the rows: its readout mirrors the rows' labels.
        let plug = app.buttons["midiFakePlug"], unplug = app.buttons["midiFakeUnplug"]
        app.reveal(unplug)
        let synthOnly = "Fake Synth, Output, Virtual"
        let withKeys = "Fake Keys, Input | Fake Keys, Output | Fake Synth, Output, Virtual"
        XCTAssertEqual(readout(), synthOnly, "the virtual output is listed")
        XCTAssertTrue(row(0x5000_0001).exists, "its row carries the stable ID")
        plug.tap()
        XCTAssertTrue(poll(5) { self.readout() == withKeys && self.status() == "Listening — 3 devices" },
                      "rows: \(readout()), status: \(status())")
        XCTAssertTrue(row(0x5000_0010).exists)
        unplug.tap()
        XCTAssertTrue(poll(5) { self.readout() == synthOnly && self.status() == "Listening — 1 device" },
                      "rows: \(readout()), status: \(status())")
        XCTAssertFalse(row(0x5000_0010).exists)
        plug.tap()
        XCTAssertTrue(poll(5) { self.readout() == withKeys }, "the replugged device returns: \(readout())")
        XCTAssertTrue(row(0x5000_0010).exists, "with the same ID (row identifier)")
        // Turning listening off clears the list: MIDIDiscoveryCoordinatorTests (kept out of this test's budget).
    }
}
