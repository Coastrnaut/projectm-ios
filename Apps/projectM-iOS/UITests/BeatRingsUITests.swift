// BeatRingsUITests.swift — VIS-006-T12 on the iOS Simulator: choosing Beat Rings in Settings, Ring life offered
// with Medium selected, Bars not offered, choosing Long, the visual shown with "Long ring life" in its value and
// the source started once (VIS-006 User Story 1; VIS-006-R9, R11; S6). One short test (owner rule 7: under
// 30 s); the key's persistence across a relaunch is BeatRingsAppTests' unit test.
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class BeatRingsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var rings: XCUIElement { app.descendants(matching: .any)["beatRings"].firstMatch }
    private var value: String { rings.value as? String ?? "" }

    func testChoosingBeatRingsAndLongLife() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.beatRings"]
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let life = app.segmentedControls["beatRingsLifePicker"]
        XCTAssertTrue(life.appears(within: 5), "Ring life offered for beat rings")
        XCTAssertTrue(life.buttons["Medium"].isSelected, "Medium ring life by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply to beat rings")
        life.buttons["Long"].tap()
        XCTAssertTrue(life.buttons["Long"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(rings.appears(within: 10), "beat rings are shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Long ring life") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
