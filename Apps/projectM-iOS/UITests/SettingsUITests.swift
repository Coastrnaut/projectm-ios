// Task T103: the three settings on the iOS Simulator. The performance overlay is off by default and
// shows the frame rate and audio state when turned on (FR-048); Reduce flashing follows Reduce
// Motion (off on the simulator) until changed, and the choice persists (FR-072); the Licenses screen
// lists the components with their texts and the LGPL source and replacement note (FR-067).
// Simulator results are never device evidence.
// Shortened 2026-11-13 under owner rule 7: `-autostart inAppPlayback` replaces the notice and chooser
// taps, waits poll every 0.1 s (UITestWaits.swift), and the Licenses test is split in two (it took
// 67 s as one test).
import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics", "-autostart", "inAppPlayback"]
            + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    /// Shows the controls with a fresh 5 s auto-hide, then opens Settings (see NativeVisualUITests).
    private func openSettings() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
    }

    private func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? String) == "1"
    }

    /// The SwiftUI switch inside a Toggle row.
    private func flip(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    private var overlayElement: XCUIElement { app.descendants(matching: .any)["performanceOverlay"].firstMatch }

    func testPerformanceOverlay() {
        launch(reset: true)
        XCTAssertFalse(overlayElement.exists, "off by default (FR-048)")
        openSettings()
        let toggle = app.switches["performanceOverlayToggle"]
        XCTAssertTrue(toggle.appears(within: 5))
        XCTAssertFalse(isOn(toggle))
        flip(toggle)
        XCTAssertTrue(isOn(toggle))
        closeSettings()
        let overlay = overlayElement
        XCTAssertTrue(overlay.appears(within: 5))
        XCTAssertTrue(poll(5) { overlay.label.contains("fps") && overlay.label.contains("audio:") },
                      "frame rate and audio state: \(overlay.label)")
    }

    func testReduceFlashingFollowsReduceMotionAndPersists() {
        launch(reset: true)
        openSettings()
        let toggle = app.switches["reduceFlashingToggle"]
        XCTAssertTrue(toggle.appears(within: 5))
        XCTAssertFalse(isOn(toggle), "Reduce Motion is off on the simulator, so Reduce flashing starts off")
        XCTAssertFalse(app.buttons["reduceFlashingFollowSystem"].exists)
        flip(toggle)
        XCTAssertTrue(isOn(toggle))
        XCTAssertTrue(app.buttons["reduceFlashingFollowSystem"].appears(within: 3))

        app.terminate()
        launch(reset: false)
        openSettings()
        XCTAssertTrue(app.switches["reduceFlashingToggle"].appears(within: 5))
        XCTAssertTrue(isOn(app.switches["reduceFlashingToggle"]), "the choice persists")
        app.buttons["reduceFlashingFollowSystem"].tap()
        XCTAssertFalse(isOn(app.switches["reduceFlashingToggle"]), "back to following Reduce Motion")
    }

    func testLicensesScreen() {
        launch(reset: true)
        openSettings()
        app.buttons["licensesLink"].tap()
        XCTAssertTrue(app.navigationBars["Licenses"].appears(within: 5))
        for id in ["lgplNote", "license:app", "license:projectm", "license:glm", "license:angle-ANGLE", "license:presets"] {
            let row = app.buttons[id]
            XCTAssertTrue(row.exists || scrollTo(row), id)
        }
        scrollTo(app.buttons["lgplNote"], down: true)   // back to the top: no row under the bar
        app.buttons["license:projectm"].tap()
        let text = app.staticTexts["licenseText"]
        XCTAssertTrue(text.appears(within: 5))
        XCTAssertTrue(text.label.contains("GNU LESSER GENERAL PUBLIC LICENSE"))
        app.navigationBars.buttons["Licenses"].tap()
        XCTAssertTrue(app.navigationBars["Licenses"].appears(within: 5))
        let note = app.buttons["lgplNote"]
        scrollTo(note, down: true)
        note.tap()
        XCTAssertTrue(app.staticTexts["licenseText"].appears(within: 5))
        XCTAssertTrue(app.staticTexts["licenseText"].label.contains("Corresponding source"))
    }

    /// Feature 002 T235 (FR-121): each preset pack has an entry with its source, commit and authors.
    func testLicensesListEveryPresetPack() {
        launch(reset: true)
        openSettings()
        app.buttons["licensesLink"].tap()
        XCTAssertTrue(app.navigationBars["Licenses"].appears(within: 5))
        for pack in ["cream-of-the-crop", "projectm-classic", "milkdrop-original", "en-d", "milkdrop-texture-pack"] {
            XCTAssertTrue(scrollTo(app.buttons["license:pack-\(pack)"]), pack)
        }
        let cream = app.buttons["license:pack-cream-of-the-crop"]
        scrollTo(cream, down: true)
        cream.tap()
        let packText = app.staticTexts["licenseText"]
        XCTAssertTrue(packText.appears(within: 5))
        XCTAssertTrue(packText.label.contains("presets-cream-of-the-crop at commit 0180df2"), "source and pinned commit")
        XCTAssertTrue(packText.label.contains("Authors"), "author list")
    }

    /// Scrolls until `element` is hittable, at most 8 drags. Each drag holds at its end, so the list
    /// stops at once: a swipe flings, and XCUITest then waits about 5 s for the list to settle.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, down: Bool = false) -> Bool {
        let window = app.windows.firstMatch
        let top = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            let (from, to) = down ? (top, bottom) : (bottom, top)
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.1)
        }
        return element.exists
    }
}
