// OSC-001-T21: the OSC receiver in Settings on the iOS Simulator (OSC-001-R2, R3, R16). Off at
// start, on → listening on the chosen port, a port outside 1024-65535 refused, off → "Off". The
// launch arguments fix the start state (`-settings.osc.enabled NO`, port 47123 so the host's port 9000
// is not needed); the fresh-install default is proved by SettingsTests (OSC-001-S4). Simulator
// results are never device evidence; the Wi-Fi test is the {device} task OSC-001-T26.
// Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class OSCReceiverUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private static let port = "47123"

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

    private func status() -> String {
        let element = app.staticTexts["oscStatus"]
        app.reveal(element)   // below the fold as Settings grows (PERF-010 added a DEBUG section)
        return (element.value as? String) ?? element.label
    }

    func testToggleListensOnTheChosenPortRefusesABadPortAndTurnsOff() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.osc.enabled", "NO", "-settings.osc.port", Self.port] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let toggle = app.switches["oscReceiverToggle"]
        XCTAssertTrue(app.reveal(toggle, long: true), "the OSC section is in Settings")
        XCTAssertEqual(toggle.value as? String, "0", "off at start")
        XCTAssertEqual(status(), "Off")

        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(10) { self.status() == "Listening on port \(Self.port)" }, "status: \(status())")
        XCTAssertTrue(app.descendants(matching: .any)["oscTestValue"].exists)

        let field = app.textFields["oscPortField"]
        app.reveal(field, long: true)
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: Self.port.count) + "80")
        app.buttons["oscPortDone"].tap()
        XCTAssertTrue(app.staticTexts["oscPortError"].appears(within: 5), "port 80 is refused")
        XCTAssertEqual(field.value as? String, Self.port, "the stored port stays")
        XCTAssertEqual(status(), "Listening on port \(Self.port)")

        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(10) { self.status() == "Off" }, "status: \(status())")
    }
}
