// OSC-011-T13: the Nearby Devices screen on the iOS Simulator (OSC-011-R3, R4, R8, R9). No network is used: the
// receiver runs over the DEBUG stand-in transport (`-uitestFakeOSC`) and the browser is the DEBUG fake
// (`-uitestFakeDiscovery`, two fixed local devices). Both switches start off and no list is shown; turning Find on
// shows the devices, and Allow is an explicit tap. The real LAN check is the {device} task OSC-011-T19.
// Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class OSCDiscoveryUITests: XCTestCase {
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

    func testSwitchesDefaultOffAndFindShowsTheList() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestFakeOSC",
                               "-uitestFakeDiscovery", "-settings.osc.enabled", "YES", "-uitestSettingsSection", "osc"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let link = app.buttons["oscDiscoveryLink"]
        XCTAssertTrue(app.reveal(link, long: true), "Nearby Devices is in the OSC section")
        link.tap()
        XCTAssertTrue(app.navigationBars["Nearby Devices"].appears(within: 5))

        let find = app.switches["oscDiscoveryBrowseToggle"]
        XCTAssertTrue(find.appears(within: 5))
        XCTAssertEqual(find.value as? String, "0", "R4: Find nearby devices is off by default")
        XCTAssertEqual(app.switches["oscDiscoveryAdvertiseToggle"].value as? String, "0", "R4: announcing is off by default")
        XCTAssertEqual(app.staticTexts["oscDiscoveryStatus"].value as? String, "Off")
        XCTAssertFalse(app.descendants(matching: .any)["oscDiscoveredPeer_0"].exists, "no list while off")

        find.switches.firstMatch.exists ? find.switches.firstMatch.tap() : find.tap()
        let first = app.descendants(matching: .any)["oscDiscoveredPeer_0"]
        XCTAssertTrue(first.appears(within: 5), "turning it on shows the devices found")
        XCTAssertTrue(app.staticTexts["Lighting Desk"].exists)
        XCTAssertTrue(app.staticTexts["192.168.1.40:9001"].exists)
        XCTAssertEqual(app.staticTexts["oscDiscoveryStatus"].value as? String, "2 devices found")

        app.buttons["oscDiscoveryAllow_0"].tap()   // R9: an explicit tap
        XCTAssertTrue(app.staticTexts["oscDiscoveryActionNote"].appears(within: 5))
        XCTAssertEqual(app.buttons["oscDiscoveryAllow_0"].label, "Allow Lighting Desk")
        XCTAssertFalse(app.buttons["oscDiscoveryAllow_0"].isEnabled, "already approved")
    }
}
