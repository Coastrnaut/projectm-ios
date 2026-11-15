// KaleidoscopeUITests.swift — VIS-014-T10 on the iOS Simulator: choosing Kaleidoscope in Settings, Wedges offered at 6,
// Bars not offered, one more wedge, the visual shown with "7 wedges" in its value and the source started once
// (VIS-014 User Story 3; VIS-014-R9, R12; S6). One short test (owner rule 7: under 30 s); persistence across a relaunch
// is KaleidoscopeAppTests' unit test. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class KaleidoscopeUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var kaleidoscope: XCUIElement { app.descendants(matching: .any)["kaleidoscope"].firstMatch }
    private var value: String { kaleidoscope.value as? String ?? "" }

    func testChoosingKaleidoscopeAndOneMoreWedge() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.kaleidoscope"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let wedges = app.descendants(matching: .any)["kaleidoscopeWedgesStepper"].firstMatch
        if !wedges.appears(within: 2) { app.reveal(wedges) }
        XCTAssertTrue(wedges.appears(within: 5), "Wedges offered")
        XCTAssertEqual(wedges.value as? String, "6", "6 by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply")
        let increment = wedges.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Increment'")).firstMatch
        XCTAssertTrue(increment.appears(within: 2), "the stepper's increment button")
        increment.tap()
        XCTAssertTrue(poll(5) { (wedges.value as? String) == "7" }, "value: \(String(describing: wedges.value))")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(kaleidoscope.appears(within: 10), "the kaleidoscope is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("7 wedges") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
