// PresetEnergyFacetUITests.swift — PRE-005-T14 (spec PRE-005-S5): after a folder's thumbnails are made
// (`-uitestThumbnailFixture YES`: the instant fixture renderer, which writes one score per class into the
// PNG, through the real cache and decoder), the browser home shows motion chips; a chip replaces the home
// with the matching presets, and Clear restores it. Simulator results are never device evidence.
import XCTest

@MainActor
final class PresetEnergyFacetUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func matching(_ prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    func testMotionChipNarrowsTheHomeAndClearRestoresIt() {
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

        let chip = matching("presetEnergyChip.").firstMatch
        XCTAssertTrue(chip.appears(within: 10), "motion chips after thumbnails")
        XCTAssertTrue(app.staticTexts["presetEnergyCoverage"].exists)
        XCTAssertTrue(chip.label.hasSuffix("motion"), "a chip is named: \(chip.label)")
        chip.tap()
        XCTAssertTrue(poll(5) { !self.app.buttons["node:included"].exists }, "the home is replaced by the filtered list")
        XCTAssertTrue(matching("preset:").firstMatch.appears(within: 5), "matching presets listed")
        XCTAssertTrue(chip.isSelected)

        app.buttons["presetEnergyClear"].tap()
        XCTAssertTrue(app.buttons["node:included"].appears(within: 5), "Clear restores the home")
    }
}
