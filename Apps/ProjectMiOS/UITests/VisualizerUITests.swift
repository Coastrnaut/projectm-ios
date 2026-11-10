// Task T081: the visualizer's controls on the iOS Simulator with In-App Playback. A tap toggles
// the controls; they hide after 5 s while the compact source-and-state indicator stays (FR-042);
// rotation re-lays out within 1 s without restarting capture (FR-041); compact width uses the
// single-row layout (FR-087). Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class VisualizerUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// Fresh launch in portrait with the notice reset, then notice → chooser → In-App Playback.
    private func startInAppPlayback() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics"]
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10), "photosensitivity notice first (FR-071)")
        acknowledge.tap()
        let inApp = app.buttons["In-App Playback"]
        XCTAssertTrue(inApp.waitForExistence(timeout: 10))
        inApp.tap()
        XCTAssertTrue(app.otherElements["controls"].waitForExistence(timeout: 10), "controls shown on start")
    }

    private var controls: XCUIElement { app.otherElements["controls"] }
    private var indicator: XCUIElement { app.staticTexts["sourceIndicator"] }

    func testTapTogglesControls() {
        startInAppPlayback()
        app.otherElements["visualizerTapArea"].firstMatch.tap()
        XCTAssertTrue(controls.waitForNonExistence(timeout: 3), "a tap hides the controls")
        app.otherElements["visualizerTapArea"].firstMatch.tap()
        XCTAssertTrue(controls.waitForExistence(timeout: 3), "a second tap shows them")
    }

    func testControlsAutoHideAndTheIndicatorStays() {
        startInAppPlayback()
        XCTAssertTrue(controls.exists)
        XCTAssertTrue(controls.waitForNonExistence(timeout: 8), "controls hide after 5 s (FR-042)")
        XCTAssertTrue(indicator.exists, "the source-and-state indicator stays visible")
        XCTAssertTrue(indicator.label.hasPrefix("In-App Playback · "), indicator.label)
    }

    func testRotationRelaysOutWithoutRestartingCapture() {
        startInAppPlayback()
        let starts = app.staticTexts["sourceStarts"]
        XCTAssertTrue(starts.waitForExistence(timeout: 5))
        XCTAssertEqual(starts.value as? String, "1")
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.height, window.frame.width)
        let start = Date()
        XCUIDevice.shared.orientation = .landscapeLeft
        var elapsed = Double.infinity
        while Date().timeIntervalSince(start) < 5 {
            if window.frame.width > window.frame.height { elapsed = Date().timeIntervalSince(start); break }
        }
        // Includes the time XCUITest needs to query the layout, so this is an upper bound.
        print("VisualizerUITests: re-layout observed after \(String(format: "%.2f", elapsed)) s")
        XCTAssertLessThanOrEqual(elapsed, 1.0, "re-layout within 1 s (FR-041)")
        XCTAssertEqual(starts.value as? String, "1", "rotation did not restart capture")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(starts.value as? String, "1")
    }

    func testCompactWidthUsesTheSingleRowLayout() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("compact width: iPhone portrait (iPad split view is checked by hand)")
        }
        startInAppPlayback()
        let window = app.windows.firstMatch.frame
        var rows: [CGFloat] = []
        for id in ["stop", "pauseResume", "previous", "next", "random", "presets", "settings"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists && button.isHittable, "\(id) reachable in compact width (FR-087)")
            XCTAssertTrue(window.contains(button.frame), "\(id) inside the window")
            rows.append(button.frame.midY)
        }
        XCTAssertLessThan((rows.max() ?? 0) - (rows.min() ?? 0), 2, "one row of controls (FR-087)")
    }

    /// T082 (FR-081, FR-071, FR-005): first launch shows the notice, a second launch opens on the
    /// chooser, and Microphone shows its explainer before anything starts.
    func testFirstAndSecondLaunchAndTheMicrophoneExplainer() {
        app.launchArguments = ["-uitestResetNotice"]
        app.launch()
        XCTAssertTrue(app.buttons["acknowledgeNotice"].waitForExistence(timeout: 10), "notice on first launch")
        XCTAssertFalse(app.buttons["In-App Playback"].exists, "nothing else before the notice")
        app.buttons["acknowledgeNotice"].tap()
        XCTAssertTrue(app.buttons["In-App Playback"].waitForExistence(timeout: 10))
        app.terminate()

        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Microphone"].waitForExistence(timeout: 10), "second launch opens on the chooser")
        XCTAssertFalse(app.buttons["acknowledgeNotice"].exists, "the notice is shown once")
        XCTAssertFalse(app.otherElements["controls"].exists, "no source starts by itself (FR-002)")
        app.buttons["Microphone"].tap()
        let explainer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
                                                             "Microphone mode listens to sound in the room")).firstMatch
        XCTAssertTrue(explainer.waitForExistence(timeout: 5), "explainer before the permission prompt (FR-005)")
    }

    /// T090 (FR-043, FR-044, FR-088): alphabetical browser, favorites filter and empty state, a star
    /// adds a favorite, and choosing a preset closes the browser and shows its name.
    func testPresetBrowser() {
        startInAppPlayback()
        app.buttons["presets"].tap()
        let browser = app.navigationBars["Presets"]
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        let names = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).allElementsBoundByIndex
            .map { String($0.identifier.dropFirst("preset:".count)) }
        XCTAssertGreaterThanOrEqual(names.count, 2)
        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "alphabetical")

        app.segmentedControls.buttons["Favorites"].tap()
        XCTAssertTrue(app.staticTexts["No favorites yet — tap the star on a preset to add one."].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["All"].tap()
        let pick = names[1]
        app.buttons["star:\(pick)"].tap()
        app.segmentedControls.buttons["Favorites"].tap()
        XCTAssertTrue(app.buttons["preset:\(pick)"].waitForExistence(timeout: 3), "the starred preset is a favorite")
        app.buttons["preset:\(pick)"].tap()
        XCTAssertTrue(browser.waitForNonExistence(timeout: 3), "the browser closes on selection")
        let current = app.staticTexts["currentPreset"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        let shown = NSPredicate(format: "label == %@", pick)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: current)], timeout: 5), .completed)
    }

    func testPauseDimsAndLabels() {
        startInAppPlayback()
        app.buttons["pauseResume"].tap()
        XCTAssertTrue(app.staticTexts["pausedLabel"].waitForExistence(timeout: 3), "Paused label (FR-085)")
        app.buttons["pauseResume"].tap()
        XCTAssertTrue(app.staticTexts["pausedLabel"].waitForNonExistence(timeout: 3))
    }
}
