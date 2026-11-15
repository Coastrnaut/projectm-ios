// ReactionDiffusionUITests.swift — VIS-012-T11 on the iOS Simulator: choosing Reaction Diffusion in Settings, its
// options offered (Preset, Seed pattern, Seed, Speed), Bars not offered, raising the seed to 2, the visual shown with
// that seed in its value and the source started once (VIS-012 User Story 4; VIS-012-R13; S7). One short test (owner
// rule 7: under 30 s); persistence across a relaunch is ReactionDiffusionAppTests' unit test. Simulator results are
// never device evidence (Constitution X).
import XCTest

@MainActor
final class ReactionDiffusionUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var reaction: XCUIElement { app.descendants(matching: .any)["reactionDiffusion"].firstMatch }
    private var value: String { reaction.value as? String ?? "" }

    func testChoosingReactionDiffusionAndANewSeed() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.reactionDiffusion"]
        if !row.exists { app.reveal(row) }   // below the fold: scroll at once
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let seed = app.descendants(matching: .any)["reactionSeedStepper"].firstMatch
        if !seed.exists { app.reveal(seed) }
        XCTAssertTrue(seed.appears(within: 5), "Seed offered")
        XCTAssertTrue(app.descendants(matching: .any)["reactionPresetPicker"].exists, "Preset offered")
        XCTAssertTrue(app.descendants(matching: .any)["reactionSpeedStepper"].exists, "Speed offered")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply")
        XCTAssertEqual(seed.value as? String, "1", "seed 1 by default")
        let increment = seed.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Increment'")).firstMatch
        XCTAssertTrue(increment.appears(within: 2), "the stepper's increment button")
        increment.tap()
        XCTAssertTrue(poll(5) { (seed.value as? String) == "2" }, "value: \(String(describing: seed.value))")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(reaction.appears(within: 10), "reaction diffusion is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Coral, Centre Square, seed 2, speed 8") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
