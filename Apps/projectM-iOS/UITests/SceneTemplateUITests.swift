// SceneTemplateUITests.swift — SCN-011-T08 on the iOS Simulator (SCN-011-S5; contract T5): with the SHOW-001
// DEBUG seed (`-uitestShowSeed`: five cues, standing on cue 1), Settings → Show → Add from Template… opens the
// gallery; choosing Pulse Rings closes it and appends cue 6 "Pulse Rings" while the show stays on cue 1 (adding
// applies nothing). Simulator results are never device evidence. Owner rule 7: under 30 s; UITestWaits' 0.1 s
// polling.
import XCTest

@MainActor
final class SceneTemplateUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }

    func testAddATemplateAndItsCueAppears() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "show"]   // Settings opens at the Show row (owner rule 7)
            + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))

        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
        app.buttons["settings"].tap()
        let link = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(link), "the Show row is reachable")
        link.tap()

        let add = app.buttons["showAddFromTemplate"]
        XCTAssertTrue(add.appears(within: 5), "Add from Template… is offered")
        add.tap()
        let pulse = app.buttons["sceneTemplate.pulse-rings"]
        XCTAssertTrue(pulse.appears(within: 5), "the gallery lists Pulse Rings")
        XCTAssertTrue(pulse.label.hasPrefix("Pulse Rings, "), "VoiceOver reads the name and description: \(pulse.label)")
        XCTAssertTrue(app.buttons["sceneTemplate.show-starter"].exists)
        pulse.tap()
        XCTAssertTrue(pulse.disappears(within: 3), "choosing a template closes the gallery")

        let cue = app.descendants(matching: .any)["showCue6"]
        XCTAssertTrue(app.reveal(cue), "the new cue is listed")
        XCTAssertEqual(cue.label, "Pulse Rings")
        XCTAssertEqual(cue.value as? String, "Cue 6 of 6", "appended, not active: adding applies nothing")
        let first = app.descendants(matching: .any)["showCue1"]
        XCTAssertTrue(app.reveal(first, down: true))
        XCTAssertEqual(first.value as? String, "Cue 1 of 6, active", "the show stays on cue 1")
    }
}
