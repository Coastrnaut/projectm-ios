// ParameterBatchResetUITests.swift — UIX-010-T05 on the iOS Simulator (S4, R1, R5, R8, R10): launched with Bars 16
// and the horizontal orientation, Settings › Search Parameters › Select, tick Bars and Orientation, Reset; both
// rows show their defaults (64, Vertical); one Undo in the list's toolbar brings back 16 and Horizontal. Opens
// Settings at the search row with `-uitestSettingsSection parameterSearch` (owner rule 7: under 30 s). Simulator
// results are UI evidence only (Constitution X).
import XCTest

@MainActor
final class ParameterBatchResetUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testResetTwoParametersThenOneUndoRestoresBoth() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum", "-settings.circularSpectrum.bars", "16",
                               "-settings.linearSpectrum.orientation", "horizontal",
                               "-uitestSettingsSection", "parameterSearch", "-uitestSettingsSectionOnce"]
        app.launch()
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()

        let link = app.buttons["parameterSearchLink"].firstMatch
        XCTAssertTrue(link.appears(within: 5), "the Search Parameters row")
        if !link.isHittable { _ = app.reveal(link, down: true) }
        link.tap()

        app.buttons["parameterReset.select"].firstMatch.tap()
        let bars = app.descendants(matching: .any)["parameterResetToggle.visual.circularSpectrum.barCount"].firstMatch
        let orientation = app.descendants(matching: .any)["parameterResetToggle.visual.linearSpectrum.orientation"].firstMatch
        XCTAssertTrue(bars.appears(within: 5), "rows are toggles in selection mode")
        XCTAssertTrue(value(bars).hasPrefix("Not selected"), "toggle value: \(value(bars))")
        bars.tap()
        if !orientation.isHittable { _ = app.reveal(orientation, down: true) }
        orientation.tap()
        XCTAssertTrue(value(bars).hasPrefix("Selected"))

        let reset = app.buttons["parameterReset.reset"].firstMatch
        XCTAssertEqual(reset.label, "Reset 2 parameters to defaults")
        reset.tap()

        let barsRow = app.buttons["parameterSearchResult.visual.circularSpectrum.barCount"].firstMatch
        let orientationRow = app.buttons["parameterSearchResult.visual.linearSpectrum.orientation"].firstMatch
        XCTAssertTrue(barsRow.appears(within: 5), "the reset ends selection mode")
        XCTAssertTrue(value(barsRow).contains("Spectrum, 64"), "Bars at its default: \(value(barsRow))")
        XCTAssertTrue(value(orientationRow).contains("Vertical"), "Orientation at its default: \(value(orientationRow))")

        let undo = app.buttons["sceneUndo"].firstMatch
        XCTAssertEqual(undo.label, "Undo Reset 2 Parameters")
        undo.tap()
        XCTAssertTrue(waitFor(barsRow, containing: "Spectrum, 16"), "one Undo restores Bars: \(value(barsRow))")
        XCTAssertTrue(value(orientationRow).contains("Horizontal"), "and Orientation: \(value(orientationRow))")
    }

    private func value(_ element: XCUIElement) -> String { (element.value as? String) ?? "" }

    private func waitFor(_ element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5) == .completed
    }
}
