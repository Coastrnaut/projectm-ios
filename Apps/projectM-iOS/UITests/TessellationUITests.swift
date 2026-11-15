// TessellationUITests.swift — VIS-018-T12 on the iOS Simulator: choosing Tessellation in Settings, its options offered at
// their defaults, Bars not offered, one more tile, the visual shown with the new count in its value and the source
// started once (VIS-018 User Story 5; VIS-018-R10, R13; S6). One short test (owner rule 7: under 30 s); persistence across
// a relaunch is TessellationAppTests' unit test. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class TessellationUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var tiles: XCUIElement { app.descendants(matching: .any)["tessellation"].firstMatch }
    private var value: String { tiles.value as? String ?? "" }

    func testChoosingTessellationAndAddingATile() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.tessellation"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let symmetry = app.segmentedControls["tessellationSymmetryPicker"]
        if !symmetry.appears(within: 2) { app.reveal(symmetry) }
        XCTAssertTrue(symmetry.appears(within: 5), "Symmetry offered")
        XCTAssertTrue(symmetry.buttons["6"].isSelected, "6-fold by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply")
        let stepper = app.steppers["tessellationTilesStepper"]
        if !stepper.appears(within: 2) { app.reveal(stepper) }
        XCTAssertTrue(stepper.appears(within: 5), "Tiles offered")
        stepper.buttons.element(boundBy: 1).tap()   // SwiftUI names the buttons "<id>-Increment"; the second is +
        XCTAssertTrue(poll(5) { (self.stepper(in: self.app).value as? String) == "7" }, "Tiles: 7")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(tiles.appears(within: 10), "the tessellation is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Hexagons, 7 tiles") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }

    private func stepper(in app: XCUIApplication) -> XCUIElement { app.steppers["tessellationTilesStepper"] }
}
