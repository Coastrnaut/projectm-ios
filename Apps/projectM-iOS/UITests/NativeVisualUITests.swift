// NativeVisualUITests.swift — VIS-001-T25, T29 on the iOS Simulator: choosing the visual in Settings,
// persistence across relaunch, rotation with the circular spectrum on screen, switching back to
// projectM, the bar count, and the fallback notice (VIS-001 User Stories 1, 3, 4). Simulator results
// are never device evidence (Constitution X). Waits use generous ceilings, never frame budgets.
import XCTest

@MainActor
final class NativeVisualUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool, extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics"] + extra + Self.noStore
        app.launch()
        if reset {
            let acknowledge = app.buttons["acknowledgeNotice"]
            XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
            acknowledge.tap()
        }
        let inApp = app.buttons["In-App Playback"]
        XCTAssertTrue(inApp.waitForExistence(timeout: 10))
        inApp.tap()
        XCTAssertTrue(app.staticTexts["sourceStarts"].waitForExistence(timeout: 10))
    }

    private var circularSpectrum: XCUIElement { app.descendants(matching: .any)["circularSpectrum"].firstMatch }
    private var projectM: XCUIElement { app.descendants(matching: .any)["visualizer"].firstMatch }
    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }

    private func openSettings() {
        if !app.buttons["settings"].waitForExistence(timeout: 2) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
    }

    private func choose(_ title: String) {
        openSettings()
        let picker = app.segmentedControls["visualPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons[title].tap()
        closeSettings()
    }

    /// Polls `condition` on the main actor for up to 30 s.
    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func showControls() {
        if !app.otherElements["controls"].waitForExistence(timeout: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.otherElements["controls"].waitForExistence(timeout: 5))
    }

    func testProjectMIsTheDefaultAndCircularSpectrumReplacesIt() {
        launch(reset: true)
        XCTAssertTrue(projectM.waitForExistence(timeout: 10), "projectM by default")
        XCTAssertFalse(circularSpectrum.exists)
        choose("Circular Spectrum")
        XCTAssertTrue(circularSpectrum.waitForExistence(timeout: 10), "the circular spectrum is shown")
        XCTAssertFalse(projectM.exists, "projectM's view is gone while the native visual runs")
        showControls()
        XCTAssertTrue(app.staticTexts["currentVisual"].exists)
        for id in ["previous", "next", "random", "presets", "duplicateCurrent"] {
            XCTAssertFalse(app.buttons[id].exists, "\(id) hidden with the native visual (VIS-001-R13)")
        }
        for id in ["stop", "pauseResume", "settings"] { XCTAssertTrue(app.buttons[id].exists, id) }
        XCTAssertEqual(starts, "1", "switching the visual does not restart the source")

        choose("projectM")
        XCTAssertTrue(projectM.waitForExistence(timeout: 10), "projectM returns")
        XCTAssertFalse(circularSpectrum.exists)
        showControls()
        XCTAssertTrue(app.buttons["next"].exists)
        XCTAssertEqual(starts, "1")
    }

    func testChoiceAndBarsPersistAcrossRelaunch() {
        launch(reset: true)
        openSettings()
        app.segmentedControls["visualPicker"].buttons["Circular Spectrum"].tap()
        let bars = app.segmentedControls["barsPicker"]
        XCTAssertTrue(bars.waitForExistence(timeout: 5), "Bars offered for the circular spectrum")
        XCTAssertTrue(bars.buttons["64"].isSelected, "64 bars by default")
        bars.buttons["16"].tap()
        closeSettings()
        XCTAssertTrue(circularSpectrum.waitForExistence(timeout: 10))
        app.terminate()

        launch(reset: false)
        XCTAssertTrue(circularSpectrum.waitForExistence(timeout: 10), "the choice persisted")
        openSettings()
        XCTAssertTrue(app.segmentedControls["visualPicker"].buttons["Circular Spectrum"].isSelected)
        XCTAssertTrue(app.segmentedControls["barsPicker"].buttons["16"].isSelected, "the bar count persisted")
        closeSettings()
    }

    func testRotationKeepsTheCircularSpectrumWithoutRestartingTheSource() {
        launch(reset: true)
        choose("Circular Spectrum")
        XCTAssertTrue(circularSpectrum.waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.staticTexts["nativeVisualUnavailable"].waitForExistence(timeout: 10), "visible notice (VIS-001-R16)")
        XCTAssertEqual(app.staticTexts["nativeVisualUnavailable"].label,
                       "Circular Spectrum isn't available on this device. Showing projectM.")
        XCTAssertTrue(projectM.exists, "projectM is shown instead")
        XCTAssertFalse(circularSpectrum.exists)
        openSettings()
        XCTAssertTrue(app.staticTexts["nativeVisualUnavailableFooter"].waitForExistence(timeout: 5))
        closeSettings()
        XCTAssertEqual(starts, "1")
    }
}
