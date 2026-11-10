// Task T103: the three settings on the iOS Simulator. The performance overlay is off by default and
// shows the frame rate and audio state when turned on (FR-048); Reduce flashing follows Reduce
// Motion (off on the simulator) until changed, and the choice persists (FR-072); the Licenses screen
// lists the components with their texts and the LGPL source and replacement note (FR-067).
// Simulator results are never device evidence.
import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + Self.noStore
        app.launch()
        if reset {
            let acknowledge = app.buttons["acknowledgeNotice"]
            XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
            acknowledge.tap()
        }
        let inApp = app.buttons["In-App Playback"]
        XCTAssertTrue(inApp.waitForExistence(timeout: 10))
        inApp.tap()
    }

    private func openSettings() {
        let controls = app.otherElements["controls"]
        if !controls.waitForExistence(timeout: 2) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(isOn(toggle))
        flip(toggle)
        XCTAssertTrue(isOn(toggle))
        closeSettings()
        let overlay = overlayElement
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        let shows = NSPredicate(format: "label CONTAINS 'fps' AND label CONTAINS 'audio:'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shows, object: overlay)], timeout: 5),
                       .completed, "frame rate and audio state: \(overlay.label)")
    }

    func testReduceFlashingFollowsReduceMotionAndPersists() {
        launch(reset: true)
        openSettings()
        let toggle = app.switches["reduceFlashingToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(isOn(toggle), "Reduce Motion is off on the simulator, so Reduce flashing starts off")
        XCTAssertFalse(app.buttons["reduceFlashingFollowSystem"].exists)
        flip(toggle)
        XCTAssertTrue(isOn(toggle))
        XCTAssertTrue(app.buttons["reduceFlashingFollowSystem"].waitForExistence(timeout: 3))

        app.terminate()
        launch(reset: false)
        openSettings()
        XCTAssertTrue(app.switches["reduceFlashingToggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(isOn(app.switches["reduceFlashingToggle"]), "the choice persists")
        app.buttons["reduceFlashingFollowSystem"].tap()
        XCTAssertFalse(isOn(app.switches["reduceFlashingToggle"]), "back to following Reduce Motion")
    }

    func testLicensesScreen() {
        launch(reset: true)
        openSettings()
        app.buttons["licensesLink"].tap()
        XCTAssertTrue(app.navigationBars["Licenses"].waitForExistence(timeout: 5))
        for id in ["lgplNote", "license:app", "license:projectm", "license:glm", "license:angle-ANGLE", "license:presets"] {
            let row = app.buttons[id]
            XCTAssertTrue(row.waitForExistence(timeout: 3) || scrollTo(row), id)
        }
        for _ in 0..<8 where !app.buttons["license:projectm"].isHittable { app.swipeDown() }
        app.buttons["license:projectm"].tap()
        let text = app.staticTexts["licenseText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("GNU LESSER GENERAL PUBLIC LICENSE"))
        app.navigationBars.buttons["Licenses"].tap()
        XCTAssertTrue(app.navigationBars["Licenses"].waitForExistence(timeout: 5))
        let note = app.buttons["lgplNote"]
        for _ in 0..<8 where !note.waitForExistence(timeout: 1) { app.swipeDown() }
        note.tap()
        XCTAssertTrue(app.staticTexts["licenseText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["licenseText"].label.contains("Corresponding source"))

        // Feature 002 T235 (FR-121): each preset pack has an entry with its source, commit and authors.
        app.navigationBars.buttons["Licenses"].tap()
        XCTAssertTrue(app.navigationBars["Licenses"].waitForExistence(timeout: 5))
        for pack in ["cream-of-the-crop", "projectm-classic", "milkdrop-original", "en-d", "milkdrop-texture-pack"] {
            XCTAssertTrue(scrollTo(app.buttons["license:pack-\(pack)"]), pack)
        }
        let cream = app.buttons["license:pack-cream-of-the-crop"]
        for _ in 0..<8 where !cream.isHittable { app.swipeDown() }
        cream.tap()
        let packText = app.staticTexts["licenseText"]
        XCTAssertTrue(packText.waitForExistence(timeout: 5))
        XCTAssertTrue(packText.label.contains("presets-cream-of-the-crop at commit 0180df2"), "source and pinned commit")
        XCTAssertTrue(packText.label.contains("Authors"), "author list")
    }

    private func scrollTo(_ element: XCUIElement) -> Bool {
        for _ in 0..<8 where !element.exists { app.swipeUp() }
        return element.exists
    }
}
