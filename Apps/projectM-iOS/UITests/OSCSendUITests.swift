// OSC-005-T12: the Send OSC screen on the iOS Simulator (OSC-005-R1, R2, R3, R10; S5). No network is used: the
// receiver switch runs over the DEBUG stand-in transport (`-uitestFakeOSC`) and Send OSC stays off, so no flow is
// opened. A public address is refused with its message; a LAN address is accepted and stored. The real LAN check
// is the {device} task OSC-005-T16. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class OSCSendUITests: XCTestCase {
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

    private func enter(_ text: String, into field: XCUIElement) {
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    func testPublicAddressRefusedLocalAccepted() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestFakeOSC",
                               "-settings.osc.enabled", "YES", "-uitestSettingsSection", "osc"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let link = app.buttons["oscSendLink"]
        XCTAssertTrue(app.reveal(link, long: true), "Send OSC is in the OSC section")
        link.tap()
        XCTAssertTrue(app.navigationBars["Send OSC"].appears(within: 5))

        let toggle = app.switches["oscSendToggle"]
        XCTAssertTrue(toggle.appears(within: 5))
        XCTAssertEqual(toggle.value as? String, "0", "R2: off by default")
        XCTAssertEqual(app.staticTexts["oscSendStatus"].value as? String, "Off")

        let host = app.textFields["oscSendHost"]
        enter("8.8.8.8", into: host)
        app.buttons["oscSendApply"].tap()
        let error = app.staticTexts["oscSendHostError"]
        XCTAssertTrue(error.appears(within: 5), "a public address is refused")
        XCTAssertTrue(error.label.hasPrefix("Use an address on your local network"), error.label)

        enter("192.168.1.40", into: host)
        app.buttons["oscSendApply"].tap()
        XCTAssertTrue(poll(5) { !error.exists }, "a LAN address is accepted")
        XCTAssertEqual(host.value as? String, "192.168.1.40")

        XCTAssertEqual(app.switches["oscSendKind.scene"].value as? String, "1")
        XCTAssertEqual(app.switches["oscSendKind.beat"].value as? String, "0")
        // The address field keeps the keyboard up, and reveal's drags land on the keyboard instead of the list.
        if app.keyboards.firstMatch.exists { host.typeText("\n") }
        XCTAssertTrue(poll(3) { !self.app.keyboards.firstMatch.exists }, "the keyboard is closed")
        XCTAssertTrue(app.reveal(app.switches["oscSendSceneNames"]), "Include scene names is offered")
        XCTAssertEqual(app.switches["oscSendSceneNames"].value as? String, "0")
    }
}
