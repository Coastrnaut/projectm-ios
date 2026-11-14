// NativeVisualUITests.swift — VIS-001-T25, T29 on the iOS Simulator: choosing the visual in Settings,
// persistence across relaunch, rotation with the circular spectrum on screen, switching back to
// projectM, the bar count, and the fallback notice (VIS-001 User Stories 1, 3, 4). Simulator results
// are never device evidence (Constitution X). Waits use generous ceilings, never frame budgets.
// Shortened 2026-11-13 under owner rule 7: `-autostart inAppPlayback` replaces the notice and chooser
// taps, and waits poll every 0.1 s (UITestWaits.swift) instead of about once a second. Every tap on a
// control follows `showControls()`, which restarts the controls' 5 s auto-hide (see there).
import XCTest

@MainActor
final class NativeVisualUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// `reset` starts from fresh settings; `-autostart inAppPlayback` (Debug) starts the reference
    /// track as the chooser's In-App Playback row does (VIS-001-T25's launch arguments).
    private func launch(reset: Bool, extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics", "-autostart", "inAppPlayback"]
            + extra + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var circularSpectrum: XCUIElement { app.descendants(matching: .any)["circularSpectrum"].firstMatch }
    private var projectM: XCUIElement { app.descendants(matching: .any)["visualizer"].firstMatch }
    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }

    private func openSettings() {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    private func choose(_ title: String) {
        openSettings()
        let row = app.visualRow(title)
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        closeSettings()
    }

    /// Polls `condition` on the main actor for up to 30 s.
    private func waitUntil(_ condition: () -> Bool) -> Bool { poll(30, condition) }

    /// Shows the controls with a fresh 5 s auto-hide (AppCoordinator.controlsAutoHide), so the next
    /// read or tap cannot race the timer. A tap on the visualization toggles the controls, so when
    /// they are shown this hides and shows them again; every path ends on a tap that shows them and
    /// restarts the timer. (Flake fixed 2026-11-13: "controls exist, then tap" failed with "settings"
    /// not found when the 5 s hide from launch fired between the check and the tap.)
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testProjectMIsTheDefaultAndCircularSpectrumReplacesIt() {
        launch(reset: true)
        XCTAssertTrue(projectM.appears(within: 10), "projectM by default")
        XCTAssertFalse(circularSpectrum.exists)
        choose("Circular Spectrum")
        XCTAssertTrue(circularSpectrum.appears(within: 10), "the circular spectrum is shown")
        XCTAssertTrue(projectM.disappears(within: 5), "projectM's view is gone while the native visual runs")
        showControls()
        XCTAssertTrue(app.staticTexts["currentVisual"].exists)
        for id in ["previous", "next", "random", "presets", "duplicateCurrent"] {
            XCTAssertFalse(app.buttons[id].exists, "\(id) hidden with the native visual (VIS-001-R13)")
        }
        for id in ["stop", "pauseResume", "settings"] { XCTAssertTrue(app.buttons[id].exists, id) }
        XCTAssertEqual(starts, "1", "switching the visual does not restart the source")

        choose("projectM")
        XCTAssertTrue(projectM.appears(within: 10), "projectM returns")
        XCTAssertTrue(circularSpectrum.disappears(within: 5))
        showControls()
        XCTAssertTrue(app.buttons["next"].exists)
        XCTAssertEqual(starts, "1")
    }

    func testChoiceAndBarsPersistAcrossRelaunch() {
        launch(reset: true)
        openSettings()
        app.visualRow("Circular Spectrum").tap()
        let bars = app.segmentedControls["barsPicker"]
        XCTAssertTrue(bars.appears(within: 5), "Bars offered for the circular spectrum")
        XCTAssertTrue(bars.buttons["64"].isSelected, "64 bars by default")
        bars.buttons["16"].tap()
        closeSettings()
        XCTAssertTrue(circularSpectrum.appears(within: 10))
        app.terminate()

        launch(reset: false)
        XCTAssertTrue(circularSpectrum.appears(within: 10), "the choice persisted")
        openSettings()
        XCTAssertTrue(app.visualRow("Circular Spectrum").isSelected)
        XCTAssertTrue(app.segmentedControls["barsPicker"].buttons["16"].isSelected, "the bar count persisted")
        closeSettings()
    }

    func testRotationKeepsTheCircularSpectrumWithoutRestartingTheSource() {
        launch(reset: true)
        choose("Circular Spectrum")
        XCTAssertTrue(circularSpectrum.appears(within: 10))
        let window = app.windows.firstMatch
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil { window.frame.width > window.frame.height }, "landscape within 30 s")
        XCTAssertTrue(circularSpectrum.exists, "still shown in landscape")
        // The rotation animation scales the view for a moment; wait for the final layout.
        XCTAssertTrue(waitUntil { abs(self.circularSpectrum.frame.width - window.frame.width) <= 1 },
                      "fills the landscape window: \(circularSpectrum.frame) in \(window.frame)")
        XCTAssertEqual(starts, "1", "rotation did not restart the source")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil { window.frame.height > window.frame.width }, "portrait within 30 s")
        XCTAssertTrue(circularSpectrum.exists, "still shown back in portrait")
        XCTAssertEqual(starts, "1")
    }

    func testUnavailableNativeVisualFallsBackToProjectMWithANotice() {
        launch(reset: true, extra: ["-uitestNativeVisualFailure"])
        choose("Circular Spectrum")
        XCTAssertTrue(app.staticTexts["nativeVisualUnavailable"].appears(within: 10), "visible notice (VIS-001-R16)")
        XCTAssertEqual(app.staticTexts["nativeVisualUnavailable"].label,
                       "Circular Spectrum isn't available on this device. Showing projectM.")
        XCTAssertTrue(projectM.exists, "projectM is shown instead")
        XCTAssertFalse(circularSpectrum.exists)
        openSettings()
        let footer = app.staticTexts["nativeVisualUnavailableFooter"]
        XCTAssertTrue(footer.appears(within: 5) || app.reveal(footer), "under the Visual rows (SCN-008 added snapshot rows)")
        closeSettings()
        XCTAssertEqual(starts, "1")
    }
}
