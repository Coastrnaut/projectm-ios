// HapticBeatUITests.swift — ACC-007-T09 (S5, contract C4) on the iOS Simulator: Settings → Haptics. The switch
// starts off with the choices hidden; on shows "Pulse on" and "Strength"; off hides them again. The simulator has
// no haptics, so DEBUG `-uitestHapticsAvailable` enables the switch (research ACC-007-D7); without hardware nothing
// is installed or played, so no pulse is checked here (ACC-007-T13 is the device check). Settings opens at the section (owner rule 7: < 30 s).
import XCTest

@MainActor
final class HapticBeatUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func flip(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    func testSwitchShowsAndHidesTheChoices() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestHapticsAvailable", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "haptics"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 3))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let toggle = app.switches["hapticBeatToggle"]
        XCTAssertTrue(toggle.appears(within: 3) || app.reveal(toggle), "Settings → Haptics → Haptic beat pulses")
        XCTAssertEqual(toggle.value as? String, "0", "off by default")
        XCTAssertTrue(toggle.isEnabled)
        let event = app.descendants(matching: .any)["hapticBeatEventPicker"].firstMatch
        let strength = app.descendants(matching: .any)["hapticBeatStrengthPicker"].firstMatch
        XCTAssertFalse(event.exists, "choices hidden while off")

        flip(toggle)
        XCTAssertTrue(poll(2) { (toggle.value as? String) == "1" })
        XCTAssertTrue(event.appears(within: 2) || app.reveal(event), "Pulse on")
        XCTAssertTrue(strength.exists || app.reveal(strength), "Strength")

        flip(toggle)
        XCTAssertTrue(poll(2) { (toggle.value as? String) == "0" })
        XCTAssertTrue(event.disappears(within: 2), "hidden again")
    }
}
