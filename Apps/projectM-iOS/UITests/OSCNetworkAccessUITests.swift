// OSC-007-T10: the OSC listener badge and its Stop on the iOS Simulator (OSC-007-R2, R4, R6, R7, S4).
// Enable OSC in Settings → after Done the visualizer shows "OSC listening on port 47124", with the
// controls shown and hidden → Stop → the badge is gone and Settings shows the toggle off and "Off".
// Launch state as in OSCReceiverUITests (`-settings.osc.enabled NO`, a fixed port away from 9000 and
// 47123). Simulator results are never device evidence; the Wi-Fi check is {device} OSC-007-T12.
// Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class OSCNetworkAccessUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private static let port = "47124"

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }
    private var tapArea: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    /// Shows the controls freshly (they hide on a timer), as OSCReceiverUITests does.
    private func showControls() {
        if controls.exists { tapArea.tap() }
        tapArea.tap()
        if !controls.appears(within: 2) { tapArea.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func openSettings() {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    /// Held drags, not swipes (see SettingsUITests.scrollTo).
    @discardableResult
    private func scrollTo(_ element: XCUIElement) -> Bool {
        let window = app.windows.firstMatch
        let top = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            bottom.press(forDuration: 0.05, thenDragTo: top, withVelocity: .default, thenHoldForDuration: 0.1)
        }
        return element.exists
    }

    private func status() -> String {
        let element = app.staticTexts["oscStatus"]
        return (element.value as? String) ?? element.label
    }

    private func tapSwitch(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    func testBadgeShowsTheListeningPortAndStopTurnsOSCOff() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.osc.enabled", "NO", "-settings.osc.port", Self.port] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let badge = app.descendants(matching: .any)["oscListenerBadge"]
        XCTAssertFalse(badge.exists, "no badge while OSC is off")

        // Enable in Settings.
        openSettings()
        let toggle = app.switches["oscReceiverToggle"]
        XCTAssertTrue(scrollTo(toggle), "the OSC section is in Settings")
        tapSwitch(toggle)
        XCTAssertTrue(poll(10) { self.status() == "Listening on port \(Self.port)" }, "status: \(status())")
        app.navigationBars["Settings"].buttons["Done"].tap()

        // The badge, with the controls shown (no overlap) and hidden.
        let text = app.staticTexts["oscListenerBadgeText"]
        let stop = app.buttons["oscStopButton"]
        XCTAssertTrue(text.appears(within: 5), "the badge is shown")
        XCTAssertEqual(text.label, "OSC listening")
        XCTAssertEqual(text.value as? String, "Port \(Self.port)")
        XCTAssertEqual(stop.label, "Stop OSC")
        showControls()
        XCTAssertTrue(stop.isHittable && app.buttons["settings"].isHittable, "badge and controls do not cover each other")
        tapArea.tap()
        XCTAssertTrue(controls.disappears(within: 5), "the controls hide")
        XCTAssertTrue(text.exists, "the badge stays when the controls hide")

        // Stop.
        stop.tap()
        XCTAssertTrue(badge.disappears(within: 5), "Stop removes the badge")

        // Settings shows the toggle off.
        openSettings()
        XCTAssertTrue(scrollTo(toggle))
        XCTAssertEqual(toggle.value as? String, "0", "the toggle is off after Stop")
        XCTAssertTrue(poll(5) { self.status() == "Off" }, "status: \(status())")
    }
}
