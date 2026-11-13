// TextOverlayUITests.swift — MED-009-T17 on the iOS Simulator: the roadmap acceptance "Saved text
// renders identically after relaunch and handles Unicode" (MED-009-S1). Typing emoji and Arabic
// through XCUITest is unreliable, so `-uitestSeedText` (DEBUG only) saves the message through the
// editor's path; `textRendering` (DEBUG) reports the rendering's size and pixel checksum. Simulator
// results are never device evidence (Constitution X); right-to-left and emoji typing on devices is
// MED-009-T23. Waits are ceilings for a slow shared Mac.
import XCTest

@MainActor
final class TextOverlayUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private static let message = "Hello 👋🏽 مرحبا"

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback"] + extra + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var textVisual: XCUIElement { app.descendants(matching: .any)["textVisual"].firstMatch }
    private var rendering: String { app.staticTexts["textRendering"].value as? String ?? "" }

    /// See CameraUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    /// The text visual's value and its rendering (size and checksum) once drawn.
    private func shownText(_ message: String) -> (value: String?, rendering: String) {
        XCTAssertTrue(textVisual.appears(within: 10), "\(message): the Text visual is shown")
        XCTAssertTrue(poll(10) { self.rendering.contains("x") && self.rendering.count > 17 }, "\(message): drawn (\(rendering))")
        return (textVisual.value as? String, rendering)
    }

    func testSavedTextRendersIdenticallyAfterRelaunch() {
        launch(["-uitestResetNotice", "-uitestSeedText", Self.message])
        XCTAssertFalse(textVisual.exists, "projectM is the default visual")
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow("Text")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        let before = shownText("seeded")
        XCTAssertEqual(before.value, Self.message, "VoiceOver reads the saved message")

        app.terminate()
        launch([])   // no reset, no seed: only the saved text and the saved choice
        let after = shownText("after relaunch")
        XCTAssertEqual(after.value, Self.message, "the same message")
        XCTAssertEqual(after.rendering, before.rendering, "the same size and pixel checksum: rendered identically")
    }
}
