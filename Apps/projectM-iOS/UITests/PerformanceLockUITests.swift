// PerformanceLockUITests.swift — SHOW-015-T10 (US1-US3; R2, R4-R6; S4) on the iOS Simulator: with two seeded preset
// collections, Lock scene in the controls; the preset browser's Collections screen shows the lock note, no Edit button
// (no drag reorder) and no Delete on a swipe, while New Collection stays; back on the visualizer the emergency Black out
// still blacks out and Restore returns; Unlock asks first and removes the badge. Simulator results are never device
// evidence (SHOW-015-T12 is). Owner rule 7: under 30 s; UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class PerformanceLockUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var badge: XCUIElement { app.descendants(matching: .any)["sceneLockBadge"].firstMatch }
    private var output: String? { app.staticTexts["outputBlackout"].value as? String }

    func testLockHidesDeleteAndReorderButBlackoutWorksThenUnlocks() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSeedCollections", "Friday set:0,1|Second:"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))

        // Lock: one tap in the controls.
        app.tapFreshControl("lockScene")
        XCTAssertTrue(badge.appears(within: 3), "the Scene locked badge shows")

        // Collections: no Edit, no swipe Delete, the note; New Collection stays (additive).
        app.tapFreshControl("presets")
        let node = app.buttons["node:collections"]
        XCTAssertTrue(node.appears(within: 10), "library home")
        if !node.isHittable { _ = app.reveal(node) }
        node.tap()
        let friday = app.buttons["collection:Friday set"]
        XCTAssertTrue(friday.appears(within: 5))
        XCTAssertTrue(app.descendants(matching: .any)["sceneLockNote"].firstMatch.exists, "the screen says it is locked")
        XCTAssertFalse(app.buttons["Edit"].exists, "no Edit button: no drag reorder while locked")
        XCTAssertTrue(app.buttons["newCollection"].isEnabled, "New Collection stays")
        friday.swipeLeft()
        XCTAssertTrue(app.buttons["Rename"].appears(within: 2), "the swipe opened (Rename stays)")
        XCTAssertFalse(app.buttons["Delete"].exists, "no Delete action while locked")
        friday.swipeRight()   // close the swipe
        XCTAssertTrue(friday.exists, "the collection stays")
        app.navigationBars.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(friday.disappears(within: 3), "the browser closed")   // a tap during the dismissal lands on the sheet

        // The emergency blackout still works while locked, and Restore returns.
        let emergency = app.buttons["emergencyBlackout"]
        XCTAssertTrue(emergency.appears(within: 5), "the emergency button is offered while locked")
        // The button sits above the controls and moves when they auto-hide (5 s after the last use), so a tap racing
        // that move can miss: hide the controls first and tap the settled button, as EmergencyBlackoutUITests does.
        let controls = app.otherElements["controls"]
        let area = app.otherElements["visualizerTapArea"].firstMatch
        // A tap that races the 5 s auto-hide shows them again, so retry (EmergencyBlackoutUITests.hideControls).
        var hidden = false
        for _ in 0..<4 where !hidden {
            if controls.exists { area.tap() }
            hidden = controls.disappears(within: 1.5) && !controls.appears(within: 0.5)
        }
        XCTAssertTrue(hidden, "the controls are hidden")
        XCTAssertTrue(poll(3) { emergency.isHittable }, "the emergency button can be tapped")
        emergency.tap()
        XCTAssertTrue(poll(2) { self.output == "black" }, "black at once while locked")
        app.buttons["blackoutRestore"].tap()
        XCTAssertTrue(poll(5) { self.output == "live" }, "restored while locked")
        XCTAssertTrue(badge.exists, "still locked")

        // Unlock asks first.
        app.tapFreshControl("lockScene")
        let confirm = app.buttons["sceneUnlockConfirm"].firstMatch
        XCTAssertTrue(confirm.appears(within: 3), "Unlock scene? asks first")
        confirm.tap()
        XCTAssertTrue(poll(3) { !self.badge.exists }, "unlocked")
    }
}
