// EmergencyBlackoutUITests.swift — SHOW-014-T06, T08, T10 on the iOS Simulator: with the controls
// hidden, one tap on the persistent emergency button blacks out the output (the device's
// visualization, or the DEBUG fake external display's slot); the controls stay hidden, the visual
// keeps drawing, and restore resumes the same preset with the audio source started once. The B key
// (hardware keyboard event) blacks out and restores. Simulator results are never device evidence
// (SHOW-014-T12 is). Owner rule 7: under 30 s each; UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class EmergencyBlackoutUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }
    private var output: String? { app.staticTexts["outputBlackout"].value as? String }
    private var running: String? { app.staticTexts["visualRunning"].value as? String }
    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }
    private var emergency: XCUIElement { app.buttons["emergencyBlackout"] }

    private func waitFor(_ value: String, _ read: () -> String?, within seconds: TimeInterval) -> Bool {
        poll(seconds) { read() == value }
    }

    private func launch(external: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"]
            + (external ? ["-uitestExternalDisplay"] : []) + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(waitFor("live", { output }, within: 5), "live at launch")
        XCTAssertTrue(waitFor("yes", { running }, within: 10), "the visual draws")
    }

    /// The shown preset's name, read from the controls; leaves the controls hidden.
    private func presetNameThenHideControls() -> String {
        showControls()
        let preset = app.staticTexts["currentPreset"]
        XCTAssertTrue(preset.appears(within: 5))
        XCTAssertTrue(poll(10) { preset.label != "No preset" }, "a preset is loaded")
        let name = preset.label
        hideControls()
        return name
    }

    /// Shows the controls with a fresh 5 s auto-hide (as OutputBlackoutUITests.showControls).
    private func showControls() {
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    /// Hides the controls; a tap that races the 5 s auto-hide (and shows them again) is retried.
    private func hideControls() {
        for _ in 0..<4 {
            if controls.exists { area.tap() }
            if controls.disappears(within: 1.5), !controls.appears(within: 0.5) { return }
        }
        XCTFail("the controls stay shown")
    }

    /// The emergency path with the controls hidden, then restore from the badge.
    private func blackOutAndRestore(external: Bool) {
        let before = presetNameThenHideControls()
        XCTAssertTrue(emergency.exists, "the emergency button stays with the controls hidden")
        XCTAssertEqual(emergency.label, "Emergency black out")

        emergency.tap()   // one tap
        XCTAssertTrue(waitFor("black", { output }, within: 2), "black at once")
        XCTAssertFalse(controls.exists, "the tap did not show the controls")
        XCTAssertTrue(emergency.disappears(within: 2), "only blacks out: hidden while blacked out")
        XCTAssertTrue(app.descendants(matching: .any)["blackoutBadge"].firstMatch.appears(within: 2), "persistent badge")
        XCTAssertEqual(running, "yes", "the visual keeps drawing under the blackout")
        if external {
            XCTAssertEqual(app.descendants(matching: .any)["externalDisplayNote"].firstMatch.label,
                           "The external display is blacked out")
        }

        app.buttons["blackoutRestore"].tap()
        XCTAssertTrue(waitFor("live", { output }, within: 5), "restored")
        XCTAssertTrue(emergency.appears(within: 2), "offered again")
        XCTAssertEqual(running, "yes")
        XCTAssertEqual(presetNameThenHideControls(), before, "restore resumes the previous preset")
        XCTAssertEqual(starts, "1", "the session never restarted")
    }

    func testOneTapBlacksOutTheDeviceWithControlsHiddenAndRestoreResumesThePreset() {
        launch(external: false)
        blackOutAndRestore(external: false)

        // SHOW-014-T10: B blacks out, B again restores (hardware keyboard event).
        app.typeKey("b", modifierFlags: [])
        XCTAssertTrue(waitFor("black", { output }, within: 2), "B blacks out")
        XCTAssertTrue(app.buttons["blackoutRestore"].appears(within: 2))
        app.typeKey("b", modifierFlags: [])
        XCTAssertTrue(waitFor("live", { output }, within: 5), "B restores")
        XCTAssertEqual(starts, "1")
    }

    func testOneTapBlacksOutTheExternalDisplayWithControlsHidden() {
        launch(external: true)
        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["externalDisplayNote"].firstMatch.appears(within: 5),
                      "the visualization is on the (fake) external display")
        blackOutAndRestore(external: true)
    }
}
