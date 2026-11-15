// StarfieldUITests.swift — VIS-016-T11 on the iOS Simulator: choosing Starfield in Settings, Speed offered at Medium and
// Stars at 600, Bars not offered, choosing Fast and one more step of stars, the visual shown with both in its value and
// the source started once (VIS-016 User Story 5; VIS-016-R8, R11; S5). One short test (owner rule 7: under 30 s);
// persistence across a relaunch is StarfieldAppTests' unit test. Simulator results are never device evidence
// (Constitution X).
import XCTest

@MainActor
final class StarfieldUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var starfield: XCUIElement { app.descendants(matching: .any)["starfield"].firstMatch }
    private var value: String { starfield.value as? String ?? "" }

    func testChoosingStarfieldFastWithMoreStars() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.starfield"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let speed = app.segmentedControls["starfieldSpeedPicker"]
        if !speed.appears(within: 2) { app.reveal(speed) }
        XCTAssertTrue(speed.appears(within: 5), "Speed offered")
        XCTAssertTrue(speed.buttons["Medium"].isSelected, "Medium by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply")
        speed.buttons["Fast"].tap()
        XCTAssertTrue(speed.buttons["Fast"].isSelected)
        let stars = app.steppers["starfieldDensityStepper"]
        if !stars.appears(within: 2) { app.reveal(stars) }
        XCTAssertTrue(stars.appears(within: 5), "Stars offered")
        stars.buttons.element(boundBy: 1).tap()   // increment: 600 → 700
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(starfield.appears(within: 10), "the starfield is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Fast speed, 700 stars") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
