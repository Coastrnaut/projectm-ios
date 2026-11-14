// PresetTagsUITests.swift — PRE-003-T12, T14 (PRE-003-S1; specs/149-pre-003-preset-tags): preset tags
// on the iOS Simulator. (1) The roadmap acceptance with a real relaunch: Included presets tagged by the
// Debug seed (`-uitestSeedPresetTags`, saved through the real store), a chip filters the browser to
// exactly them, the app is terminated and relaunched without the reset, and the same chips give the
// same rows. (2) Tagging through a row's Tags… sheet. Launched with the fixed fake entitlement
// (`-uitestUnlocked NO`); Included presets only. Each test is under 30 s (owner rule 7). Simulator
// results are never device evidence (Constitution X).
import XCTest

@MainActor
final class PresetTagsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func start(reset: Bool, extraArguments: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : [])
            + ["-uitestDiagnostics", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback"] + extraArguments
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))
    }

    private func openBrowser() {
        app.tapFreshControl("presets")
        XCTAssertTrue(app.buttons["node:included"].appears(within: 10), "library home")
    }

    private func chip(_ tag: String) -> XCUIElement { app.buttons["presetTagChip.\(tag)"] }

    /// The preset rows on screen, top to bottom (names).
    private var presetRows: [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).allElementsBoundByIndex
            .map { String($0.identifier.dropFirst("preset:".count)) }
    }

    private func rows(after tags: [String]) -> [String] {
        for tag in tags {
            XCTAssertTrue(chip(tag).appears(within: 5), tag)
            chip(tag).tap()
        }
        XCTAssertTrue(app.buttons["presetTagClear"].appears(within: 5))
        _ = poll(3) { !self.presetRows.isEmpty }
        return presetRows
    }

    func testTagFilterGivesTheSameRowsAfterRelaunch() {
        start(reset: true, extraArguments: ["-uitestSeedPresetTags", "Calm:0,1,2|Slow:1"])
        openBrowser()
        let calm = rows(after: ["Calm"])
        XCTAssertEqual(calm.count, 3, "\(calm)")
        XCTAssertEqual(calm, calm.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "alphabetical")
        let both = rows(after: ["Slow"])
        XCTAssertEqual(both.count, 1)
        XCTAssertTrue(calm.contains(both[0]))

        app.terminate()
        start(reset: false)
        openBrowser()
        XCTAssertFalse(app.buttons["presetTagClear"].exists, "chips are not stored")
        XCTAssertEqual(rows(after: ["Calm"]), calm)
        XCTAssertEqual(rows(after: ["Slow"]), both)
    }

    func testTaggingThroughTheSheetAddsAChip() {
        start(reset: true)
        openBrowser()
        app.buttons["node:included"].tap()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch
        XCTAssertTrue(first.appears(within: 5))
        let name = String(first.identifier.dropFirst("preset:".count))
        first.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Tags…"].appears(within: 5))
        app.buttons["Tags…"].tap()
        let field = app.textFields["presetTagField"]
        XCTAssertTrue(field.appears(within: 5))
        field.tap()
        field.typeText("Calm\n")
        XCTAssertTrue(app.descendants(matching: .any)["presetTag.Calm"].appears(within: 5))
        app.buttons["presetTagsDone"].tap()
        let row = app.buttons["preset:\(name)"]
        XCTAssertTrue(poll(5) { row.exists && row.label.hasSuffix(", tags Calm") }, "the row carries its tag: \(row.label)")
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to the home
        XCTAssertEqual(rows(after: ["Calm"]), [name])
    }
}
