// SceneAutosaveUITests.swift — SCN-002-T09 on the iOS Simulator: the roadmap acceptance "Kill app after
// edit and relaunch; last committed scene is intact" (SCN-002-S1). A first edit is committed (closing
// Settings commits at once), a second edit is made and the app is killed before it is committed
// (`terminate()` stops the process; the DEBUG launch arguments stretch the quiet period so the second
// edit cannot commit on its own). The relaunched app restores the committed scene: the first edit,
// never the second, never the defaults. The `sceneAutosave` probe (DEBUG) reports the restore source
// and the committed revision. Simulator results are never device evidence (Constitution X); the device
// force quit is SCN-002-T10. Waits are ceilings for a slow shared Mac.
import XCTest

@MainActor
final class SceneAutosaveUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private static let slowAutosave = ["-uitestSceneAutosaveQuiet", "30", "-uitestSceneAutosaveMaxLatency", "60"]

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics", "-autostart", "inAppPlayback"]
            + Self.slowAutosave + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var circularSpectrum: XCUIElement { app.descendants(matching: .any)["circularSpectrum"].firstMatch }
    private var probe: String { app.staticTexts["sceneAutosave"].value as? String ?? "" }
    private var bars: XCUIElement { app.segmentedControls["barsPicker"] }

    /// See NativeVisualUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func openSettings() {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    func testKillAfterAnUncommittedEditRestoresTheLastCommittedScene() {
        launch(reset: true)
        XCTAssertTrue(poll(10) { self.probe.hasPrefix("restored=none committed=0 pending=0") }, "a fresh start: \(probe)")

        // Edit 1, committed: Circular Spectrum (commits at once), 16 bars, Settings closed (commits).
        openSettings()
        app.visualRow("Circular Spectrum").tap()
        XCTAssertTrue(bars.appears(within: 5))
        bars.buttons["16"].tap()
        XCTAssertTrue(bars.buttons["16"].isSelected)
        closeSettings()
        XCTAssertTrue(circularSpectrum.appears(within: 10))
        XCTAssertTrue(poll(10) { self.probe.contains("pending=0") && !self.probe.contains("committed=0") },
                      "edit 1 committed: \(probe)")

        // Edit 2, not committed: 32 bars with Settings still open, then the app is killed.
        openSettings()
        XCTAssertTrue(bars.appears(within: 5))
        bars.buttons["32"].tap()
        XCTAssertTrue(bars.buttons["32"].isSelected)
        app.terminate()

        launch(reset: false)
        XCTAssertTrue(circularSpectrum.appears(within: 10), "the visual choice persisted")
        XCTAssertTrue(poll(10) { self.probe.hasPrefix("restored=main committed=0 pending=0 events=0") },
                      "the committed scene was restored from the main file: \(probe)")
        openSettings()
        XCTAssertTrue(bars.appears(within: 5))
        XCTAssertTrue(bars.buttons["16"].isSelected, "the last committed bar count (edit 1) is restored intact")
        XCTAssertFalse(bars.buttons["32"].isSelected, "the uncommitted edit 2 is not")
        closeSettings()
    }
}
