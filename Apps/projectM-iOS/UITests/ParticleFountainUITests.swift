// ParticleFountainUITests.swift — VIS-008-T12 on the iOS Simulator: choosing Particle Fountain in Settings, Gravity
// offered with Medium selected, Bars not offered, choosing High, the visual shown with "High gravity" in its value
// and the source started once (VIS-008 User Story 1; VIS-008-R10, R12; S8). One short test (owner rule 7: under
// 30 s); the key's persistence across a relaunch is ParticleFountainAppTests' unit test.
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class ParticleFountainUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var fountain: XCUIElement { app.descendants(matching: .any)["particleFountain"].firstMatch }
    private var value: String { fountain.value as? String ?? "" }

    func testChoosingParticleFountainAndHighGravity() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.particleFountain"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let gravity = app.segmentedControls["particleGravityPicker"]
        if !gravity.appears(within: 2) { app.reveal(gravity) }   // the rows below the visual list (lazy until near the screen)
        XCTAssertTrue(gravity.appears(within: 5), "Gravity offered for the fountain")
        XCTAssertTrue(gravity.buttons["Medium"].isSelected, "Medium by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply to the fountain")
        gravity.buttons["High"].tap()
        XCTAssertTrue(gravity.buttons["High"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(fountain.appears(within: 10), "the fountain is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("High gravity") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
