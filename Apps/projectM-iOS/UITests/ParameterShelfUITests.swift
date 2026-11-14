// ParameterShelfUITests.swift — UIX-004-T11 on the iOS Simulator (S4; contracts/parameter-shelf.md P1, P2): pin
// Glow Intensity from the inspector (`-uitestInspectParameter`), find its slider in the visualizer's controls,
// move it, relaunch without the reset flag, and find it still pinned with the moved value. `-uitestKeepControls`
// keeps the controls up so the auto-hide cannot race the queries. Under 30 s (owner rule 7). Simulator results
// are UI evidence only (Constitution X).
import XCTest

@MainActor
final class ParameterShelfUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool, extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestKeepControls", "-autostart", "inAppPlayback"]
            + extra + Self.noStore
        app.launch()
    }

    private var shelfSlider: XCUIElement { app.otherElements["controls"].descendants(matching: .any).matching(identifier: "shelf.effect.bloom.intensity").firstMatch }

    func testPinFromTheInspectorShowsTheControlAndSurvivesARelaunch() {
        launch(reset: true, extra: ["-uitestInspectParameter", "effect.bloom.intensity"])
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertFalse(app.otherElements["parameterShelf"].exists, "no shelf without pins")
        app.buttons["settings"].tap()
        let pin = app.navigationBars.buttons["parameterInspector.pin"]   // in the sheet's navigation bar
        XCTAssertTrue(pin.appears(within: 5))
        XCTAssertEqual(pin.label, "Pin to Shelf")
        pin.tap()
        XCTAssertTrue(poll(3) { pin.label == "Remove from Shelf" }, "the button now removes the pin")
        app.buttons["parameterInspector.done"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()

        XCTAssertTrue(shelfSlider.appears(within: 5), "the pinned slider sits in the controls")
        XCTAssertEqual(shelfSlider.label, "Intensity")
        XCTAssertEqual(shelfSlider.value as? String, "50 percent")
        shelfSlider.dragSlider(from: 0.5, to: 0.85)
        XCTAssertTrue(poll(5) { (self.shelfSlider.value as? String) != "50 percent" }, "the shelf changed the setting")
        let moved: String? = shelfSlider.value as? String

        app.terminate()
        launch(reset: false)
        XCTAssertTrue(shelfSlider.appears(within: 10), "still pinned after a relaunch")
        XCTAssertEqual(shelfSlider.value as? String, moved, "the value written through the shelf was saved")
    }

    /// UIX-004-R7, R9: pins stored before launch (argument domain) with one unknown entry; at the AX5 text size
    /// the shelf stacks inside the scrolling controls, every pin and the note are reachable, and Remove clears
    /// only the unknown entry.
    func testAtTheLargestTextSizeTheShelfStacksAndReportsAMissingPin() {
        launch(reset: true, extra: ["-settings.parameterShelf.pins", "(effect.bloom.enabled, visual.circularSpectrum.barCount, gone.parameter)",
                                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let controls = app.otherElements["controls"]
        XCTAssertTrue(controls.appears(within: 10))
        let toggle = controls.descendants(matching: .any).matching(identifier: "shelf.effect.bloom.enabled").firstMatch
        let note = controls.staticTexts["shelf.missingNote"]
        XCTAssertTrue(note.appears(within: 5))
        XCTAssertEqual(note.label, "1 pinned control is no longer available")
        // The controls open at the bottom (ACC-006-R2): drag them down until the shelf's first control shows.
        let window = app.windows.firstMatch
        for _ in 0..<6 where !(toggle.exists && toggle.frame.minY >= window.frame.minY + 40) {
            let from = controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 400)), withVelocity: .default, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(toggle.isHittable, "the first pin is reachable at AX5")
        let bars = controls.descendants(matching: .any).matching(identifier: "shelf.visual.circularSpectrum.barCount").firstMatch
        XCTAssertTrue(bars.exists)
        XCTAssertGreaterThan(bars.frame.minY, toggle.frame.minY, "stacked, not side by side")
        XCTAssertLessThanOrEqual(toggle.frame.maxX, window.frame.maxX, "not clipped at the right edge")
        let remove = controls.buttons["shelf.removeMissing"]
        if !remove.isHittable { _ = poll(2) { remove.isHittable } }
        remove.tap()
        XCTAssertTrue(note.disappears(within: 3), "Remove deleted the unknown entry")
        XCTAssertTrue(toggle.exists && bars.exists, "the valid pins stay")
    }
}
