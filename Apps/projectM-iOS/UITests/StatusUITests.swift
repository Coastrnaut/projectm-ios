// Task T093: every FR-010 audio-state string and every FR-015 message with its actions
// (contracts/ui-states.md), driven by UITestFakeSource on the iOS Simulator. Also: pausing the
// visualization does not change the audio state (FR-046), the paused frame is dimmed with "Paused"
// (FR-085), and Restart after Ended by system starts the System/App Capture source again, which
// re-presents the picker (FR-055). Simulator results are never device evidence.
import XCTest

@MainActor
final class StatusUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static let labels = ["systemAppCapture": "System/App Capture", "microphone": "Microphone",
                                 "inAppPlayback": "In-App Playback"]

    /// Launches with the fake replacing `mode`, acknowledges the notice and picks that mode.
    private func start(_ mode: String = "inAppPlayback", startError: String? = nil) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestFake", mode] + Self.noStore
        if let startError { app.launchArguments += ["-uitestFakeStartError", startError] }
        app.launch()
        app.buttons["acknowledgeNotice"].tap()
        let row = app.buttons[Self.labels[mode]!]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 10))
    }

    private var indicator: XCUIElement { app.staticTexts["sourceIndicator"] }

    /// Waits until the indicator ends with "· <state>".
    private func expectState(_ state: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label ENDSWITH %@", "· \(state)")
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: indicator)], timeout: timeout)
        XCTAssertEqual(result, .completed, "state \"\(state)\"; indicator shows \"\(indicator.label)\"", file: file, line: line)
    }

    private func expectMessage(_ message: String, actions: [String], file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts.matching(NSPredicate(format: "label == %@", message)).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), "message \"\(message)\"", file: file, line: line)
        for action in actions {
            XCTAssertTrue(app.buttons[action].exists, "action \"\(action)\" for \"\(message)\"", file: file, line: line)
        }
    }

    private func tapFake(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
        button.tap()
    }

    // MARK: - Audio states (FR-010)

    func testWaitingActiveSilentAndNoAudio() {
        start()
        expectState("Waiting")
        tapFake("fake:loud")
        expectState("Active audio")
        tapFake("fake:silent")
        expectState("Audio received — silent")
        tapFake("fake:none")
        expectState("No audio received", timeout: 15)
        XCTAssertTrue(app.staticTexts["No audio received. Try another source or use Microphone."].waitForExistence(timeout: 5))
    }

    func testInterruptedWithRestart() {
        start()
        tapFake("fake:loud")
        expectState("Active audio")
        tapFake("fake:interrupt")
        expectState("Interrupted")
        expectMessage("Interrupted", actions: ["Restart", "Choose source"])
        tapFake("fake:none")   // so the restarted source shows Waiting before any audio
        app.buttons["Restart"].tap()
        expectState("Waiting")
    }

    func testPausedByRouteChangeWithResume() {
        start()
        tapFake("fake:loud")
        expectState("Active audio")
        tapFake("fake:routeLost")
        expectState("Paused")
        expectMessage("Paused — audio route changed", actions: ["Resume", "Choose source"])
        app.buttons["Resume"].tap()
        expectState("Active audio")
    }

    func testStoppedWithFailureMessages() {
        for (event, message) in [("fake:fail:microphoneUnavailable", "Microphone unavailable"),
                                 ("fake:fail:inAppPlaybackFailed", "In-App Playback failed")] {
            start()
            tapFake("fake:loud")
            expectState("Active audio")
            tapFake(event)
            expectState("Stopped")
            expectMessage(message, actions: ["Choose source"])
            app.terminate()
        }
    }

    // MARK: - Ended by system and restart (FR-055)

    func testEndedBySystemRestartRepresentsThePicker() {
        start("systemAppCapture")
        let starts = app.staticTexts["fake:starts"]
        XCTAssertTrue(starts.waitForExistence(timeout: 5))
        XCTAssertEqual(starts.value as? String, "1")
        tapFake("fake:ended")
        expectState("Ended by system")
        expectMessage("Ended by system", actions: ["Restart", "Choose source"])
        app.buttons["Restart"].tap()
        let restarted = NSPredicate(format: "value == '2'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: restarted, object: starts)], timeout: 5),
                       .completed, "Restart starts the source again, which presents the system picker")
        expectState("Waiting")
    }

    // MARK: - Start failures (FR-015)

    func testStartFailureMessagesAndActions() {
        let cases: [(String, String, String, [String])] = [
            ("inAppPlayback", "cancelled", "Not started — cancelled", ["Choose source"]),
            ("inAppPlayback", "permissionDenied", "Microphone permission denied. Enable it in Settings › Privacy › Microphone.",
             ["Open Settings", "Choose source"]),
            ("inAppPlayback", "unsupportedOS", "Requires a newer iOS version", ["Choose source"]),
            ("systemAppCapture", "screenRecordingNotAllowed", "Screen recording not allowed", ["Restart", "Choose source"]),
            ("inAppPlayback", "error", "Something went wrong: fake failure", ["Restart", "Choose source"]),
        ]
        for (mode, error, message, actions) in cases {
            start(mode, startError: error)
            expectState("Not started")
            expectMessage(message, actions: actions)
            app.terminate()
        }
    }

    // MARK: - Visualization pause (FR-046, FR-085)

    func testPausingTheVisualizationKeepsTheAudioState() {
        start()
        tapFake("fake:loud")
        expectState("Active audio")
        app.buttons["pauseResume"].tap()
        XCTAssertTrue(app.staticTexts["pausedLabel"].waitForExistence(timeout: 3), "dimmed frame with \"Paused\" (FR-085)")
        expectState("Active audio", timeout: 2)   // FR-046: the audio state is unchanged
        XCTAssertTrue(indicator.label.hasPrefix("In-App Playback · "))
    }
}
