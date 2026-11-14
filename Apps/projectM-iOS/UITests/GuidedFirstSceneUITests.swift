// GuidedFirstSceneUITests.swift — UIX-001-T07, T08, T10 on the iOS Simulator: the roadmap acceptance
// "New user can finish with no account or network access" (UIX-001-S1 to S4, S6). A fresh install
// (`-uitestResetNotice`) with `-uitestGuidedFirstScene` (the tutorial is otherwise suppressed in UI-test
// launches, UIX-001-R13) acknowledges the notice and meets the tutorial. "No network" is shown by what
// the app can reach: it has no networking code besides StoreKit (a fixed fake here, `-uitestUnlocked NO`)
// and the OSC receiver, whose listener the `sessionRecovery` probe reports off; no system alert
// (permission, sign-in) appears. Simulator results are never device evidence: the D1 Airplane Mode and
// VoiceOver pass is UIX-001-T14. Budget: under 30 s per test (owner rule 7).
import XCTest

@MainActor
final class GuidedFirstSceneUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool, extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics", "-uitestGuidedFirstScene"]
            + extra + Self.noStore
        app.launch()
    }

    private func acknowledgeNotice() {
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.appears(within: 15), "photosensitivity notice first (FR-071)")
        acknowledge.tap()
    }

    private var guide: XCUIElement { app.descendants(matching: .any)["guidedFirstScene"].firstMatch }
    private var next: XCUIElement { app.buttons["guide.next"] }
    private func stepTitle(_ name: String) -> XCUIElement { app.staticTexts["guide.step.\(name)"] }
    private func probe(_ id: String) -> String { app.staticTexts[id].value as? String ?? "" }
    /// The tutorial itself is modal, so XCUITest lists it as an alert; every other alert counts.
    private var otherAppAlerts: XCUIElementQuery { app.alerts.matching(NSPredicate(format: "identifier != %@", "guidedFirstScene")) }
    private var noSystemAlert: Bool { !springboard.alerts.firstMatch.exists && !otherAppAlerts.firstMatch.exists }
    private var alertLabels: String {
        (springboard.alerts.allElementsBoundByIndex + otherAppAlerts.allElementsBoundByIndex).map { (alert: XCUIElement) -> String in
            alert.label + " | " + alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " / ")
        }.joined(separator: "; ")
    }

    /// Taps Next (or Play) after checking the step's title.
    private func advance(from step: String) {
        XCTAssertTrue(stepTitle(step).appears(within: 5), "step \(step) is shown")
        XCTAssertTrue(app.reveal(next), "the primary button of \(step) is reachable")
        next.tap()
    }

    func testNewUserFinishesOfflineAndTheSceneIsKept() {
        launch(reset: true)
        acknowledgeNotice()
        XCTAssertTrue(guide.appears(within: 5), "the tutorial follows the notice on a new install")
        advance(from: "welcome")
        advance(from: "sound")
        XCTAssertTrue(stepTitle("visual").appears(within: 5))
        let circular = app.buttons["guide.visual.circularSpectrum"]
        XCTAssertTrue(circular.isSelected, "Circular Spectrum is preselected")
        circular.tap()
        advance(from: "visual")
        XCTAssertTrue(stepTitle("look").appears(within: 5))
        let glow = app.switches["guide.glow"]
        XCTAssertTrue(glow.exists)
        XCTAssertEqual(glow.value as? String, "1", "glow is preselected on")
        advance(from: "look")
        XCTAssertTrue(stepTitle("play").appears(within: 5))
        XCTAssertEqual(next.label, "Play")
        XCTAssertTrue(noSystemAlert, "no permission or sign-in prompt during the tutorial: \(alertLabels)")
        next.tap()

        // The scene plays: one source start (the built-in track), the visual draws, the scene is committed.
        XCTAssertTrue(guide.disappears(within: 5))
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 10))
        XCTAssertEqual(probe("sourceStarts"), "1")
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 10))
        XCTAssertTrue(poll(10) { self.probe("visualRunning") == "yes" }, "the visual draws frames")
        XCTAssertTrue(poll(10) { self.probe("sceneAutosave").contains("pending=0") && !self.probe("sceneAutosave").contains("committed=0") },
                      "the scene is committed: \(probe("sceneAutosave"))")
        XCTAssertTrue(probe("sessionRecovery").hasSuffix("osc=off"), "no network listener: \(probe("sessionRecovery"))")
        XCTAssertTrue(noSystemAlert, "no permission or sign-in prompt after Play: \(alertLabels)")

        // Relaunch: no tutorial, and the committed scene is restored.
        app.terminate()
        launch(reset: false)
        let inApp = app.buttons["In-App Playback"]
        XCTAssertTrue(inApp.appears(within: 15), "the chooser")
        XCTAssertFalse(guide.exists, "the tutorial is not shown again")
        inApp.tap()
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 10), "the scene is restored")
        XCTAssertTrue(poll(10) { self.probe("sceneAutosave").hasPrefix("restored=main") }, "from the committed file: \(probe("sceneAutosave"))")
    }

    func testSkipChangesNothingAndNeverReturns() {
        launch(reset: true)
        acknowledgeNotice()
        advance(from: "welcome")
        XCTAssertTrue(stepTitle("sound").appears(within: 5))
        XCTAssertTrue(app.buttons["guide.back"].exists, "Back from step 2")
        let skip = app.buttons["guide.skip"]
        XCTAssertTrue(app.reveal(skip))
        skip.tap()
        XCTAssertTrue(guide.disappears(within: 5))
        XCTAssertTrue(app.buttons["In-App Playback"].appears(within: 5), "back on the chooser")
        XCTAssertFalse(app.staticTexts["sourceStarts"].exists, "nothing started")

        app.terminate()
        launch(reset: false)
        XCTAssertTrue(app.buttons["In-App Playback"].appears(within: 15))
        XCTAssertFalse(guide.exists, "a skipped tutorial never returns by itself")
    }

    func testEveryPrimaryButtonIsReachableAtTheLargestTextSize() {
        launch(reset: true, extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        acknowledgeNotice()
        XCTAssertTrue(guide.appears(within: 5))
        for step in ["welcome", "sound", "visual", "look"] {
            advance(from: step)
        }
        XCTAssertTrue(stepTitle("play").appears(within: 5))
        XCTAssertTrue(app.reveal(next), "Play is reachable")
        XCTAssertTrue(next.isHittable, "Play is hittable")
        let skip = app.buttons["guide.skip"]
        XCTAssertTrue(app.reveal(skip), "Skip is reachable")
        XCTAssertTrue(skip.isHittable)
    }

    /// UIX-001-T09: Settings › Guided first scene over the running visualizer applies the new visual
    /// and keeps the running source (no second start).
    func testReopenFromSettingsKeepsTheRunningSource() {
        launch(reset: true, extra: ["-autostart", "inAppPlayback", "-uitestSettingsSection", "guide"])   // Settings opens at the guide row (owner rule 7)
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertFalse(guide.exists, "not offered by itself (the notice was skipped by -autostart)")
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["guidedFirstSceneButton"]
        XCTAssertTrue(app.reveal(row), "the Settings row")
        row.tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5), "Settings closes")
        XCTAssertTrue(guide.appears(within: 5))
        advance(from: "welcome")
        advance(from: "sound")
        XCTAssertTrue(stepTitle("visual").appears(within: 5))
        app.buttons["guide.visual.linearSpectrum"].tap()
        XCTAssertTrue(app.buttons["guide.visual.linearSpectrum"].isSelected)
        advance(from: "visual")
        advance(from: "look")
        advance(from: "play")
        XCTAssertTrue(guide.disappears(within: 5))
        XCTAssertTrue(app.descendants(matching: .any)["linearSpectrum"].firstMatch.appears(within: 10), "the new visual")
        XCTAssertEqual(probe("sourceStarts"), "1", "the running source was not restarted")
    }
}
