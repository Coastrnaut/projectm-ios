// GridWarpUITests.swift — OUT-008-T13 on the iOS Simulator: with the fake external display (`-uitestExternalDisplay`),
// Settings › External Display › Grid warp… is reached, the display draws the guides while the editor is open, a nudge
// moves the selected point (hidden `gridWarpProbe`: the stored mesh and the display's summary), Reset restores the
// identity and Done hides the guides and keeps the mesh (hidden `externalGridWarp` probe). Simulator results are never
// device evidence (OUT-008-T15 is). Owner rule 7: under 30 s.
import XCTest

@MainActor
final class GridWarpUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var editorProbe: String { (app.descendants(matching: .any)["gridWarpProbe"].firstMatch.value as? String) ?? "nil" }
    private var displayProbe: String { (app.descendants(matching: .any)["externalGridWarp"].firstMatch.value as? String) ?? "nil" }

    func testTheEditorShowsGuidesNudgesResetsAndCloses() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestExternalDisplay", "-uitestSettingsSection", "externalDisplay"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(poll(5) { self.displayProbe.hasPrefix("warp=identity grid=3x3 guides=off") }, "identity: \(displayProbe)")

        app.tapFreshControl("settings")
        let row = app.buttons["externalGridWarpButton"]
        XCTAssertTrue(app.reveal(row), "Grid warp… is reachable")
        row.tap()
        XCTAssertTrue(poll(5) { self.editorProbe.contains("guides=on applied=yes") }, "the display draws the guides: \(editorProbe)")

        app.buttons["gridWarpNudge.right"].tap()
        app.buttons["gridWarpNudge.down"].tap()
        XCTAssertTrue(poll(3) { self.editorProbe.hasPrefix("3x3:0.005,0.005;0.5,0;1,0;0,0.5;0.5,0.5;1,0.5;0,1;0.5,1;1,1|warp=custom") },
                      "the top-left point moved one step right and down, on the display too: \(editorProbe)")

        app.buttons["gridWarpReset"].tap()
        XCTAssertTrue(poll(3) { self.editorProbe.hasPrefix("3x3:0,0;0.5,0;1,0;0,0.5;0.5,0.5;1,0.5;0,1;0.5,1;1,1|warp=identity") },
                      "reset: \(editorProbe)")
        app.buttons["gridWarpNudge.right"].tap()
        app.buttons["gridWarpDone"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(poll(5) { self.displayProbe == "warp=custom grid=3x3 guides=off applied=yes" },
                      "Done hides the guides and keeps the mesh: \(displayProbe)")
    }
}
