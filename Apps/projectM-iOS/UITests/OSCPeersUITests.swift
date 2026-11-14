// OSC-008-T12: Approved Devices in Settings on the iOS Simulator (OSC-008-R9). Settings opens at the OSC section
// (`-uitestSettingsSection osc`); the row reads "Off", the switch turns the allowlist on, the empty-list note appears
// and the row reads "0 approved". OSC stays off: no listener and no network. Simulator results are never device
// evidence. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class OSCPeersUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openSettings() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    func testApprovedDevicesTurnsOnAndExplainsAnEmptyList() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.osc.enabled", "NO", "-uitestSettingsSection", "osc"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let link = app.buttons["oscPeersLink"]
        XCTAssertTrue(app.reveal(link, long: true), "Approved Devices is in the OSC section")
        XCTAssertTrue(link.label.contains("Off"), "off by default: \(link.label)")
        link.tap()
        XCTAssertTrue(app.navigationBars["Approved Devices"].appears(within: 5))

        let toggle = app.switches["oscPeerAllowlistToggle"]
        XCTAssertTrue(toggle.appears(within: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.staticTexts["oscPeersEmptyNote"].exists)
        let control = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        control.tap()
        XCTAssertTrue(poll(5) { toggle.value as? String == "1" }, "turned on")
        XCTAssertTrue(app.staticTexts["oscPeersEmptyNote"].appears(within: 5), "every message is blocked with no device approved")
        XCTAssertTrue(app.staticTexts["oscBlockedCount"].exists || app.otherElements["oscBlockedCount"].exists, "the blocked count is shown")

        app.navigationBars["Approved Devices"].buttons.firstMatch.tap()
        XCTAssertTrue(poll(5) { app.buttons["oscPeersLink"].label.contains("0 approved") }, "the row shows the count")
    }
}
