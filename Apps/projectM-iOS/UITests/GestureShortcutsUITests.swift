// GestureShortcutsUITests.swift — UIX-006-T10 on the iOS Simulator (specs/290-uix-006-touch-gesture-mapping; S5;
// contract G4, G5). Settings → Gesture shortcuts: switch on, Two-finger tap → Next preset; with the controls hidden a
// two-finger tap on the visualization changes the preset without showing the controls (one action per touch, R3);
// with the switch turned off again, a two-finger tap runs nothing and the preset stays. The DEBUG probes read the
// last shortcut and the shown preset with the controls hidden. Simulator results are never device evidence
// (UIX-006-T14). Owner rule 7: under 30 s; UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class GestureShortcutsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }
    private var toggle: XCUIElement { app.switches["gestureShortcutsToggle"] }
    private var last: String? { app.staticTexts["gestureShortcutLast"].value as? String }
    private var preset: String? { app.staticTexts["gestureShortcutPreset"].value as? String }

    private func openSettings() {
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(toggle.appears(within: 3) || app.reveal(toggle), "Settings → Gesture shortcuts")
    }

    private func flipSwitch(to value: String) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(2) { (self.toggle.value as? String) == value })
    }

    private func closeSettingsAndHideControls() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 3))
        for _ in 0..<3 where controls.exists {
            area.tap()
            if controls.disappears(within: 1.5) { break }
        }
        XCTAssertFalse(controls.exists, "the controls are hidden")
    }

    func testTwoFingerTapRunsTheMappedActionAndTheSwitchDisablesIt() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "gestureShortcuts"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertEqual(last, "none:0")

        // Map: switch on, Two-finger tap → Next preset.
        openSettings()
        flipSwitch(to: "1")
        let picker = app.buttons["gestureShortcut.twoFingerTap"]
        XCTAssertTrue(picker.appears(within: 3) || app.reveal(picker), "the two-finger tap picker")
        picker.tap()
        let item = app.buttons["Next preset"].firstMatch
        XCTAssertTrue(item.appears(within: 3), "menu item Next preset")
        item.tap()
        closeSettingsAndHideControls()
        XCTAssertTrue(poll(10) { (self.preset ?? "none") != "none" }, "a preset is loaded")
        let before: String = preset ?? ""

        area.twoFingerTap()
        XCTAssertTrue(poll(3) { self.last == "nextPreset:1" }, "probe: \(last ?? "nil")")
        XCTAssertTrue(poll(5) { self.preset != before }, "the preset changed from \(before)")
        XCTAssertFalse(controls.exists, "the controls' tap did not also fire")
        let after: String = preset ?? ""

        // Disable: switch off; a two-finger tap runs nothing.
        openSettings()
        flipSwitch(to: "0")
        closeSettingsAndHideControls()
        area.twoFingerTap()
        XCTAssertFalse(poll(1) { self.last != "nextPreset:1" }, "no shortcut ran")
        XCTAssertEqual(preset, after, "the preset did not change")
    }
}
