// SceneUndoUITests.swift — SCN-010-T08 on the iOS Simulator (SCN-010-S5): Settings' Undo and Redo
// restore the bar count and the glow without restarting the audio source, and their accessibility
// labels name the step. Simulator results are never device evidence (Constitution X). Waits are
// ceilings for a slow shared Mac (UITestWaits.swift).
import XCTest

@MainActor
final class SceneUndoUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }
    private var bars: XCUIElement { app.segmentedControls["barsPicker"] }
    private var glowToggle: XCUIElement { app.switches["glowToggle"] }
    private var intensity: XCUIElement { app.slider("glowIntensitySlider") }
    private var undo: XCUIElement { app.navigationBars["Settings"].buttons["sceneUndo"] }
    private var redo: XCUIElement { app.navigationBars["Settings"].buttons["sceneRedo"] }

    private func isOn(_ toggle: XCUIElement) -> Bool { (toggle.value as? String) == "1" }

    func testUndoAndRedoRestoreBarsAndGlowWithoutRestartingTheSource() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(undo.exists && !undo.isEnabled, "nothing to undo after launch")
        XCTAssertFalse(redo.isEnabled)

        // Edits: Circular Spectrum, 16 bars, Glow on, intensity dragged to 100%.
        app.visualRow("Circular Spectrum").tap()
        XCTAssertTrue(bars.appears(within: 5))
        bars.buttons["16"].tap()
        XCTAssertTrue(poll(5) { self.undo.label == "Undo Bars 16" }, "undo names the step: \(undo.label)")
        XCTAssertTrue(glowToggle.appears(within: 2) || app.reveal(glowToggle))
        glowToggle.switches.firstMatch.exists ? glowToggle.switches.firstMatch.tap() : glowToggle.tap()
        // Fully on screen before the drag (2026-11-14, SCN-008): the slider can exist just below the fold once the Visual
        // section grows, and a drag at its off-screen frame does nothing; `reveal` returns at once when it is visible.
        XCTAssertTrue(intensity.appears(within: 2) && app.reveal(intensity))
        intensity.dragSlider(from: 0.5, to: 1)   // ACC-005: dragged by touch
        XCTAssertTrue(poll(5) { (self.intensity.value as? String) == "100 percent" })
        XCTAssertTrue(poll(5) { self.undo.label == "Undo Glow Intensity 100%" }, "one step for the drag: \(undo.label)")

        // Undo: intensity back, then Glow off, then 64 bars.
        undo.tap()
        XCTAssertTrue(poll(5) { (self.intensity.value as? String) == "50 percent" }, "intensity restored")
        XCTAssertEqual(redo.label, "Redo Glow Intensity 100%")
        undo.tap()
        XCTAssertTrue(intensity.disappears(within: 5), "glow off again")
        XCTAssertFalse(isOn(glowToggle))
        undo.tap()
        XCTAssertTrue(poll(5) { self.bars.buttons["64"].isSelected }, "bars restored")

        // Redo: 16 bars, then Glow on.
        redo.tap()
        XCTAssertTrue(poll(5) { self.bars.buttons["16"].isSelected }, "bars redone")
        redo.tap()
        XCTAssertTrue(poll(5) { self.isOn(self.glowToggle) }, "glow redone")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertEqual(starts, "1", "undo and redo never restart the source")
    }
}
