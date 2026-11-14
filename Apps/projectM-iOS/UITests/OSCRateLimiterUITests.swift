// OSC-009-T12: the rate limiter's Settings row on the iOS Simulator (OSC-009-R12). OSC on via launch
// arguments (port 47125, so the host's 9000 is not needed); the row shows "0" with no traffic. The
// flood itself is proven by package and app unit tests; the LAN flood is the {device} task
// OSC-009-T15. Simulator results are never device evidence. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class OSCRateLimiterUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testSettingsShowsTheRateLimitedCount() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.osc.enabled", "YES", "-settings.osc.port", "47125",
                               "-uitestSettingsSection", "osc"] + Self.noStore   // Settings opens at OSC (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))

        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }                 // show them freshly (they hide on a timer)
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let row = app.descendants(matching: .any)["oscRateLimited"]
        app.reveal(row)
        XCTAssertTrue(row.exists, "the Rate-limited row is shown while OSC is on")
        // LabeledContent reads as one element, "Rate-limited, 0".
        XCTAssertEqual(row.label, "Rate-limited, 0", "no traffic: the row shows 0")
    }
}
