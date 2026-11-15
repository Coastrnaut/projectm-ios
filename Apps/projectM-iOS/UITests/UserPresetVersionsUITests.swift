// UserPresetVersionsUITests.swift — PRE-017-T09 (specs/250-pre-017-preset-restore-points; S5): reverting an edited
// user preset on the iOS Simulator with the real off-screen engine check. `-uitestPresetVersions` (DEBUG, with
// `-uitestResetNotice`) seeds "Versioned" with one earlier version. My Presets › touch and hold › Versions… ›
// Revert › Revert; the sheet closes after the check, and Versions… then lists two versions (the reverted-from
// text is kept, so the revert can be undone). Launched with the fixed fake entitlement (`-uitestUnlocked NO`).
// Simulator only; never device evidence. Budget: under 30 s.
import XCTest

@MainActor
final class UserPresetVersionsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openVersions(of row: XCUIElement) {
        row.press(forDuration: 1.2)
        let item = app.buttons["userPresetVersions"]
        XCTAssertTrue(item.appears(within: 3), "Versions… is in the row menu")
        item.tap()
        XCTAssertTrue(app.descendants(matching: .any)["presetVersions"].appears(within: 5))
    }

    func testRevertingAnEditedPresetFromTheVersionsSheet() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("simulator only")
        #else
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-uitestPresetVersions",
                               "-autostart", "inAppPlayback"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))   // a ceiling for a loaded Mac

        app.tapFreshControl("presets")
        let node = app.buttons["node:myPresets"]
        _ = app.reveal(node)
        // As LibraryCheckUITests: lift the row clear of the bottom search field once facet chips exist.
        let window = app.windows.firstMatch
        if node.frame.maxY > window.frame.maxY * 0.75 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.35)))
        }
        node.tap()
        let row = app.buttons["preset:Versioned"]
        XCTAssertTrue(row.appears(within: 5) || app.reveal(row), "the seeded preset is listed")

        openVersions(of: row)
        let revert = app.buttons["revertVersion"]
        XCTAssertTrue(revert.appears(within: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "revertVersion").count, 1, "one earlier version")
        revert.tap()
        let confirm = app.alerts.firstMatch.buttons["Revert"].firstMatch
        XCTAssertTrue(confirm.appears(within: 3))
        confirm.tap()
        // The engine check runs, then the sheet closes on success.
        XCTAssertTrue(app.descendants(matching: .any)["presetVersions"].disappears(within: 20),
                      app.descendants(matching: .any)["presetVersionsError"].label)

        openVersions(of: row)
        XCTAssertTrue(app.buttons["revertVersion"].appears(within: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "revertVersion").count, 2, "the reverted-from text is a version now")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "versions after revert"
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }
}
