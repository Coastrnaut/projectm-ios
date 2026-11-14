// RecentPresetsUITests.swift — PRE-006-T15 (PRE-006-S4; specs/159-pre-006-recent-history): the recently
// played history on the iOS Simulator. Two presets each stay on screen for more than 3 s (the launch
// preset, then Next); both are listed in the browser's Recently Played, newest first. One is starred
// there; Clear History (confirmed) empties the list, and Favorites still lists the starred preset.
// Launched with the fixed fake entitlement (`-uitestUnlocked NO`), the reset (no history) and the opt-in
// switch turned on through the launch arguments.
// Under 30 s (owner rule 7). Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class RecentPresetsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// The preset rows on screen, top to bottom (names).
    private var presetRows: [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).allElementsBoundByIndex
            .map { (row: XCUIElement) -> String in String(row.identifier.dropFirst("preset:".count)) }
    }

    func testPlayedPresetsAreListedAndClearKeepsFavorites() {
        XCUIDevice.shared.orientation = .portrait
        // History is opt-in: the argument domain turns "Remember Recently Played" on for this launch only.
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-settings.recentPresets.enabled", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))
        Thread.sleep(forTimeInterval: 3.5)   // the launch preset stays more than 3 s (PRE-006-R2)
        app.tapFreshControl("next")
        Thread.sleep(forTimeInterval: 3.5)   // so does the next one

        app.tapFreshControl("presets")
        let recentRow = app.buttons["node:recent"]
        XCTAssertTrue(recentRow.appears(within: 10), "Recently Played on the library home")
        XCTAssertTrue(app.reveal(recentRow))
        XCTAssertEqual(recentRow.label, "Recently Played, 2 presets")
        recentRow.tap()
        XCTAssertTrue(poll(5) { self.presetRows.count == 2 }, "\(presetRows)")
        let played = presetRows
        XCTAssertEqual(Set(played).count, 2, "two different presets")

        let starred = played[1]
        app.buttons["star:\(starred)"].tap()
        XCTAssertEqual(app.buttons["star:\(starred)"].label, "Remove from favorites")

        app.buttons["recentClear"].tap()
        let confirm = app.alerts.buttons["Clear History"]
        XCTAssertTrue(confirm.appears(within: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["recentEmpty"].appears(within: 5), "Recent is empty after Clear")
        XCTAssertEqual(presetRows, [])

        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to the library home
        XCTAssertTrue(recentRow.appears(within: 5))
        XCTAssertEqual(recentRow.label, "Recently Played, 0 presets")
        app.segmentedControls.buttons["Favorites"].tap()
        XCTAssertTrue(app.buttons["preset:\(starred)"].appears(within: 5), "Favorites still lists its item")
    }
}
