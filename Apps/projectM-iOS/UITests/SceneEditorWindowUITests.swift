// SceneEditorWindowUITests.swift — UIX-008-T13 on an iPad simulator (UIX-008-S6; contract W1, W3, W6): with the
// SHOW-001 DEBUG seed, Settings → Show → Scene Folders, swipe "Opening" → Open in New Window: a scene editor window
// opens; rename the scene and lower its first layer's opacity; the "Unsaved changes" marker shows; Save; the
// hidden file probe (`-uitestSceneEditorProbe`) reads the stored file with the new name and opacity, and the marker
// is gone. Two windows side by side need Stage Manager on a device (UIX-008-T16 {device}). iPad only: on iPhone
// the action is not offered. Simulator results are never device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class SceneEditorWindowUITests: XCTestCase {
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

    /// Swipes the row right and taps "Open in New Window" among its leading actions.
    private func openInNewWindow(_ row: XCUIElement) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", "sceneFolderOpenWindow", "Open in New Window")
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(button.appears(within: 3), "Open in New Window is offered on iPad")
        button.tap()
    }

    func testOpenASceneInANewWindowEditAndSaveItsFile() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("multiple windows are an iPadOS feature") }
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestKeepControls", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "show", "-uitestSceneEditorProbe"] + Self.noStore
        app.launch()
        openSceneFolders()
        let opening = app.descendants(matching: .any)["sceneFolderScene.Opening"].firstMatch
        XCTAssertTrue(opening.appears(within: 5))
        openInNewWindow(opening)

        // The editor window.
        let name = app.textFields["sceneEditorName"]
        XCTAssertTrue(name.appears(within: 8), "the scene editor window opened")
        let probe = app.descendants(matching: .any)["sceneEditorFileProbe"].firstMatch
        XCTAssertTrue(probe.appears(within: 3))
        let before: String = probe.value as? String ?? ""
        XCTAssertTrue(before.hasPrefix("name=Opening;"), "probe: \(before)")

        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()   // the cursor after "Opening"
        name.typeText(" Two\n")
        let slider = app.slider("sceneEditorOpacity.1")   // ACC-005: an adjustable element, not a slider
        XCTAssertTrue(slider.appears(within: 3))
        slider.dragSlider(from: 1, to: 0.3)
        XCTAssertTrue(app.descendants(matching: .any)["sceneEditorDirty"].firstMatch.appears(within: 3), "unsaved changes shown")

        app.buttons["sceneEditorSave"].tap()
        XCTAssertTrue(poll(5) { ((probe.value as? String) ?? "").hasPrefix("name=Opening Two;") }, "probe: \(probe.value ?? "nil")")
        let after: String = probe.value as? String ?? ""
        XCTAssertFalse(after.hasSuffix("opacity=1.00"), "the stored opacity changed: \(after)")
        XCTAssertNotEqual(after, before)
        XCTAssertTrue(app.descendants(matching: .any)["sceneEditorDirty"].firstMatch.disappears(within: 3), "saved")
    }
}
