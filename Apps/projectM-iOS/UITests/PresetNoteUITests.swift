// PresetNoteUITests.swift — PRE-011-T10 (spec PRE-011-S4; contract C3): a private note on the iOS Simulator. Open the
// Included list, touch and hold a preset, choose Note…, type a note (the count follows), Save; the row's VoiceOver
// label then ends with ", has note", and reopening the sheet shows the text. Launched with the fixed fake entitlement
// (`-uitestUnlocked NO`) and the reset flag (which removes `PresetCollections/`, notes included). Under 30 s (owner
// rule 7). Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class PresetNoteUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openNote(_ row: XCUIElement) {
        row.press(forDuration: 0.7)
        let action = app.buttons["Note…"]
        XCTAssertTrue(action.appears(within: 5))
        action.tap()
        XCTAssertTrue(app.textViews["presetNoteText"].appears(within: 5))
    }

    func testAddingANoteShowsItOnTheRow() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))
        app.tapFreshControl("presets")
        let included = app.buttons["node:included"]
        XCTAssertTrue(included.appears(within: 10))
        included.tap()

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch
        XCTAssertTrue(row.appears(within: 10))
        let identifier: String = row.identifier
        XCTAssertFalse(row.label.hasSuffix(", has note"))

        openNote(row)
        let field = app.textViews["presetNoteText"]
        field.tap()
        field.typeText("Slow build for the intro")
        XCTAssertTrue(poll(3) { self.app.staticTexts["presetNoteCount"].label.hasPrefix("24 of 2,000") }, app.staticTexts["presetNoteCount"].label)
        app.buttons["presetNoteSave"].tap()

        let noted = app.buttons[identifier]
        XCTAssertTrue(poll(5) { noted.exists && noted.label.hasSuffix(", has note") }, noted.label)
        openNote(noted)
        XCTAssertEqual(app.textViews["presetNoteText"].value as? String, "Slow build for the intro")
        XCTAssertTrue(app.buttons["presetNoteDelete"].exists)
    }
}
