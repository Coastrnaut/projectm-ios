// SceneFoldersUITests.swift — SCN-004-T11 on the iOS Simulator (SCN-004-S5): with the SHOW-001 DEBUG
// seed (`-uitestShowSeed`: Opening, Build, Drop, Break, Finale), Settings → Show → Scene Folders: New
// Folder "Set A", swipe "Opening" → Move → Set A; "Opening" leaves the top level, and opening "Set A"
// lists it with VoiceOver value "Scene, 1 cue". Simulator results are never device evidence. Owner rule
// 7: under 30 s.
import XCTest

@MainActor
final class SceneFoldersUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// Swipes a row right (a short drag, so a full swipe never runs the first action) and taps one of
    /// its leading actions (the context menu's live blur over the visualizer is slow to settle).
    private func swipeAction(_ row: XCUIElement, id: String, titles: [String]) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let predicate = NSPredicate(format: "identifier == %@ OR label IN %@", id, titles)
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(button.appears(within: 3), "\(id) is offered")
        button.tap()
    }

    func testCreateAFolderMoveASceneIntoItAndFindItThere() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestKeepControls", "-uitestShowSeed", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        let settings = app.buttons["settings"]
        let area = app.otherElements["visualizerTapArea"].firstMatch
        XCTAssertTrue(area.appears(within: 15), "the visualizer is up")
        if !settings.exists { area.tap() }
        XCTAssertTrue(settings.appears(within: 5), "the controls are shown")
        settings.tap()
        let showLink = app.buttons["showEditorLink"]
        // The Show row is the last of a long Settings list: two fast flicks in the right margin (no
        // slider there) get close in about 4 s, where held reveal drags took 15 s (owner rule 7).
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let window = app.windows.firstMatch
        for _ in 0..<2 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.9))
                .press(forDuration: 0.01, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.15)),
                       withVelocity: 6000, thenHoldForDuration: 0)
        }
        XCTAssertTrue(app.reveal(showLink, long: true), "the Show row is reachable")
        showLink.tap()
        let foldersLink = app.buttons["showSceneFoldersLink"]
        XCTAssertTrue(foldersLink.appears(within: 5))
        foldersLink.tap()

        // New Folder "Set A".
        let newFolder = app.buttons["sceneFoldersNewFolder"]
        XCTAssertTrue(newFolder.appears(within: 5))
        newFolder.tap()
        let alert = app.alerts["New Folder"]
        XCTAssertTrue(alert.appears(within: 3), "the New Folder alert")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.appears(within: 2))
        field.typeText("Set A")   // the alert's only field has the focus
        let create = alert.buttons["Create"]
        create.tap()
        if !alert.disappears(within: 1.5) {   // a hardware-keyboard simulator swallows the first tap (SCN-003-T12)
            XCTAssertTrue(create.settles(), "the alert holds still")
            create.tap()
        }
        XCTAssertTrue(alert.disappears(within: 3))
        let folderRow = app.descendants(matching: .any)["sceneFolderRow.Set A"].firstMatch
        XCTAssertTrue(folderRow.appears(within: 3), "the folder is listed")

        // Move "Opening" into it.
        let opening = app.descendants(matching: .any)["sceneFolderScene.Opening"].firstMatch
        XCTAssertTrue(opening.appears(within: 3))
        swipeAction(opening, id: "sceneFolderMoveScene", titles: ["Move", "Move to"])
        let top = app.buttons["sceneFolderDestination.top"]
        XCTAssertTrue(top.appears(within: 3), "the Move to… sheet")
        XCTAssertFalse(top.isEnabled, "the current folder cannot be chosen")
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "sceneFolderDestination.", "sceneFolderDestination.top")
        let destination = app.buttons.matching(predicate).firstMatch
        XCTAssertEqual(destination.label, "Set A")
        XCTAssertTrue(destination.appears(within: 3))
        destination.tap()
        XCTAssertTrue(opening.disappears(within: 3), "Opening left the top level")
        XCTAssertTrue(poll(3) { (folderRow.value as? String) == "Folder, 1 scene, 0 folders" }, "value: \(folderRow.value ?? "nil")")

        // Open "Set A": Opening is there.
        folderRow.tap()
        XCTAssertTrue(app.navigationBars["Set A"].appears(within: 3))
        let inside = app.descendants(matching: .any)["sceneFolderScene.Opening"].firstMatch
        XCTAssertTrue(inside.appears(within: 3), "the scene is in the folder")
        XCTAssertEqual(inside.value as? String, "Scene, 1 cue")
    }
}
