// CueNoteUITests.swift — SHOW-012-T10 on the iOS Simulator (SHOW-012-R5, S3): with the SHOW-001 DEBUG seed
// (`-uitestShowSeed`, five cues), Settings → Show → cue 2's leading swipe More… → Add Note… opens the note sheet; typing a
// note and Save makes the row read ", note <text>" (the row's note line). Simulator results are never device evidence.
// Owner rule 7: under 30 s.
import XCTest

@MainActor
final class CueNoteUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }

    func testAddingANoteShowsTheIndicator() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "show"] + Self.noStore
        app.launch()
        if !controls.appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        let link = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(link), "the Show row is reachable")
        link.tap()
        let second = app.descendants(matching: .any)["showCue2"]
        XCTAssertTrue(second.appears(within: 5))
        XCTAssertFalse((second.value as? String ?? "").contains("note"), "no note yet")

        // A short leading drag (a full swipe would run Go), then More… → Add Note….
        let start = second.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: second.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let more = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "showCueMore", "More Actions")).firstMatch
        XCTAssertTrue(more.appears(within: 3), "More is offered")
        more.tap()
        let add = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "showCueNote", "Add Note…")).firstMatch
        XCTAssertTrue(add.appears(within: 3), "Add Note is offered")
        add.tap()

        let editor = app.textViews["cueNoteEditor"]
        XCTAssertTrue(editor.appears(within: 3), "the note sheet")
        if !editor.hasKeyboardFocus { editor.tap() }
        editor.typeText("Wait for count-in")
        XCTAssertTrue(poll(3) { (self.app.staticTexts["cueNoteCount"].label).hasPrefix("17 of 500") }, "the counter follows")
        app.buttons["cueNoteSave"].tap()
        XCTAssertTrue(app.textViews["cueNoteEditor"].disappears(within: 3), "Save closes the sheet")
        XCTAssertTrue(poll(3) { (second.value as? String)?.hasSuffix(", note Wait for count-in") == true },
                      "the row shows the note: \(second.value ?? "nil")")
    }
}

private extension XCUIElement {
    var hasKeyboardFocus: Bool { (value(forKey: "hasKeyboardFocus") as? Bool) ?? false }
}
