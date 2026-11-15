// FixturePreviewUITests.swift — SHD-012-T11 on the iOS Simulator (R6; S4): Settings › Noise editor › Play fixture
// renders the 120-frame fixture run and shows its summary; Stop, then Play again renders a second run with the same run
// digest. Opens Settings at the section (owner rule 7: under 30 s). Simulator results are UI evidence only
// (Constitution X).
import XCTest

@MainActor
final class FixturePreviewUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testPlayFixtureTwiceGivesTheSameRun() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum",
                               "-uitestSettingsSection", "noiseEditor", "-uitestSettingsSectionOnce"]
        app.launch()
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()

        let link = app.buttons["noiseEditorLink"].firstMatch
        XCTAssertTrue(link.appears(within: 5), "the Noise editor row")
        if !link.isHittable { _ = app.reveal(link, down: true) }
        link.tap()

        let play = app.buttons["fixturePreviewPlay"].firstMatch
        XCTAssertTrue(app.reveal(play), "Play fixture")
        let summary = app.staticTexts["fixturePreviewSummary"].firstMatch
        XCTAssertTrue(app.reveal(summary), "the summary")
        XCTAssertEqual(summary.label, "Not rendered")
        play.tap()
        XCTAssertTrue(poll(15) { summary.label.hasPrefix("120 frames") }, "first run: \(summary.label)")
        let first: String = summary.label
        XCTAssertTrue(first.contains("Warp amount"), first)
        XCTAssertTrue(first.contains(" · run "), first)
        XCTAssertEqual(play.value as? String, "Run 1")
        XCTAssertEqual(play.label, "Stop", "the loop plays")

        play.tap()   // Stop
        XCTAssertTrue(poll(5) { play.label == "Play fixture" })
        play.tap()   // second run
        XCTAssertTrue(poll(15) { (play.value as? String) == "Run 2" }, "second run")
        XCTAssertEqual(summary.label, first, "same settings, same run digest")
    }
}
