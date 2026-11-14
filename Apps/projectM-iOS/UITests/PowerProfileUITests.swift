// PowerProfileUITests.swift — PERF-008-T13 on the iOS Simulator: Settings → Power opens at the section, Standard is
// selected after the reset, picking Battery saver selects it, and the audio source was not restarted (the DEBUG
// `sourceStarts` count is the same before and after). Persistence and the budgets are proven by
// `PowerProfileAppTests`. One short test (owner rule 7: under 30 s). Simulator results are never device evidence.
import XCTest

@MainActor
final class PowerProfileUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func sourceStarts() -> String {
        let element = app.staticTexts["sourceStarts"]
        return (element.value as? String) ?? element.label
    }

    func testPickingBatterySaverSelectsItWithoutRestartingTheSource() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "powerProfile"] + Self.noStore   // opens at Power (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let startsBefore = sourceStarts()

        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let standard = app.buttons["powerProfile.standard"]
        let saver = app.buttons["powerProfile.batterySaver"]
        XCTAssertTrue(app.reveal(saver, long: true), "the Power section is in Settings")
        XCTAssertTrue(standard.isSelected, "Standard after the reset")
        XCTAssertFalse(saver.isSelected)
        saver.tap()
        XCTAssertTrue(poll(3) { saver.isSelected }, "Battery saver is selected")
        XCTAssertFalse(standard.isSelected)

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 5))
        XCTAssertEqual(sourceStarts(), startsBefore, "the profile change did not restart the audio source")
    }
}
