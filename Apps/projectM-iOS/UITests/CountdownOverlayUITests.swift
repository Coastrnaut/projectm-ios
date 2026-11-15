// CountdownOverlayUITests.swift — MED-012-T10 on the iOS Simulator (MED-012-S5, R1, R5, R7, R9): with a frozen
// monotonic clock (`-uitestCountdownFixed`), the countdown is off at launch; Settings › Countdown › Show Countdown and
// Start make the Text visual's countdown layer draw "05:00", running (DEBUG probe `countdownProbe`: "<text> <state>
// finished=<n> drawn=<frames>"). Settings opens at the Countdown section (`-uitestSettingsSection countdown`; owner rule
// 7). Simulator results are never device evidence (Constitution X). Waits are ceilings for a slow shared Mac.
import XCTest

@MainActor
final class CountdownOverlayUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: String { app.staticTexts["countdownProbe"].value as? String ?? "" }

    /// See CameraUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testShowAndStartDrawTheCountdownOverTheTextVisual() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "text", "-uitestCountdownFixed", "1000",
                               "-uitestSettingsSection", "countdown"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.staticTexts["countdownProbe"].appears(within: 5))
        XCTAssertTrue(probe.hasPrefix("none idle finished=0 drawn=0"), "off by default: \(probe)")

        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let toggle = app.switches["showCountdownToggle"]
        XCTAssertTrue(app.reveal(toggle), "the Countdown section")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let start = app.buttons["countdownStartButton"]
        XCTAssertTrue(app.reveal(start), "the Start button")
        start.tap()
        XCTAssertTrue(app.buttons["Pause"].appears(within: 5), "Start became Pause")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))

        let drawn: Bool = poll(15) { () -> Bool in Self.frames(self.probe) > 0 }
        XCTAssertTrue(drawn, "the Text visual's countdown layer showed the countdown: \(probe)")
        XCTAssertTrue(probe.hasPrefix("05:00 running finished=0 "), "the frozen clock's string: \(probe)")
    }

    /// The `n` of "... drawn=<n>" (-1 when unreadable).
    nonisolated static func frames(_ probe: String) -> Int {
        guard let start = probe.range(of: "drawn=") else { return -1 }
        return Int(probe[start.upperBound...]) ?? -1
    }
}
