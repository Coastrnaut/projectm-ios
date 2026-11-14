// LissajousUITests.swift — VIS-004-T11 on the iOS Simulator: choosing Lissajous in Settings, Plot offered with
// X/Y selected, Persistence offered, Bars not offered, choosing Mid/Side, the visual shown with "Mid/Side" in
// its value and the source started once (VIS-004 User Story 1; VIS-004-R11, R14; S6). One short test (owner
// rule 7: under 30 s); the keys' persistence across a relaunch is LissajousAppTests' unit test.
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class LissajousUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var lissajous: XCUIElement { app.descendants(matching: .any)["lissajous"].firstMatch }
    private var value: String { lissajous.value as? String ?? "" }

    func testChoosingLissajousAndMidSide() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.lissajous"]
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let plot = app.segmentedControls["lissajousModePicker"]
        XCTAssertTrue(plot.appears(within: 5), "Plot offered for the Lissajous")
        XCTAssertTrue(plot.buttons["X/Y"].isSelected, "X/Y by default")
        XCTAssertTrue(app.switches["lissajousPersistenceToggle"].exists, "Persistence offered")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply to the Lissajous")
        plot.buttons["Mid/Side"].tap()
        XCTAssertTrue(plot.buttons["Mid/Side"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(lissajous.appears(within: 10), "the Lissajous is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Mid/Side, Persistence off") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
