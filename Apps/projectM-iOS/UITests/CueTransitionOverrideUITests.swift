// CueTransitionOverrideUITests.swift — SHOW-004-T09 on the iOS Simulator (SHOW-004-S4): with the SHOW-001 DEBUG seed
// (`-uitestShowSeed`, five cues), Settings → Show → cue 2's "Into" swipe action opens Transition Into This Cue; choosing
// Cut makes the row read ", into this cue Cut"; "Use Scene Default" removes it. Simulator results are never device
// evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class CueTransitionOverrideUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private static let sheetTitle = "Transition Into This Cue"

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

    /// A short drag so a full swipe never runs Go (as CueTransitionUITests).
    private func openOverride(_ row: XCUIElement) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        // The cue's edit actions are in the leading swipe's More… dialog (show editor fix, 2026-11-14).
        let more = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "showCueMore", "More Actions")).firstMatch
        XCTAssertTrue(more.appears(within: 3), "More is offered")
        more.tap()
        let button = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "showCueTransitionOverride",
                                                      Self.sheetTitle + "…")).firstMatch
        XCTAssertTrue(button.appears(within: 3), "Transition Into This Cue is offered")
        button.tap()
        XCTAssertTrue(app.navigationBars[Self.sheetTitle].appears(within: 3), "the override sheet")
    }

    private func chooseType(_ option: String) {
        let row = app.buttons["cueTransitionType"]
        XCTAssertTrue(row.appears(within: 3))
        row.tap()
        let item = app.buttons[option].firstMatch.exists ? app.buttons[option].firstMatch : app.staticTexts[option].firstMatch
        XCTAssertTrue(item.appears(within: 3), "\(option) is listed")
        item.tap()
        XCTAssertTrue(app.navigationBars[Self.sheetTitle].appears(within: 3), "back on the sheet")
        app.buttons["cueTransitionDone"].tap()
        XCTAssertTrue(app.navigationBars[Self.sheetTitle].disappears(within: 3))
    }

    func testSettingAndClearingACueOverride() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "show"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openShowEditor()
        let second = app.descendants(matching: .any)["showCue2"]
        XCTAssertTrue(second.appears(within: 5))
        XCTAssertEqual(second.value as? String, "Cue 2 of 5", "no override yet")

        openOverride(second)
        chooseType("Cut")
        XCTAssertTrue(poll(3) { (second.value as? String) == "Cue 2 of 5, into this cue Cut" }, "set: \(second.value ?? "nil")")

        openOverride(second)
        chooseType("Use Scene Default")
        XCTAssertTrue(poll(3) { (second.value as? String) == "Cue 2 of 5" }, "cleared: \(second.value ?? "nil")")
    }
}
