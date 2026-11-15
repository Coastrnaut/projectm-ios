// CymaticUITests.swift — VIS-019-T11 on the iOS Simulator: choosing Cymatic Lines in Settings, Bands offered at All, Bars
// not offered, choosing Low, the visual shown with the range in its value and the source started once (VIS-019 User
// Story 3; VIS-019-R10, R13; S6). One short test (owner rule 7: under 30 s); persistence across a relaunch is
// CymaticAppTests' unit test. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class CymaticUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var lines: XCUIElement { app.descendants(matching: .any)["cymatic"].firstMatch }
    private var value: String { lines.value as? String ?? "" }

    func testChoosingCymaticLinesWithLowBands() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.cymatic"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let bands = app.segmentedControls["cymaticBandsPicker"]
        if !bands.appears(within: 2) { app.reveal(bands) }
        XCTAssertTrue(bands.appears(within: 5), "Bands offered")
        XCTAssertTrue(bands.buttons["All"].isSelected, "All by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply")
        bands.buttons["Low"].tap()
        XCTAssertTrue(bands.buttons["Low"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(lines.appears(within: 10), "the cymatic lines are shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Low bands") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
