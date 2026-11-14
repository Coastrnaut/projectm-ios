// PermissionAuditUITests.swift — FILE-013-T07 (specs/078-file-013-privacy-permission-audit): denied and
// restricted behaviour for every permission the app can trigger, on the iOS Simulator.
// * Microphone denied for real: the runner revokes the permission with
//   `xcrun simctl privacy <udid> revoke microphone org.projectmios.ProjectMiOS` and passes
//   `TEST_RUNNER_FILE013_MIC_REVOKED=1`; without it the test skips (never passes). iOS has no
//   restricted record permission (the catalog's unit tests cover the mapping).
// * Camera restricted (the stand-in `-uitestCamera restricted`; the simulator has no rear camera and
//   cannot set restricted): the catalog's notice, and Open Settings brings iOS Settings forward.
//   Camera denied is CameraUITests.testDeniedCameraShowsNoticeAndAppStaysUsable.
// * Local Network denied (`-uitestOSCFailure localNetworkDenied`: not scriptable on the simulator).
// * Screen capture restricted (`-uitestFakeAvailability`) and denied (`-uitestFakeStartError`).
// Simulator results are never device evidence; D1 is FILE-013-T11. Each test < 30 s (owner rule 7).
import XCTest

@MainActor
final class PermissionAuditUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private let settingsApp = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    /// Launches at the notice, acknowledges it and waits for the source chooser.
    private func launchToChooser(_ extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice"] + extra + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.appears(within: 15))
        acknowledge.tap()
    }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func openSettings() {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private func message(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    /// Taps Open Settings and checks that iOS Settings comes to the foreground; then returns.
    private func expectOpenSettingsOpensSettings(_ button: XCUIElement) {
        XCTAssertTrue(button.exists, "Open Settings is offered")
        button.tap()
        XCTAssertTrue(settingsApp.wait(for: .runningForeground, timeout: 10), "iOS Settings is in front")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    // MARK: Microphone (real denial)

    func testMicrophoneDeniedForRealShowsBannerAndOpensSettings() throws {
        guard ProcessInfo.processInfo.environment["FILE013_MIC_REVOKED"] == "1" else {
            throw XCTSkip("Run with the microphone revoked (simctl privacy revoke) and TEST_RUNNER_FILE013_MIC_REVOKED=1")
        }
        launchToChooser([])
        let row = app.buttons["Microphone"]
        XCTAssertTrue(row.appears(within: 10))
        row.tap()
        XCTAssertFalse(app.buttons["Continue"].appears(within: 1), "no explainer: the permission is already denied")
        let text = message("Microphone permission denied. Enable it in Settings › Privacy › Microphone.")
        XCTAssertTrue(text.appears(within: 10), "the catalog's denied text")
        XCTAssertTrue(app.buttons["Choose source"].exists)
        expectOpenSettingsOpensSettings(app.buttons["Open Settings"])
    }

    // MARK: Camera (restricted, stand-in)

    func testCameraRestrictedShowsNoticeAndOpensSettings() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestCamera", "restricted"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()
        let row = app.visualRow("Camera")
        app.reveal(row)
        row.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.otherElements["cameraNotice"].appears(within: 10), "the non-blocking notice")
        XCTAssertEqual(app.staticTexts["cameraNoticeText"].label,
                       "Camera access is restricted on this device. It can be allowed in Settings if your restrictions permit.")
        let visual = app.descendants(matching: .any)["cameraVisual"].firstMatch
        XCTAssertEqual(visual.value as? String, "Camera restricted", "the visual keeps running without the camera")
        expectOpenSettingsOpensSettings(app.buttons["cameraOpenSettings"])
        XCTAssertTrue(app.otherElements["cameraNotice"].appears(within: 5), "the notice stays after returning")
    }

    // MARK: Local Network (denied, stand-in)

    func testLocalNetworkDeniedShowsNoticeWithOpenSettings() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-settings.osc.enabled", "NO",
                               "-settings.osc.port", "47127", "-uitestOSCFailure", "localNetworkDenied",
                               "-uitestSettingsSection", "osc"] + Self.noStore   // Settings opens at OSC (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()
        let toggle = app.switches["oscReceiverToggle"]
        XCTAssertTrue(app.reveal(toggle), "the OSC section is in Settings")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        let text = app.staticTexts["localNetworkNoticeText"]
        XCTAssertTrue(text.appears(within: 10), "the Local Network notice replaces the status")
        app.reveal(text)
        XCTAssertEqual(text.label, "Local network access is off for projectM in Settings › Privacy & Security › Local Network.")
        XCTAssertTrue(app.buttons["localNetworkOpenSettings"].exists, "Open Settings is offered")
        XCTAssertFalse(app.staticTexts["oscStatus"].exists)

        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(text.disappears(within: 10), "off clears the notice")
        XCTAssertTrue(app.staticTexts["oscStatus"].appears(within: 5))
    }

    // MARK: Screen capture (restricted and denied, fake source)

    func testScreenCaptureRestrictedDisablesTheRow() {
        launchToChooser(["-uitestFake", "systemAppCapture", "-uitestFakeAvailability", "screenRecordingNotAllowed"])
        let row = app.buttons["System/App Capture"]
        XCTAssertTrue(row.appears(within: 10))
        XCTAssertFalse(row.isEnabled, "not allowed on this device: the row is disabled")
        XCTAssertTrue(app.buttons["Microphone"].isEnabled, "the other sources stay available")
        XCTAssertTrue(app.buttons["In-App Playback"].isEnabled)
    }

    func testScreenCaptureDeniedOffersRestartNotSettings() {
        launchToChooser(["-uitestFake", "systemAppCapture", "-uitestFakeStartError", "screenRecordingNotAllowed"])
        let row = app.buttons["System/App Capture"]
        XCTAssertTrue(row.appears(within: 10))
        row.tap()
        XCTAssertTrue(message("Screen recording not allowed").appears(within: 10))
        XCTAssertTrue(app.buttons["Restart"].exists)
        XCTAssertTrue(app.buttons["Choose source"].exists)
        XCTAssertFalse(app.buttons["Open Settings"].exists, "iOS Settings has no screen-recording switch")
    }
}
