// PhotoLayerUITests.swift — MED-001-T15, T16 on the iOS Simulator: the roadmap acceptance "Selected
// image renders after relaunch when copied into app storage" (MED-001-S1, S2, S4). System pickers
// cannot be automated, so `-uitestSeedPhoto solid` (DEBUG only) imports a generated 64 × 48 PNG
// through the app's import path before the first screen; the real pickers are device tasks
// (T22-T24). Simulator results are never device evidence (Constitution X). Waits are ceilings for
// a slow shared Mac, never frame budgets.
import XCTest

@MainActor
final class PhotoLayerUITests: XCTestCase {
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

    private var photoVisual: XCUIElement { app.descendants(matching: .any)["photoVisual"].firstMatch }
    private var photoValue: String? { photoVisual.value as? String }
    private var framesShown: Int { Int(app.staticTexts["photoFramesShown"].value as? String ?? "") ?? -1 }

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

    private func assertPhotoShown(_ message: String) {
        XCTAssertTrue(photoVisual.appears(within: 10), "\(message): the Photo visual is shown")
        XCTAssertTrue(poll(10) { self.photoValue == "Photo 64 × 48" }, "\(message): VoiceOver value \(String(describing: photoValue))")
        XCTAssertTrue(poll(10) { self.framesShown > 0 }, "\(message): frames show the photo")
        let first = framesShown
        XCTAssertTrue(poll(10) { self.framesShown > first }, "\(message): and keep coming (\(first) → \(framesShown))")
    }

    /// S1, S2, S4: a seeded photo renders, renders again after a relaunch without the seed, and
    /// Remove Photo returns the layer to "No photo".
    func testImportedPhotoRendersAfterRelaunchAndCanBeRemoved() {
        launch(["-uitestResetNotice", "-uitestSeedPhoto", "solid"])
        XCTAssertFalse(photoVisual.exists, "projectM is the default visual")
        openSettings()
        let row = app.visualRow("Photo")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        XCTAssertTrue(scrollTo(app.buttons["removePhoto"]), "a stored photo offers Remove Photo")
        XCTAssertTrue(app.buttons["choosePhotoFromFiles"].exists)
        closeSettings()
        assertPhotoShown("seeded")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "choosing Photo does not restart the source")

        app.terminate()
        launch([])   // no reset, no seed: only the stored copy and the stored choice
        assertPhotoShown("after relaunch")

        openSettings()
        XCTAssertTrue(scrollTo(app.buttons["removePhoto"]))
        app.buttons["removePhoto"].tap()
        XCTAssertTrue(app.buttons["removePhoto"].disappears(within: 5), "removed")
        closeSettings()
        XCTAssertTrue(poll(10) { self.photoValue == "No photo" }, "the layer falls back: \(String(describing: photoValue))")
        XCTAssertFalse(app.otherElements["photoNotice"].exists, "removing is not an error")
    }
}
