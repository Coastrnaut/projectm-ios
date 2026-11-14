// MandalaUITests.swift — VIS-007-T11 on the iOS Simulator: choosing Mandala in Settings, Symmetry offered with 6
// selected, Mirror and Petal offered, Bars not offered, choosing 8, the visual shown with "8-fold" in its value and
// the source started once (VIS-007 User Story 1; VIS-007-R9, R11; S7). One short test (owner rule 7: under 30 s);
// the keys' persistence across a relaunch is MandalaAppTests' unit test.
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class MandalaUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var mandala: XCUIElement { app.descendants(matching: .any)["mandala"].firstMatch }
    private var value: String { mandala.value as? String ?? "" }

    func testChoosingMandalaAndEightFoldSymmetry() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.mandala"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let symmetry = app.segmentedControls["mandalaSymmetryPicker"]
        let petal = app.segmentedControls["mandalaPetalPicker"]
        if !petal.appears(within: 2) { app.reveal(petal) }   // the rows below the visual list (lazy until near the screen)
        XCTAssertTrue(symmetry.appears(within: 5), "Symmetry offered for the mandala")
        XCTAssertTrue(symmetry.buttons["6"].isSelected, "6-fold by default")
        XCTAssertTrue(app.switches["mandalaMirrorToggle"].exists, "Mirror offered")
        XCTAssertTrue(petal.exists, "Petal offered")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply to the mandala")
        symmetry.buttons["8"].tap()
        XCTAssertTrue(symmetry.buttons["8"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(mandala.appears(within: 10), "the mandala is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("8-fold, Mirror off, Petal") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
