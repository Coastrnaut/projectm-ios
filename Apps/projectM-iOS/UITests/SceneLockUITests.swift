// SceneLockUITests.swift — SCN-015-T09 (US1-US3; R2, R5-R7; S5) on the iOS Simulator: with the DEBUG show seed (five
// cues, standing on cue 1), Lock scene in the controls shows the "Scene locked" badge; in Settings › Show a swipe left
// on a cue offers no Delete and the cue stays; Next in the controls still advances to cue 2; Unlock asks first, and
// Unlock removes the badge. Simulator results are never device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class SceneLockUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var status: XCUIElement { app.staticTexts["showCueStatus"] }
    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }
    private var badge: XCUIElement { app.descendants(matching: .any)["sceneLockBadge"].firstMatch }

    private func showControls() {
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
    }

    func testLockedSceneIgnoresSwipeDeleteButNextAdvancesThenUnlocks() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "show"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        XCTAssertFalse(badge.exists, "unlocked by default")

        // Lock: one tap, the badge shows.
        let lock = app.buttons["lockScene"]
        XCTAssertTrue(lock.appears(within: 3))
        XCTAssertEqual(lock.value as? String, "Unlocked")
        lock.tap()
        XCTAssertTrue(badge.appears(within: 3), "the Scene locked badge shows")

        // Swipe-delete on a cue does nothing.
        showControls()
        app.buttons["settings"].tap()
        let link = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(link), "the Show row is reachable")
        link.tap()
        let first = app.descendants(matching: .any)["showCue1"]
        XCTAssertTrue(first.appears(within: 5))
        XCTAssertTrue(app.descendants(matching: .any)["sceneLockNote"].exists, "the editor says the scene is locked")
        XCTAssertFalse(app.buttons["showAddCurrentScene"].isEnabled, "Add Current Scene is disabled")
        first.swipeLeft()
        XCTAssertFalse(app.buttons["Delete"].appears(within: 1), "no Delete action while locked")
        XCTAssertEqual(first.label, "Opening", "the cue stays")
        XCTAssertTrue(app.descendants(matching: .any)["showCue5"].exists, "all five cues remain")
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to Settings
        app.navigationBars["Settings"].buttons["Done"].tap()

        // Next still advances the cue.
        showControls()
        app.buttons["showNextCue"].tap()
        XCTAssertTrue(poll(3) { (self.status.value as? String) == "Cue 2 of 5, Build" }, "Next advances while locked")

        // Unlock asks first.
        showControls()
        let unlock = app.buttons["lockScene"]
        XCTAssertEqual(unlock.label, "Unlock scene")
        unlock.tap()
        let confirm = app.buttons["sceneUnlockConfirm"].firstMatch
        XCTAssertTrue(confirm.appears(within: 3), "Unlock scene? asks first")
        XCTAssertTrue(badge.exists, "still locked while asking")
        confirm.tap()
        XCTAssertTrue(poll(3) { !self.badge.exists }, "unlocked")
    }
}
