// ScenePackUITests.swift — SCN-014-T09 on the iOS Simulator (SCN-014-S5): with the DEBUG seed
// `-uitestScenePackFixture` ("Pack Scene": a photo, two slides and a logo, one cue), Settings → Show → Scene
// Folders: swipe "Pack Scene" → Export packs it (fixture mode keeps the file instead of the share sheet, research
// SCN-014-D8); Import Scene… reads that pack, the preview says a copy is added with 1 photo, 2 slides and
// 1 logo; Import adds the scene "Pack Scene copy", whose row appears. Simulator results are never device
// evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class ScenePackUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openSceneFolders() {
        let settings = app.buttons["settings"]
        let area = app.otherElements["visualizerTapArea"].firstMatch
        XCTAssertTrue(area.appears(within: 15), "the visualizer is up")
        if !settings.exists { area.tap() }
        XCTAssertTrue(settings.appears(within: 5), "the controls are shown")
        settings.tap()
        let showLink = app.buttons["showEditorLink"]
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(showLink), "the Show row is reachable")
        showLink.tap()
        let foldersLink = app.buttons["showSceneFoldersLink"]
        XCTAssertTrue(foldersLink.appears(within: 5))
        foldersLink.tap()
    }

    func testExportASceneThenImportThePackAndItsCueAppears() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestKeepControls", "-uitestScenePackFixture", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "show"] + Self.noStore
        app.launch()
        openSceneFolders()

        // Export (leading swipe → Export).
        let row = app.descendants(matching: .any)["sceneFolderScene.Pack Scene"].firstMatch
        XCTAssertTrue(row.appears(within: 5), "the seeded scene is listed")
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let export = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "sceneFolderExportScene", "Export Scene")).firstMatch
        XCTAssertTrue(export.appears(within: 3), "Export is offered")
        export.tap()
        let status = app.staticTexts["scenePackStatus"]
        XCTAssertTrue(status.appears(within: 10), "the export result is shown")
        XCTAssertEqual(status.label, "Exported Pack Scene.")

        // Import the pack just exported.
        let importRow = app.buttons["scenePackImportRow"]
        XCTAssertTrue(importRow.appears(within: 3))
        importRow.tap()
        let outcome = app.descendants(matching: .any)["scenePackOutcome"].firstMatch
        XCTAssertTrue(outcome.appears(within: 10), "the preview opens")
        XCTAssertTrue(outcome.label.contains("adds a copy, \"Pack Scene copy\""), outcome.label)
        let media = app.descendants(matching: .any)["scenePackMedia"].firstMatch
        XCTAssertTrue(media.label.contains("1 photo, 2 slides, 1 logo"), media.label)
        app.buttons["scenePackImport"].tap()
        XCTAssertTrue(outcome.disappears(within: 10), "the preview closes")

        let copy = app.descendants(matching: .any)["sceneFolderScene.Pack Scene copy"].firstMatch
        XCTAssertTrue(copy.appears(within: 5), "the imported scene is listed")
        XCTAssertEqual(copy.value as? String, "Scene, 1 cue", "one cue was added for it")
        XCTAssertTrue(status.label.hasPrefix("Imported Pack Scene copy as cue 2."), status.label)
    }
}
