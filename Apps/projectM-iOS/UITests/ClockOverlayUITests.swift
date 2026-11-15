// ClockOverlayUITests.swift — MED-011-T11 on the iOS Simulator (MED-011-S5, R1, R6, R7): with a fixed injected clock
// (`-uitestClockFixed`: 2026-03-04 14:05:09 UTC, en_US_POSIX), the clock is off at launch; Settings › Clock › Show
// Clock turns it on and the Text visual's clock layer draws "14:05" (DEBUG probe `clockProbe`: "<text> drawn=<frames>").
// Settings opens at the Clock section (`-uitestSettingsSection clock`; owner rule 7). Simulator results are never
// device evidence (Constitution X). Waits are ceilings for a slow shared Mac, never frame budgets.
import XCTest

@MainActor
final class ClockOverlayUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: String { app.staticTexts["clockProbe"].value as? String ?? "" }

    /// See CameraUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testShowClockDrawsTheFixedTimeOverTheTextVisual() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "text", "-uitestClockFixed", "1772633109",
                               "-uitestSettingsSection", "clock"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.staticTexts["clockProbe"].appears(within: 5))
        XCTAssertTrue(probe.hasPrefix("none drawn=0"), "off by default: \(probe)")

        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let toggle = app.switches["showClockToggle"]
        XCTAssertTrue(app.reveal(toggle), "the Clock section")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(app.buttons["clockFormatPicker"].exists || app.otherElements["clockFormatPicker"].exists
                      || app.staticTexts["Format"].exists, "the format row appears")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))

        let drawn: Bool = poll(15) { () -> Bool in Self.frames(self.probe) > 0 }
        XCTAssertTrue(drawn, "the Text visual's clock layer showed the clock: \(probe)")
        XCTAssertTrue(probe.hasPrefix("14:05 "), "the fixed clock's string: \(probe)")
    }

    /// The `n` of "<text> drawn=<n>" (-1 when unreadable).
    nonisolated static func frames(_ probe: String) -> Int {
        guard let start = probe.range(of: "drawn=") else { return -1 }
        return Int(probe[start.upperBound...]) ?? -1
    }
}
