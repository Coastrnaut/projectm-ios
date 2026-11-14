// CueTransitionUITests.swift — SCN-007-T12 on the iOS Simulator (SCN-007-S6): with the SHOW-001 DEBUG seed
// (`-uitestShowSeed`, five cues), Settings → Show → cue 2's Transition sheet sets Crossfade, a duration and
// Ease Out; after a relaunch without the seed or `-uitestResetNotice` (the show is read from disk) cue 2 reads the same transition (type,
// duration and easing in its VoiceOver value). Simulator results are never device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class CueTransitionUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }

    private func openShowEditor() {
        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
        app.buttons["settings"].tap()
        let link = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(link), "the Show row is reachable")
        link.tap()
    }

    /// A short drag so a full swipe never runs Go (as SceneDuplicateUITests).
    private func openTransition(_ row: XCUIElement) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let button = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "showCueTransition", "Transition")).firstMatch
        XCTAssertTrue(button.appears(within: 3), "Transition is offered")
        button.tap()
        XCTAssertTrue(app.navigationBars["Transition"].appears(within: 3), "the Transition sheet")
    }

    private func choose(_ picker: String, _ option: String) {
        let row = app.buttons[picker]
        XCTAssertTrue(row.appears(within: 3), picker)
        row.tap()
        let item = app.buttons[option].firstMatch.exists ? app.buttons[option].firstMatch : app.staticTexts[option].firstMatch
        XCTAssertTrue(item.appears(within: 3), "\(option) is listed")
        item.tap()
        XCTAssertTrue(app.navigationBars["Transition"].appears(within: 3), "back on the sheet")
    }

    func testACueTransitionPersistsAcrossARelaunch() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "show"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openShowEditor()
        let second = app.descendants(matching: .any)["showCue2"]
        XCTAssertTrue(second.appears(within: 5))
        XCTAssertEqual(second.value as? String, "Cue 2 of 5", "no transition yet")
        openTransition(second)

        choose("cueTransitionType", "Crossfade")
        let slider = app.slider("cueTransitionDurationSlider")   // ACC-005 makes it an adjustable element
        XCTAssertTrue(slider.appears(within: 3))
        slider.dragSlider(from: 0.1, to: 0.3)   // 1 s of 0…10 s sits at a tenth
        let readout = app.staticTexts["cueTransitionDurationValue"]
        XCTAssertTrue(poll(3) { readout.label != "1 s" }, "the duration moved: \(readout.label)")
        let seconds = readout.label   // e.g. "2.5 s"
        choose("cueTransitionEasing", "Ease Out")
        app.buttons["cueTransitionDone"].tap()
        XCTAssertTrue(app.navigationBars["Transition"].disappears(within: 3))
        let expected = "Cue 2 of 5, transition Crossfade " + seconds.replacingOccurrences(of: " s", with: " seconds") + ", Ease Out"
        XCTAssertTrue(poll(3) { (second.value as? String) == expected }, "set: \(second.value ?? "nil") vs \(expected)")

        // Relaunch without the seed and without the reset (which removes the show folder): the show comes from disk.
        app.terminate()
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "show"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openShowEditor()
        let reopened = app.descendants(matching: .any)["showCue2"]
        XCTAssertTrue(reopened.appears(within: 5))
        // The row's value carries the type, the duration and the easing (the sheet reads the same model).
        XCTAssertEqual(reopened.value as? String, expected, "the transition is restored")
    }
}
