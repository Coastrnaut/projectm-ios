// SceneCompareUITests.swift — SCN-009-T10 (US1, US2; SCN-009-R1, R3, R7, S6) on the iOS Simulator: with Glow on,
// Save Snapshot at 50 %, move Intensity to 100 %, Save Snapshot again, then Compare A/B… › Start Compare (A =
// Snapshot 1, B = Snapshot 2). Settings closes, the "Comparing A/B" bar shows A; B, A, B switch it; Done › Keep A
// ends Compare and Settings shows 50 % again. The no-write proof is SceneCompareAcceptanceTests. `-settings.visual
// circularSpectrum` (argument domain) sets the visual without taps (owner rule 7: under 30 s). Simulator results
// are never device evidence (Constitution X).
import XCTest

@MainActor
final class SceneCompareUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var bar: XCUIElement { app.descendants(matching: .any)["sceneCompareBar"].firstMatch }

    private func openSettings() {
        let area = app.otherElements["visualizerTapArea"].firstMatch
        if !app.buttons["settings"].appears(within: 1) { area.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    func testCompareSwitchesAndKeepA() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXS"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 15), "the Circular Spectrum is shown")
        openSettings()

        let glow = app.switches["glowToggle"]
        XCTAssertTrue(glow.appears(within: 2) || app.reveal(glow), "the Glow toggle")
        if (glow.value as? String) != "1" { glow.switches.firstMatch.exists ? glow.switches.firstMatch.tap() : glow.tap() }
        let intensity = app.slider("glowIntensitySlider")
        XCTAssertTrue(intensity.appears(within: 2), "Glow is on")
        XCTAssertEqual(intensity.value as? String, "50 percent")

        let save = app.buttons["snapshotSave"]
        XCTAssertTrue(save.isHittable || app.reveal(save), "the Snapshots rows")
        save.tap()
        XCTAssertTrue(intensity.isHittable || app.reveal(intensity, down: true))
        intensity.dragSlider(from: 0.5, to: 1)
        XCTAssertTrue(poll(5) { (intensity.value as? String) == "100 percent" }, "moved: \(String(describing: intensity.value))")
        XCTAssertTrue(save.isHittable || app.reveal(save))
        save.tap()

        let open = app.buttons["sceneCompareOpen"]
        XCTAssertTrue(open.isHittable || app.reveal(open), "the Compare row")
        XCTAssertTrue(poll(5) { open.isEnabled })
        open.tap()
        let start = app.buttons["sceneCompareStart"]
        XCTAssertTrue(start.appears(within: 5), "the setup sheet")
        start.tap()

        XCTAssertTrue(bar.appears(within: 5), "the Comparing A/B bar")
        XCTAssertFalse(app.navigationBars["Settings"].exists, "Settings closed")
        XCTAssertEqual(bar.value as? String, "A, Snapshot 1")
        for (id, value) in [("sceneCompareSideB", "B, Snapshot 2"), ("sceneCompareSideA", "A, Snapshot 1"),
                            ("sceneCompareSideB", "B, Snapshot 2")] {
            app.buttons[id].tap()
            XCTAssertTrue(poll(3) { (self.bar.value as? String) == value }, "shown: \(String(describing: bar.value))")
        }

        app.buttons["sceneCompareDone"].tap()
        let keepA = app.buttons["sceneCompareKeepA"]
        XCTAssertTrue(keepA.appears(within: 3), "the Finish Compare question")
        keepA.tap()
        XCTAssertTrue(poll(3) { !self.bar.exists }, "Compare ended")

        openSettings()
        XCTAssertTrue(intensity.appears(within: 2) || app.reveal(intensity))
        XCTAssertTrue(poll(5) { (intensity.value as? String) == "50 percent" }, "kept A: \(String(describing: intensity.value))")
    }
}
