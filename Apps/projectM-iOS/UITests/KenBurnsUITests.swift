// KenBurnsUITests.swift — MED-007-T09 on the iOS Simulator (MED-007-S5, R11): with a seeded photo
// (`-uitestSeedPhoto solid`) and the Photo visual (Settings opened at the section), Settings › Ken Burns turns on with "Zoom in, 10 s", the Movement
// menu chooses Zoom out, and the duration slider moves to its 2 s minimum. Simulator results are never
// device evidence (Constitution X). Waits are ceilings for a slow shared Mac, never frame budgets.
import XCTest

@MainActor
final class KenBurnsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var summary: String { app.staticTexts["kenBurnsSummary"].label }

    func testKenBurnsTurnsOnAndChangesItsMovement() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "photo", "-uitestSeedPhoto", "solid",
                               "-uitestSettingsSection", "kenBurns"] + Self.noStore   // Settings opens at Ken Burns (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let toggle = app.switches["kenBurnsToggle"]
        XCTAssertTrue(app.reveal(toggle, long: true), "the Ken Burns switch below the photo")
        XCTAssertEqual(summary, "Off")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(5) { () -> Bool in self.summary == "Zoom in, 10 s" }, "on with the default: \(summary)")

        let movement = app.buttons["kenBurnsMovementPicker"]
        XCTAssertTrue(app.reveal(movement), "the Movement menu")
        movement.tap()
        let zoomOut = app.buttons["Zoom out"].firstMatch
        XCTAssertTrue(zoomOut.appears(within: 5), "the menu lists the movements")
        zoomOut.tap()
        XCTAssertTrue(poll(5) { () -> Bool in self.summary == "Zoom out, 10 s" }, "Zoom out chosen: \(summary)")

        let duration = app.slider("kenBurnsDurationSlider")   // ACC-005: an adjustable element, not a slider
        XCTAssertTrue(app.reveal(duration), "the duration slider")
        duration.dragSlider(from: CGFloat(8) / 58, to: 0)
        XCTAssertTrue(poll(5) { () -> Bool in self.summary == "Zoom out, 2 s" }, "the shortest duration: \(summary)")
    }
}
