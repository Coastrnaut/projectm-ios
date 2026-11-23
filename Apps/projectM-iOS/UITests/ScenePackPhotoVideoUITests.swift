// ScenePackPhotoVideoUITests.swift — FILE-001-T19's export and import on the iOS Simulator (the device test is
// B07FilesDeviceTests.testFILE001_A/B). With the stored photo and video seeded (`-uitestSeedPhoto pattern
// -uitestSeedVideo counter`) and `-uitestPhotoVideoScene` ("Photo and Video": the photo under the video, one cue),
// Scene Folders' Export packs the scene (fixture mode keeps the file, `-uitestScenePackKeepExport`); Import Scene…
// reads that pack and the preview lists 1 photo and 1 video; Import adds the copy. Simulator results are never
// device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class ScenePackPhotoVideoUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testASceneWithThePhotoAndTheVideoExportsAndPreviewsBoth() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestKeepControls", "-autostart", "inAppPlayback", "-settings.visual", "video",
                               "-uitestSeedPhoto", "pattern", "-uitestSeedVideo", "counter", "-uitestPhotoVideoScene",
                               "-uitestScenePackKeepExport", "-uitestSettingsSection", "show"] + Self.noStore
        app.launch()
        let video = app.descendants(matching: .any)["videoVisual"].firstMatch
        XCTAssertTrue(video.appears(within: 15), "the Video visual is up")
        let playing = NSPredicate(format: "value == %@", "Video 64 × 48")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: playing, evaluatedWith: video)], timeout: 15), .completed,
                       "the seeded video plays: \(video.value as? String ?? "")")

        let area = app.otherElements["visualizerTapArea"].firstMatch
        let settings = app.buttons["settings"]
        if !settings.exists { area.tap() }
        XCTAssertTrue(settings.appears(within: 5), "the controls are shown")
        settings.tap()
        let showLink = app.buttons["showEditorLink"]
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(showLink), "the Show row is reachable")
        showLink.tap()
        let foldersLink = app.buttons["showSceneFoldersLink"]
        XCTAssertTrue(foldersLink.appears(within: 5), "Scene Folders (the seeded scene has a cue)")
        foldersLink.tap()

        let row = app.descendants(matching: .any)["sceneFolderScene.Photo and Video"].firstMatch
        XCTAssertTrue(row.appears(within: 5), "the seeded scene is listed")
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let export = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "sceneFolderExportScene", "Export Scene")).firstMatch
        XCTAssertTrue(export.appears(within: 3), "Export is offered")
        export.tap()
        let status = app.staticTexts["scenePackStatus"]
        XCTAssertTrue(status.appears(within: 10), "the export result is shown")
        XCTAssertEqual(status.label, "Exported Photo and Video.")

        let importRow = app.buttons["scenePackImportRow"]
        XCTAssertTrue(importRow.appears(within: 3))
        importRow.tap()
        let media = app.descendants(matching: .any)["scenePackMedia"].firstMatch
        XCTAssertTrue(media.appears(within: 10), "the preview opens")
        XCTAssertTrue(media.label.contains("1 photo") && media.label.contains("1 video"), media.label)
        app.buttons["scenePackImport"].tap()
        XCTAssertTrue(media.disappears(within: 10), "the preview closes")
        XCTAssertTrue(status.label.hasPrefix("Imported Photo and Video copy as cue"), status.label)
    }
}
