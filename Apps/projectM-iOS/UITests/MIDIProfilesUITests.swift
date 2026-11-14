// MIDI-012-T10: MIDI mapping profiles (MIDI-012-R10, S5). One stored mapping (CC 7 → Glow intensity) and no profiles
// at launch; open MIDI Mappings and go to Profiles (the last section), Save Current ("Profile 1", in use), change the
// mappings with "Program number selects cue" (just above), Save Current ("Profile 2"), Apply "Profile 1" (in use again:
// the stored list equals it byte for byte), then Undo ("Profile 2" in use again). No MIDI device is needed. Budget:
// under 30 s (owner rule 7).
import XCTest

@MainActor
final class MIDIProfilesUITests: XCTestCase {
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

    private func openMappings() {
        // Settings opens at the MIDI section: wait for the sheet to settle before deciding to scroll (under load the
        // sheet still slides up at the first check, and a reveal then scrolls past the row).
        let link = app.buttons["midiMappingsLink"]
        XCTAssertTrue(link.appears(within: 5), "the MIDI Mappings row")
        _ = link.settles(within: 3)
        if !link.isHittable { XCTAssertTrue(app.reveal(link), "the MIDI Mappings row") }
        link.tap()
        XCTAssertTrue(app.navigationBars["MIDI Mappings"].appears(within: 5))
    }

    func testSaveThenApplyAnotherProfile() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestResetMIDIProfiles",
                               "-settings.midi.enabled", "YES", "-settings.midi.mappings", "(\"cc:0:7=effect.bloom.intensity\")",
                               "-uitestSettingsSection", "midi"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()
        openMappings()

        let save = app.buttons["midiProfileSaveCurrent"]
        XCTAssertTrue(app.reveal(save, long: true), "the Profiles section")
        save.tap()
        let first = app.descendants(matching: .any)["midiProfile.Profile 1"]
        XCTAssertTrue(first.appears(within: 5))
        XCTAssertEqual(first.label, "Profile 1, 1 mapping, in use")

        // Change the mappings: the program number selects a cue on any channel (adds `pc:*:*=cue.position`).
        let mode = app.buttons["midiProgramCueMode"]
        XCTAssertTrue(mode.appears(within: 5))
        mode.tap()
        let anyChannel = app.buttons["Any channel"]
        XCTAssertTrue(anyChannel.appears(within: 5))
        anyChannel.tap()
        XCTAssertTrue(poll(5) { first.label == "Profile 1, 1 mapping" }, "no longer in use: \(first.label)")

        XCTAssertTrue(app.reveal(save))
        save.tap()
        let second = app.descendants(matching: .any)["midiProfile.Profile 2"]
        XCTAssertTrue(second.appears(within: 5))
        XCTAssertEqual(second.label, "Profile 2, 2 mappings, in use")

        app.buttons["midiProfileApply.Profile 1"].tap()
        XCTAssertTrue(poll(5) { first.label == "Profile 1, 1 mapping, in use" }, "applied: \(first.label)")
        XCTAssertEqual(second.label, "Profile 2, 2 mappings")
        XCTAssertEqual(app.staticTexts["midiProfilesMessage"].label, "Applied MIDI profile Profile 1.")

        let undo = app.buttons["midiMappingsUndo"]
        XCTAssertTrue(undo.isEnabled, "Apply is one Undo step")
        undo.tap()
        XCTAssertTrue(poll(5) { second.label == "Profile 2, 2 mappings, in use" }, "Undo restores the previous list: \(second.label)")
        XCTAssertFalse(undo.isEnabled, "one step")
    }
}
