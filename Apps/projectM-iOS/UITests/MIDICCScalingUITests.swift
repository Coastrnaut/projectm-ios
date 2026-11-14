// MIDI-004-T11: a mapping's options screen (MIDI-004-R7, R8, R10; S5). A mapping is seeded by launch argument
// (`cc:0:7=effect.bloom.intensity`, with the DEBUG stand-in MIDI system so no system MIDI is touched); open MIDI
// Mappings, open the mapping's Curve row, toggle Invert, read the preview's spoken description and the row's
// summary. Simulator results are never device evidence; a physical controller is the {device} task MIDI-004-T16.
// Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class MIDICCScalingUITests: XCTestCase {
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

    func testToggleInvertOnASeededMapping() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestFakeMIDI",
                               "-settings.midi.enabled", "YES",
                               "-settings.midi.mappings", "(\"cc:0:7=effect.bloom.intensity\")"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let link = app.buttons["midiMappingsLink"]
        XCTAssertTrue(app.reveal(link, long: true), "the MIDI Mappings row")
        link.tap()
        XCTAssertTrue(app.navigationBars["MIDI Mappings"].appears(within: 5))

        let curveRow = app.buttons["midiCurve.effect.bloom.intensity"]
        XCTAssertTrue(curveRow.appears(within: 5), "the seeded mapping has a Curve row")
        XCTAssertEqual(curveRow.value as? String, "Linear")
        curveRow.tap()
        XCTAssertTrue(app.navigationBars["Glow intensity"].appears(within: 5))

        let invert = app.switches["midiInvert"]
        XCTAssertTrue(invert.appears(within: 5))
        XCTAssertEqual(invert.value as? String, "0")
        let preview = app.descendants(matching: .any)["midiCurvePreview"]
        XCTAssertTrue(app.reveal(preview), "the preview")
        XCTAssertTrue(preview.label.contains("raises the value"), preview.label)
        invert.switches.firstMatch.exists ? invert.switches.firstMatch.tap() : invert.tap()
        XCTAssertTrue(poll(5) { (invert.value as? String) == "1" }, "Invert is on")
        XCTAssertTrue(poll(5) { preview.label.contains("Linear, inverted") && preview.label.contains("lowers the value") },
                      preview.label)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["MIDI Mappings"].appears(within: 5))
        XCTAssertTrue(poll(5) { (curveRow.value as? String) == "Linear, inverted" }, "row: \(String(describing: curveRow.value))")
    }
}
