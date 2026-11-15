// OSC-012-T18: the Cue Sync screen on the iOS Simulator (OSC-012-R1, R14). No network is used: the receiver runs over
// the DEBUG stand-in transport (`-uitestFakeOSC`). The role starts Off; choosing Lead or Follow shows why it is not
// active yet (the allow list is off). The real two-device check is the {device} task OSC-012-T22.
// Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class OSCCueSyncUITests: XCTestCase {
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

    func testRoleIsOffByDefaultAndLeadAndFollowAreSelectable() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestFakeOSC",
                               "-settings.osc.enabled", "YES", "-uitestSettingsSection", "osc"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let link = app.buttons["oscCueSyncLink"]
        XCTAssertTrue(app.reveal(link, long: true), "Cue Sync is in the OSC section")
        link.tap()
        XCTAssertTrue(app.navigationBars["Cue Sync"].appears(within: 5))

        let status = app.staticTexts["oscCueSyncStatus"]
        XCTAssertTrue(status.appears(within: 5))
        XCTAssertTrue(app.buttons["Off"].isSelected, "R1: Off by default")
        XCTAssertEqual(status.value as? String, "Off")

        app.buttons["Lead"].tap()
        XCTAssertTrue(app.buttons["Lead"].isSelected)
        XCTAssertEqual(status.value as? String, "Turn on Only approved devices to sync cues.")

        app.buttons["Follow"].tap()
        XCTAssertTrue(app.buttons["Follow"].isSelected)
        XCTAssertEqual(status.value as? String, "Turn on Only approved devices to sync cues.")

        app.buttons["Off"].tap()
        XCTAssertEqual(status.value as? String, "Off")
    }
}
