// ExternalDisplayUITests.swift — OUT-001-T10 on the iOS Simulator: with a fake external display
// (`-uitestExternalDisplay`, a DEBUG off-screen 1920 × 1080 window driven through the same
// coordinator calls as a real external scene), the device shows the note and keeps working
// controls. Disconnect brings the visualization back, and the audio source is started once
// throughout (OUT-001-S2). The real hot-plug runs with `simctl io … screenConfig` (quickstart B).
// Simulator results are never device evidence (OUT-001-T15 is). Owner rule 7: under 30 s.
// OUT-004-T08: Settings › External Display's Shape and Fit change the fake display's placement, read
// through the hidden `externalPlacement` probe (pillarbox bars with the portrait device shape and Fit).
// One Settings visit keeps it near the 30 s budget; Fill and Stretch are covered by
// ExternalOutputCorrectionTests.
import XCTest

@MainActor
final class ExternalDisplayUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }
    private var note: XCUIElement { app.descendants(matching: .any)["externalDisplayNote"].firstMatch }
    private var projectM: XCUIElement { app.descendants(matching: .any)["visualizer"].firstMatch }

    /// Shows the controls with a fresh 5 s auto-hide (as NativeVisualUITests.showControls).
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testConnectShowsTheNoteKeepsControlsAndNeverRestartsTheSource() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestExternalDisplay"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(projectM.appears(within: 10))
        XCTAssertFalse(note.exists, "no note without an external display")

        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(note.appears(within: 5), "the device shows the note (OUT-001-R2)")
        XCTAssertEqual(note.label, "The visualization is showing on the external display")
        XCTAssertEqual(starts, "1", "connecting does not restart the source")

        // The controls stay on the device and still work.
        showControls()
        app.buttons["pauseResume"].tap()
        XCTAssertTrue(app.staticTexts["pausedLabel"].appears(within: 5), "pause works while external")
        showControls()
        app.buttons["pauseResume"].tap()
        XCTAssertTrue(app.staticTexts["pausedLabel"].disappears(within: 5))
        XCTAssertTrue(note.exists)

        app.buttons["uitestDisconnectExternal"].tap()
        XCTAssertTrue(note.disappears(within: 5), "the visualization is back on the device")
        XCTAssertTrue(projectM.exists)
        XCTAssertEqual(starts, "1", "disconnecting does not restart the source")

        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(note.appears(within: 5), "reconnect")
        app.buttons["uitestDisconnectExternal"].tap()
        XCTAssertTrue(note.disappears(within: 5))
        XCTAssertEqual(starts, "1")
    }

    // MARK: - OUT-004-T08

    private var placement: String? { app.descendants(matching: .any)["externalPlacement"].firstMatch.value as? String }

    private func openSettings() {
        showControls()
        app.buttons["settings"].tap()
    }

    private func choose(_ picker: String, _ option: String) {
        let row = app.buttons[picker]
        XCTAssertTrue(app.reveal(row), "\(picker) is reachable")
        row.tap()
        let item = app.buttons[option].firstMatch.exists ? app.buttons[option].firstMatch : app.staticTexts[option].firstMatch
        XCTAssertTrue(item.appears(within: 3), "\(option) is listed")
        item.tap()
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    func testTheOutputCorrectionSettingChangesTheExternalPlacement() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestExternalDisplay", "-uitestSettingsSection", "externalDisplay"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(projectM.appears(within: 10))
        XCTAssertTrue(poll(3) { self.placement == "none" }, "the visual is on the device: \(placement ?? "nil")")

        openSettings()
        choose("externalShapePicker", "Device")
        closeSettings()
        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(note.appears(within: 5))
        XCTAssertTrue(poll(3) { (self.placement ?? "").hasPrefix("fit=fit shape=device par=1.00") },
                      "Fit with the device shape: \(placement ?? "nil")")
        XCTAssertTrue(placement?.hasSuffix("bars=pillarbox") == true, "a portrait device on 1920 × 1080 is pillarboxed: \(placement ?? "nil")")

        app.buttons["uitestDisconnectExternal"].tap()
        XCTAssertTrue(note.disappears(within: 5))
        XCTAssertTrue(poll(3) { self.placement == "none" })
    }
}
