// PresetColorFacetUITests.swift — PRE-004-T10 (spec PRE-004-S4): after a folder's thumbnails are made
// (`-uitestThumbnailFixture YES`: the instant fixture renderer through the real cache, encoder and
// decoder), the browser home shows colour chips; a chip replaces the home with the matching presets,
// and Clear restores it. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class PresetColorFacetUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func matching(_ prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    func testColourChipNarrowsTheHomeAndClearRestoresIt() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO",
                               "-autostart", "inAppPlayback", "-uitestThumbnailFixture", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 15))
        app.tapFreshControl("presets")
        let included = app.buttons["node:included"]
        XCTAssertTrue(included.appears(within: 10), "library home")
        included.tap()
        XCTAssertTrue(poll(10) { self.matching("thumbnail:").count >= 3 }, "thumbnails for the first rows")
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to the home

        let chip = matching("presetColorChip.").firstMatch
        XCTAssertTrue(chip.appears(within: 10), "colour chips after thumbnails")
        XCTAssertTrue(app.staticTexts["presetColorCoverage"].exists)
        XCTAssertFalse(chip.label.isEmpty, "a chip is named, not colour only")
        chip.tap()
        XCTAssertTrue(poll(5) { !self.app.buttons["node:included"].exists }, "the home is replaced by the filtered list")
        XCTAssertTrue(matching("preset:").firstMatch.appears(within: 5), "matching presets listed")
        XCTAssertTrue(chip.isSelected)

        app.buttons["presetColorClear"].tap()
        XCTAssertTrue(app.buttons["node:included"].appears(within: 5), "Clear restores the home")
    }
}
