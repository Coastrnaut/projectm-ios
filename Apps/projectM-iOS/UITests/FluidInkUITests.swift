// FluidInkUITests.swift — VIS-011-T11 on the iOS Simulator: choosing Fluid Ink in Settings, Bars not offered, the
// visual shown with its value ("Ink from sudden sounds, …") and the source started once (VIS-011 User Story 4; VIS-011-R12;
// S6). One short test (owner rule 7: under 30 s). Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class FluidInkUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var ink: XCUIElement { app.descendants(matching: .any)["fluidInk"].firstMatch }
    private var value: String { ink.value as? String ?? "" }

    func testChoosingFluidInk() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.fluidInk"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let bars = app.segmentedControls["barsPicker"]
        XCTAssertFalse(bars.exists, "Bars does not apply")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(ink.appears(within: 10), "fluid ink is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Ink from sudden sounds") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
