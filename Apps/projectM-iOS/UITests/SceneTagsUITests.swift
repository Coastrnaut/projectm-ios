// SceneTagsUITests.swift — SCN-005-T12 on the iOS Simulator (SCN-005-S5): with the SHOW-001 DEBUG seed
// (`-uitestShowSeed`: Opening, Build, Drop, Break, Finale), open the switcher (⌘K), tag cue 1 "Intro"
// through its row's tag button and the Tags sheet, select the "Intro" chip and see only cue 1.
// Simulator results are never device evidence. Owner rule 7: under 30 s; UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class SceneTagsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var count: XCUIElement { app.staticTexts["sceneSwitcherCount"] }
    private func entry(_ n: Int) -> XCUIElement { app.buttons["sceneSwitcherEntry.\(n)"] }

    func testTagASceneAndFilterTheSwitcherByIt() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestUnlocked", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15), "the visualizer is up")

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.textFields["sceneSwitcherField"].appears(within: 3), "⌘K opens the switcher")
        XCTAssertTrue(poll(2) { self.count.label == "5 scenes" }, "five cues: \(count.label)")
        XCTAssertFalse(app.descendants(matching: .any)["sceneSwitcherTags"].exists, "no chips before any tag")

        // Tag cue 1 "Intro" in the Tags sheet.
        let tagButton = app.buttons["sceneSwitcherTagsButton.1"]
        XCTAssertTrue(tagButton.appears(within: 3))
        XCTAssertEqual(tagButton.label, "Tags for Opening")
        tagButton.tap()
        let field = app.textFields["sceneTagField"]
        XCTAssertTrue(field.appears(within: 3), "the Tags sheet")
        field.tap()
        field.typeText("Intro")
        let add = app.buttons["sceneTagAdd"]
        XCTAssertTrue(add.isEnabled)
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any)["sceneTag.Intro"].appears(within: 3), "the tag is listed")
        app.buttons["sceneTagsDone"].tap()
        XCTAssertTrue(field.disappears(within: 3), "the sheet closed")

        // Filter by the "Intro" chip: only cue 1.
        let chip = app.buttons["sceneSwitcherTag.Intro"]
        XCTAssertTrue(chip.appears(within: 3), "the chip row shows the new tag")
        XCTAssertTrue(app.reveal(chip), "the chip is on screen (no navigation bar over the visualizer, so not `down`)")
        XCTAssertEqual(chip.value as? String, "1 scene")
        chip.tap()
        XCTAssertTrue(poll(3) { self.count.label == "1 scene" }, "count: \(count.label)")
        XCTAssertTrue(entry(1).exists, "the tagged scene is listed")
        XCTAssertFalse(entry(2).exists, "an untagged scene is not")
        XCTAssertTrue(chip.isSelected, "the chip reads as selected")
        XCTAssertTrue((entry(1).value as? String)?.hasSuffix("tags Intro") ?? false, "value: \(entry(1).value ?? "nil")")
    }
}
