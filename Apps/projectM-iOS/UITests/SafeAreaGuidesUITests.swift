// SafeAreaGuidesUITests.swift — OUT-005-T10 on the iOS Simulator (specs/258-out-005-safe-area-guides; S4, C2, C4).
// Off at launch (no guide probe); Settings → Performance → Show guides turns them on, and the DEBUG probe
// (`-uitestDiagnostics`) reads the default 93 % / 90 % guides over the whole visual. The guides themselves are
// hidden from accessibility (R7). Simulator results are never device evidence. Owner rule 7: < 30 s.
import XCTest

@MainActor
final class SafeAreaGuidesUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: XCUIElement { app.staticTexts["safeAreaGuidesProbe"] }

    func testSettingsSwitchShowsTheGuides() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestKeepControls", "-autostart", "inAppPlayback", "-uitestDiagnostics",
                               "-uitestSettingsSection", "safeAreaGuides"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertFalse(probe.exists, "off by default: no guides")

        let controls = app.otherElements["controls"]
        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 3))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let toggle = app.switches["safeAreaGuidesToggle"]
        XCTAssertTrue(toggle.appears(within: 3) || app.reveal(toggle), "Settings → Performance → Show guides")
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(2) { (toggle.value as? String) == "1" })
        let action: XCUIElement = app.slider("safeAreaActionPercent")   // ACC-005: an adjustable element, not a slider
        XCTAssertTrue(action.appears(within: 2) || app.reveal(action),
                      "the percentages show while on")
        app.navigationBars["Settings"].buttons["Done"].tap()

        XCTAssertTrue(probe.appears(within: 3), "on: the guides are drawn")
        let value: String = (probe.value as? String) ?? ""
        XCTAssertTrue(value.hasPrefix("action=93 title=90 cross=no frame="), value)
    }
}
