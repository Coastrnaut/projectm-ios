// PresetCompareUITests.swift — PRE-009-T11 (spec PRE-009-S4; specs/235-pre-009-preset-comparison): in the browser,
// "Compare…" on one Calm preset and "Compare with <A>" on another open the Compare sheet with both names; Play B
// plays B and closes the sheet and the browser. Three Included presets are tagged "Calm" by the Debug seed. Launched
// with the fixed fake entitlement (`-uitestUnlocked NO`) and the reset. Under 30 s (owner rule 7). Simulator results
// are never device evidence (Constitution X).
import XCTest

@MainActor
final class PresetCompareUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var presetRows: [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).allElementsBoundByIndex
            .map { (row: XCUIElement) -> String in String(row.identifier.dropFirst("preset:".count)) }
    }

    /// Touch and hold the row, then the menu item with this title (menu items are found by title).
    private func menu(_ name: String, _ title: String) {
        app.pressRow(app.buttons["preset:\(name)"], clearOf: app.otherElements["compareBar"])
        let item = app.buttons[title]
        XCTAssertTrue(item.appears(within: 5), "\(title) in the row's menu")
        item.tap()
    }

    func testCompareTwoPresetsThenPlayB() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-uitestSeedPresetTags", "Calm:0,1,2"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))
        let current = app.staticTexts["currentPreset"].exists ? app.staticTexts["currentPreset"].label : ""

        app.tapFreshControl("presets")
        let chip = app.buttons["presetTagChip.Calm"]
        XCTAssertTrue(chip.appears(within: 10), "Calm chip")
        if !chip.isSelected { chip.tap() }
        XCTAssertTrue(poll(5) { self.presetRows.count == 3 }, "\(presetRows)")
        let candidates = presetRows.filter { (name: String) -> Bool in name != current }
        XCTAssertGreaterThanOrEqual(candidates.count, 2)
        let a = candidates[0]
        let b = candidates[1]

        menu(a, "Compare…")
        XCTAssertTrue(app.staticTexts["comparePending"].appears(within: 5), "the pick bar")
        XCTAssertTrue(app.staticTexts["comparePending"].label.contains(a))
        menu(b, "Compare with \(a)")

        XCTAssertTrue(app.staticTexts["compareNameA"].appears(within: 10), "the Compare sheet")
        XCTAssertEqual(app.staticTexts["compareNameA"].label, "A · \(a)")
        XCTAssertEqual(app.staticTexts["compareNameB"].label, "B · \(b)")
        let paneB = app.descendants(matching: .any)["comparePaneB"]
        XCTAssertTrue(paneB.appears(within: 5), "pane B")
        // The previews draw live: B leaves "loading" once its first frame arrives (shader compiles take seconds here).
        XCTAssertTrue(poll(15) { paneB.label == "Preview B, \(b)" }, paneB.label)
        app.buttons["compareChooseB"].tap()

        XCTAssertTrue(poll(15) { self.app.staticTexts["currentPreset"].exists && self.app.staticTexts["currentPreset"].label == b },
                      "B plays and the browser closed")
        XCTAssertFalse(app.buttons["compareChooseB"].exists)
    }
}

extension XCUIApplication {
    /// Touches and holds a browser row, first dragging the list up (in the right margin, as `reveal`) while the row
    /// reaches under a bottom bar, which would otherwise take the press. Since the PRE-004/PRE-005 chip rows the third
    /// row of a short list sits under the audition or compare bar on an iPhone 17 (found 2026-11-14, PRE-009).
    func pressRow(_ row: XCUIElement, clearOf bar: XCUIElement) {
        var drags = 0
        while bar.exists && row.frame.maxY > bar.frame.minY - 4 && drags < 3 {
            let start = coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.62))
            start.press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.42)))
            drags += 1
        }
        row.press(forDuration: 0.7)
    }
}
