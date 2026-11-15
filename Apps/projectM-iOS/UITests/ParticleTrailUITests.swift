// ParticleTrailUITests.swift — VIS-010-T14 on the iOS Simulator: choosing Particle Fountain in Settings, Trails offered
// with Off selected, choosing Long, the visual shown with "Trails Long" in its value and the source started once
// (VIS-010 User Story 4; VIS-010-R9, R11; S5). One short test (owner rule 7: under 30 s); persistence is
// ParticleTrailAppTests' unit test. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class ParticleTrailUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var fountain: XCUIElement { app.descendants(matching: .any)["particleFountain"].firstMatch }
    private var value: String { fountain.value as? String ?? "" }

    func testChoosingParticleFountainWithLongTrails() {
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
        let trails = app.segmentedControls["particleTrailsPicker"]
        if !trails.appears(within: 2) { app.reveal(trails) }   // below the visual list (lazy until near the screen)
        XCTAssertTrue(trails.appears(within: 5), "Trails offered for the fountain")
        XCTAssertTrue(trails.buttons["Off"].isSelected, "Off by default")
        trails.buttons["Long"].tap()
        XCTAssertTrue(trails.buttons["Long"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(fountain.appears(within: 10), "the fountain is shown")
        XCTAssertTrue(poll(10) { self.value.hasSuffix("Trails Long") }, "value: \(value)")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
