// ParticleOrbitUITests.swift — VIS-009-T14 on the iOS Simulator: choosing Particle Orbit in Settings, Radius offered
// with Medium selected, Bars not offered, choosing Large, the visual shown with "Large radius" in its value and the
// source started once (VIS-009 User Story 3; VIS-009-R10, R12; S7). One short test (owner rule 7: under 30 s); the
// key's persistence across a relaunch is ParticleOrbitAppTests' unit test.
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class ParticleOrbitUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var orbit: XCUIElement { app.descendants(matching: .any)["particleOrbit"].firstMatch }
    private var value: String { orbit.value as? String ?? "" }

    func testChoosingParticleOrbitAndLargeRadius() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.particleOrbit"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let radius = app.segmentedControls["particleOrbitRadiusPicker"]
        if !radius.appears(within: 2) { app.reveal(radius) }   // the rows below the visual list (lazy until near the screen)
        XCTAssertTrue(radius.appears(within: 5), "Radius offered for the orbit")
        XCTAssertTrue(radius.buttons["Medium"].isSelected, "Medium by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply to the orbit")
        radius.buttons["Large"].tap()
        XCTAssertTrue(radius.buttons["Large"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(orbit.appears(within: 10), "the orbit is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Large radius") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
