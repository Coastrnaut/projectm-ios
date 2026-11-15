// CornerPinUITests.swift — OUT-007-T11 on the iOS Simulator: with the fake external display
// (`-uitestExternalDisplay`), Settings › External Display › Corner pin… shows the test card on the display, a
// nudge moves the selected corner (hidden `cornerPinProbe`: the stored pin and the display's summary), Reset
// restores the identity and Done hides the card (hidden `externalCornerPin` probe). Simulator results are never
// device evidence (OUT-007-T12 is). Owner rule 7: under 30 s.
import XCTest

@MainActor
final class CornerPinUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var editorProbe: String { (app.descendants(matching: .any)["cornerPinProbe"].firstMatch.value as? String) ?? "nil" }
    private var displayProbe: String { (app.descendants(matching: .any)["externalCornerPin"].firstMatch.value as? String) ?? "nil" }

    func testTheEditorShowsTheCardNudgesResetsAndCloses() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestExternalDisplay", "-uitestSettingsSection", "externalDisplay"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(poll(5) { self.displayProbe.hasPrefix("pin=identity card=hidden") }, "identity: \(displayProbe)")

        app.tapFreshControl("settings")   // retries when the controls auto-hide mid-tap
        let row = app.buttons["externalCornerPinButton"]
        XCTAssertTrue(app.reveal(row), "Corner pin… is reachable")
        row.tap()
        XCTAssertTrue(poll(5) { self.editorProbe.contains("card=shown") }, "the display shows the test card: \(editorProbe)")

        app.buttons["cornerPinNudge.right"].tap()
        app.buttons["cornerPinNudge.down"].tap()
        XCTAssertTrue(poll(3) { self.editorProbe.hasPrefix("0.005,0.005;1,0;1,1;0,1|pin=custom card=shown") },
                      "top left moved one step right and down, on the display too: \(editorProbe)")

        app.buttons["cornerPinReset"].tap()
        XCTAssertTrue(poll(3) { self.editorProbe.hasPrefix("0,0;1,0;1,1;0,1|pin=identity card=shown") }, "reset: \(editorProbe)")
        app.buttons["cornerPinNudge.right"].tap()
        app.buttons["cornerPinDone"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(poll(5) { self.displayProbe == "pin=custom card=hidden corners=0.005,0;1,0;1,1;0,1" },
                      "Done hides the card and keeps the pin: \(displayProbe)")
    }
}
