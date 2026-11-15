// WaterfallUITests.swift — VIS-020-T10 on the iOS Simulator: choosing Spectrum Waterfall in Settings, Bars offered, the
// visual shown with its value ("Newest at top, …") and the source started once (VIS-020 User Story 4; VIS-020-R9, R12;
// S6). One short test (owner rule 7: under 30 s). Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class WaterfallUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var waterfall: XCUIElement { app.descendants(matching: .any)["spectrumWaterfall"].firstMatch }
    private var value: String { waterfall.value as? String ?? "" }

    func testChoosingSpectrumWaterfall() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.spectrumWaterfall"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let bars = app.segmentedControls["barsPicker"]
        if !bars.appears(within: 2) { app.reveal(bars) }
        XCTAssertTrue(bars.appears(within: 5), "Bars offered")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(waterfall.appears(within: 10), "the waterfall is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Newest at top") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
