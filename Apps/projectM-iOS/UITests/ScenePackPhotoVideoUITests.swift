// ScenePackPhotoVideoUITests.swift — FILE-001-T19's export and import on the iOS Simulator (the device test is
// B07FilesDeviceTests.testFILE001_A/B). With the stored photo and video seeded (`-uitestSeedPhoto pattern
// -uitestSeedVideo counter`) and `-uitestPhotoVideoScene` ("Photo and Video": the photo under the video, one cue),
// Scene Folders' Export packs the scene (fixture mode keeps the file, `-uitestScenePackKeepExport`); Import Scene…
// reads that pack and the preview lists 1 photo and 1 video; Import adds the copy. The second test is the device's
// fresh-install import (B07FilesDeviceTests.testFILE001_B on D3): after the export the app relaunches with its media and
// show reset, imports the kept pack (fixture mode reads it after the relaunch), goes to the imported cue and must show
// that scene's photo, then play its video under the Video visual (SHOW-001 Clarification 2026-11-23). Simulator
// results are never device evidence. Owner rule 7: the first about 20-25 s; the second needs two launches and an
// export (about 50 s on the shared Mac, 2026-11-23), the cost of reproducing a fresh install.
import XCTest

@MainActor
final class ScenePackPhotoVideoUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// Seeds the photo, the video and the scene "Photo and Video", opens Scene Folders and exports the scene (kept).
    private func exportPhotoVideoScene() -> XCUIElement {
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

        return status
    }

    func testASceneWithThePhotoAndTheVideoExportsAndPreviewsBoth() {
        let status = exportPhotoVideoScene()
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

    /// FILE-001-T19 on D3 (2026-11-23): a fresh install imports the pack, goes to its cue, shows its photo, plays its video.
    func testAnImportedSceneShowsItsPhotoAndPlaysItsVideoOnAFreshInstall() {
        _ = exportPhotoVideoScene()
        app.terminate()
        app.launchArguments = ["-uitestResetNotice", "-uitestKeepControls", "-autostart", "inAppPlayback", "-settings.visual", "circularSpectrum",
                               "-uitestScenePackKeepExport", "-uitestSettingsSection", "show", "-uitestSettingsSectionOnce"] + Self.noStore
        app.launch()   // Once: the later Settings open at the top, where the visual rows are (D3 lost them below Show)
        let area = app.otherElements["visualizerTapArea"].firstMatch
        let settings = app.buttons["settings"]
        XCTAssertTrue(area.appears(within: 15), "the visualizer is up")
        if !settings.exists { area.tap() }
        XCTAssertTrue(settings.appears(within: 5), "the controls are shown")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let showLink = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(showLink), "the Show row is reachable")
        showLink.tap()
        let add = app.buttons["showAddCurrentScene"]
        XCTAssertTrue(add.appears(within: 5) && app.reveal(add), "Add Current Scene (Scene Folders shows once the show has a cue)")
        add.tap()
        let foldersLink = app.buttons["showSceneFoldersLink"]
        XCTAssertTrue(foldersLink.appears(within: 5) && app.reveal(foldersLink), "Scene Folders")
        foldersLink.tap()
        let importRow = app.buttons["scenePackImportRow"]
        XCTAssertTrue(importRow.appears(within: 5))
        importRow.tap()
        let media = app.descendants(matching: .any)["scenePackMedia"].firstMatch
        XCTAssertTrue(media.appears(within: 10), "the preview opens")
        XCTAssertTrue(media.label.contains("1 photo") && media.label.contains("1 video"), media.label)
        app.buttons["scenePackImport"].tap()
        let status = app.staticTexts["scenePackStatus"]
        XCTAssertTrue(poll(10) { status.exists && status.label.hasPrefix("Imported") }, status.exists ? status.label : "no status")
        XCTAssertTrue(status.label.hasSuffix("as cue 2."), status.label)

        // Back to the Show Editor, cue 2 (the import) › Go, back to Settings › Done.
        app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch.tap()
        let cue = app.descendants(matching: .any)["showCue2"].firstMatch
        XCTAssertTrue(cue.appears(within: 5) && app.reveal(cue), "the imported cue is listed")
        cue.swipeRight()
        let go = app.buttons["Go"].firstMatch
        XCTAssertTrue(go.appears(within: 3), "Go on cue 2")
        go.tap()
        let back = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
        if back.appears(within: 2) { back.tap() }
        let done = app.navigationBars["Settings"].buttons["Done"]
        XCTAssertTrue(done.appears(within: 5))
        done.tap()

        let photo = app.descendants(matching: .any)["photoVisual"].firstMatch
        XCTAssertTrue(photo.appears(within: 10), "the cue applies the Photo visual")
        XCTAssertTrue(poll(15) { (photo.value as? String) == "Photo 256 × 192" }, "the scene's photo shows: \(photo.value as? String ?? "")")

        if !settings.exists { area.tap() }
        XCTAssertTrue(settings.appears(within: 5))
        settings.tap()
        let videoRow = app.visualRow("Video")
        XCTAssertTrue(app.reveal(videoRow), "the Video row (Settings opens at its top again)")
        videoRow.tap()
        XCTAssertTrue(done.appears(within: 3))
        done.tap()
        let video = app.descendants(matching: .any)["videoVisual"].firstMatch
        XCTAssertTrue(video.appears(within: 10), "the Video visual is up")
        XCTAssertTrue(poll(15) { (video.value as? String) == "Video 64 × 48" }, "the scene's video plays: \(video.value as? String ?? "")")
    }
}
