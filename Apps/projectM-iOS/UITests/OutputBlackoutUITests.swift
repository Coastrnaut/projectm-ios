// OutputBlackoutUITests.swift — OUT-010-T08 on the iOS Simulator, with the DEBUG fake external
// display (`-uitestExternalDisplay`, OUT-001-T06): Black out makes the slot holding the visual black,
// the device's controls keep working (Settings opens and closes; pause while external is ExternalDisplayUITests'), Restore brings the picture back
// while the visual kept drawing, and the audio source is started once throughout (OUT-010-S2).
// Simulator results are never device evidence (OUT-010-T15 is). Owner rule 7: under 30 s.
import XCTest

@MainActor
final class OutputBlackoutUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }
    private var output: String? { app.staticTexts["outputBlackout"].value as? String }
    private var running: String? { app.staticTexts["visualRunning"].value as? String }
    private var note: XCUIElement { app.descendants(matching: .any)["externalDisplayNote"].firstMatch }

    /// Shows the controls with a fresh 5 s auto-hide (as ExternalDisplayUITests.showControls).
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    /// UITestWaits' 0.1 s polling until `read()` gives `value`.
    private func waitFor(_ value: String, _ read: () -> String?, within seconds: TimeInterval) -> Bool {
        poll(seconds) { read() == value }
    }

    func testBlackOutTheExternalOutputKeepsControlsAndRestoresWithoutRestartingTheSource() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestExternalDisplay"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(waitFor("live", { output }, within: 5), "live before the tap")

        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(note.appears(within: 5), "the visualization is on the (fake) external display")

        showControls()
        let blackout = app.buttons["blackout"]
        XCTAssertEqual(blackout.label, "Black out output")
        XCTAssertEqual(blackout.value as? String, "Live")
        blackout.tap()
        XCTAssertTrue(waitFor("black", { output }, within: 2), "the external slot is black")
        XCTAssertTrue(app.descendants(matching: .any)["blackoutBadge"].firstMatch.appears(within: 2), "persistent badge")
        XCTAssertEqual(note.label, "The external display is blacked out")

        // The controls still respond while blacked out (OUT-010-R5).
        showControls()
        XCTAssertEqual(app.buttons["blackout"].label, "Restore output")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5), "Settings opens while blacked out")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5), "and closes")
        XCTAssertEqual(output, "black", "still black after using the controls")

        // Restore from the badge: a 1 s fade, then live; the visual kept drawing.
        app.buttons["blackoutRestore"].tap()
        XCTAssertTrue(waitFor("live", { output }, within: 5), "restored")
        XCTAssertTrue(waitFor("yes", { running }, within: 5), "frames continue")
        XCTAssertEqual(note.label, "The visualization is showing on the external display")
        XCTAssertEqual(starts, "1", "blackout and restore never restart the source")

        // Unplug while blacked out keeps the device black.
        showControls()
        app.buttons["blackout"].tap()
        XCTAssertTrue(waitFor("black", { output }, within: 2))
        app.buttons["uitestDisconnectExternal"].tap()
        XCTAssertTrue(note.disappears(within: 5))
        XCTAssertEqual(output, "black", "the device is black after the unplug")
        XCTAssertEqual(starts, "1")
    }
}
