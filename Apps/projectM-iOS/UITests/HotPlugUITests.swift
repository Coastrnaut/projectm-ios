// HotPlugUITests.swift — OUT-002-T10 on the iOS Simulator, with the DEBUG fake external display
// (`-uitestExternalDisplay`, driven through ExternalDisplayEventSink like a real scene): a connection
// that drops inside the settle time moves nothing and leaves nothing held; a display connecting while
// the output is blacked out is black; plug and unplug never restart the source and release the
// display's slot. Simulator results are never device evidence (OUT-002-T12 is). Owner rule 7: < 30 s.
import XCTest

@MainActor
final class HotPlugUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }
    private var output: String? { app.staticTexts["outputBlackout"].value as? String }
    private var resources: String? { app.descendants(matching: .any)["externalResources"].firstMatch.value as? String }
    private var note: XCUIElement { app.descendants(matching: .any)["externalDisplayNote"].firstMatch }

    private func waitFor(_ value: String, _ read: () -> String?, within seconds: TimeInterval) -> Bool {
        poll(seconds) { read() == value }
    }

    func testABounceMovesNothingAndABlackedOutConnectIsBlack() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestExternalDisplay", "-uitestStartBlackedOut"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(waitFor("black", { output }, within: 5), "blacked out from launch")

        // A connection that drops at once (inside the 0.3 s settle): nothing moves, nothing stays.
        app.buttons["uitestBounceExternal"].tap()
        XCTAssertTrue(waitFor("slots=0 pending=0 holding=0 cancelled=1", { resources }, within: 3), "probe: \(resources ?? "nil")")
        XCTAssertFalse(note.exists, "the visualization never left the device")

        // A real connect while blacked out: the visualization moves after the settle, and its slot is black.
        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(note.appears(within: 5), "moved to the (fake) external display")
        XCTAssertEqual(note.label, "The external display is blacked out")
        XCTAssertTrue(waitFor("black", { output }, within: 2), "the new display is black")
        XCTAssertTrue(waitFor("slots=1 pending=0 holding=1 cancelled=1", { resources }, within: 3), "probe: \(resources ?? "nil")")

        app.buttons["uitestDisconnectExternal"].tap()
        XCTAssertTrue(note.disappears(within: 5), "back on the device")
        XCTAssertTrue(waitFor("slots=0 pending=0 holding=0 cancelled=1", { resources }, within: 3), "the slot is released")
        XCTAssertEqual(output, "black", "the blackout is unchanged")
        XCTAssertEqual(starts, "1", "hot-plug never restarts the source")
    }
}
