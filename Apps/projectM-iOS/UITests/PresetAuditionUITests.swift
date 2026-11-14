// PresetAuditionUITests.swift — PRE-010-T10 (PRE-010-S4; specs/168-pre-010-quick-audition): quick
// audition on the iOS Simulator. Three Included presets are tagged "Calm" by the Debug seed
// (`-uitestSeedPresetTags`); A is chosen from the chip list (scope "Tagged: Calm"); in the browser two
// others are previewed through the row's touch-and-hold "Preview" (the audition bar names each), then
// Cancel; the browser closes and the controls name A with the tagged scope. Launched with the fixed
// fake entitlement (`-uitestUnlocked NO`) and the reset. Under 30 s (owner rule 7). Simulator results
// are never device evidence (Constitution X).
import XCTest

@MainActor
final class PresetAuditionUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var presetRows: [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).allElementsBoundByIndex
            .map { (row: XCUIElement) -> String in String(row.identifier.dropFirst("preset:".count)) }
    }

    private func openCalmList() {
        app.tapFreshControl("presets")
        let chip = app.buttons["presetTagChip.Calm"]
        XCTAssertTrue(chip.appears(within: 10), "Calm chip")
        if !chip.isSelected { chip.tap() }
        XCTAssertTrue(poll(5) { self.presetRows.count == 3 }, "\(presetRows)")
    }

    private func preview(_ name: String) {
        app.buttons["preset:\(name)"].press(forDuration: 0.7)
        let item = app.buttons["Preview"]   // menu items are found by title (as PresetTagsUITests does)
        XCTAssertTrue(item.appears(within: 5), "Preview in the row's menu")
        item.tap()
        XCTAssertTrue(poll(10) { self.app.staticTexts["auditionName"].exists
                && self.app.staticTexts["auditionName"].label == "Previewing \(name)" }, "bar names \(name)")
    }

    func testPreviewTwoPresetsThenCancelRestoresTheOriginal() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-uitestSeedPresetTags", "Calm:0,1,2"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))

        openCalmList()
        let calm = presetRows
        let original = calm[0]
        app.buttons["preset:\(original)"].tap()   // chosen: the browser closes
        XCTAssertTrue(poll(10) { self.app.staticTexts["currentPreset"].label == original }, "A chosen")
        XCTAssertTrue(app.staticTexts["scopeLine"].label.hasPrefix("Tagged"), app.staticTexts["scopeLine"].label)
        let scopeLine = app.staticTexts["scopeLine"].label

        openCalmList()
        preview(calm[1])
        preview(calm[2])
        app.buttons["auditionCancel"].tap()
        XCTAssertTrue(poll(5) { !self.app.otherElements["auditionBar"].exists && !self.app.staticTexts["auditionName"].exists },
                      "the bar goes away")
        XCTAssertEqual(presetRows, calm, "the browser stayed on the same list")
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["currentPreset"].appears(within: 10))
        XCTAssertEqual(app.staticTexts["currentPreset"].label, original, "the original preset is back")
        XCTAssertEqual(app.staticTexts["scopeLine"].label, scopeLine, "and its scope")
    }
}
