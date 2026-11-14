// PresetOverridesUITests.swift — PRE-016-T13 (PRE-016-R12, R15, S2, S6; specs/185-pre-016-preset-overrides):
// on the iOS Simulator, the first Included preset's "Adjust Parameters…" sheet: the Zoom label starts
// at the preset's original value, a slider drag changes and stores it (its restore appears), and
// Reset to Original brings the label back to the original value. Launched with `-uitestResetNotice`
// (no saved overrides) and the fixed fake entitlement. Under 30 s (owner rule 7). Simulator only;
// never device evidence (Constitution X).
import XCTest

@MainActor
final class PresetOverridesUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openFirstIncludedRow() -> XCUIElement {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))
        app.tapFreshControl("presets")
        let included = app.buttons["node:included"]
        XCTAssertTrue(included.appears(within: 10), "library home")
        included.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch
        XCTAssertTrue(row.appears(within: 10))
        return row
    }

    private func openSheet(on row: XCUIElement) {
        row.press(forDuration: 1.2)
        var item = app.buttons["adjustPresetParameters"]
        if !item.appears(within: 3) { item = app.collectionViews.buttons["Adjust Parameters…"] }
        XCTAssertTrue(item.appears(within: 3), "the menu offers Adjust Parameters…")
        item.tap()
        XCTAssertTrue(app.slider("presetOverride.zoom").appears(within: 5), "the sheet shows the Zoom slider")
    }

    func testAdjustZoomThenResetReturnsTheOriginalValue() {
        openSheet(on: openFirstIncludedRow())
        let value = app.staticTexts["presetOverrideValue.zoom"]
        let original = app.staticTexts["presetOverrideOriginal.zoom"]
        XCTAssertTrue(value.appears(within: 5))
        XCTAssertTrue(poll(5) { original.label.hasPrefix("Original ") }, original.label)
        let originalText = String(original.label.dropFirst("Original ".count))
        XCTAssertTrue(poll(5) { value.label == originalText }, "starts at the original: \(value.label) vs \(originalText)")

        // ACC-005: the slider is one adjustable element (UITestSliders.swift); drag its thumb by touch.
        let slider = app.slider("presetOverride.zoom")
        let start: CGFloat = CGFloat(((Double(originalText) ?? 1) - 0.8) / 0.4)   // Zoom's range is 0.8 … 1.2
        let clampedStart: CGFloat = min(max(start, 0), 1)
        slider.dragSlider(from: clampedStart, to: clampedStart > 0.5 ? 0.1 : 0.9)
        let restore = app.buttons["presetOverrideReset.zoom"]
        XCTAssertTrue(restore.appears(within: 5), "the drag stored an adjustment")
        XCTAssertNotEqual(value.label, originalText, "the label shows the adjusted value")

        let resetAll = app.buttons["presetOverridesResetAll"]
        XCTAssertTrue(resetAll.isEnabled)
        resetAll.tap()
        XCTAssertTrue(poll(5) { value.label == originalText }, "back to the original: \(value.label) vs \(originalText)")
        XCTAssertTrue(restore.disappears(within: 5))
        XCTAssertFalse(resetAll.isEnabled)
        app.buttons["presetOverridesDone"].tap()
    }
}
