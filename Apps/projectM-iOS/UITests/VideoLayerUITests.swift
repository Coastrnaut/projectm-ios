// VideoLayerUITests.swift — MED-002-T21 on the iOS Simulator: the roadmap row "Choose compatible
// local video and render frames as a layer" (MED-002-S4, S6). System pickers cannot be automated, so
// `-uitestSeedVideo counter` (DEBUG only) writes a 64 × 48, 30 fps, 2 s movie and imports it through
// the app's import path; the real pickers are device tasks (T26-T28). The diagnostics text
// `videoFrameIndex` is the shown picture's index on the 30 fps timeline. Simulator results are never
// device evidence (Constitution X); waits are ceilings for a slow shared Mac, never frame budgets.
import XCTest

@MainActor
final class VideoLayerUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback"] + extra + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var videoVisual: XCUIElement { app.descendants(matching: .any)["videoVisual"].firstMatch }
    private var videoValue: String? { videoVisual.value as? String }
    private var frameIndex: Int? { Int(app.staticTexts["videoFrameIndex"].value as? String ?? "") }

    /// See CameraUITests.showControls.
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

    /// Held drags, not swipes (see SettingsUITests.scrollTo).
    @discardableResult
    private func scrollTo(_ element: XCUIElement) -> Bool {
        let window = app.windows.firstMatch
        let top = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            bottom.press(forDuration: 0.05, thenDragTo: top, withVelocity: .default, thenHoldForDuration: 0.1)
        }
        return element.exists
    }

    /// The video plays: its size is announced and the shown picture's index changes.
    private func assertVideoPlays(_ message: String) {
        XCTAssertTrue(videoVisual.appears(within: 10), "\(message): the Video visual is shown")
        XCTAssertTrue(poll(10) { self.videoValue == "Video 64 × 48" }, "\(message): VoiceOver value \(String(describing: videoValue))")
        XCTAssertTrue(poll(10) { self.frameIndex != nil }, "\(message): a picture is shown")
        let first = frameIndex
        XCTAssertTrue(poll(10) { self.frameIndex != nil && self.frameIndex != first },
                      "\(message): the pictures advance (\(String(describing: first)) → \(String(describing: frameIndex)))")
    }

    /// S4, S6: a seeded video plays, plays again after a relaunch without the seed, and Remove Video
    /// returns the layer to "No video".
    func testImportedVideoPlaysAfterRelaunchAndCanBeRemoved() {
        launch(["-uitestResetNotice", "-uitestSeedVideo", "counter"])
        XCTAssertFalse(videoVisual.exists, "projectM is the default visual")
        openSettings()
        let row = app.visualRow("Video")
        XCTAssertTrue(scrollTo(row))
        row.tap()
        XCTAssertTrue(scrollTo(app.buttons["removeVideo"]), "a stored video offers Remove Video")
        XCTAssertTrue(app.buttons["chooseVideoFromFiles"].exists)
        closeSettings()
        assertVideoPlays("seeded")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "choosing Video does not restart the audio source")

        app.terminate()
        launch([])   // no reset, no seed: only the stored copy and the stored choice
        assertVideoPlays("after relaunch")

        openSettings()
        XCTAssertTrue(scrollTo(app.buttons["removeVideo"]))
        app.buttons["removeVideo"].tap()
        XCTAssertTrue(app.buttons["removeVideo"].disappears(within: 5), "removed")
        closeSettings()
        XCTAssertTrue(poll(10) { self.videoValue == "No video" }, "the layer falls back: \(String(describing: videoValue))")
        XCTAssertFalse(app.otherElements["videoNotice"].exists, "removing is not an error")
    }
}
