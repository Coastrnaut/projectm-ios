// CueHoldSkipUITests.swift — SHOW-005-T14 on the iOS Simulator (SHOW-005-S5): with the SHOW-001 DEBUG seed
// (`-uitestShowSeed`, five cues), the cue row's Hold toggle turns on and off (VoiceOver value On/Off) while Next still
// moves; in Settings → Show, cue 3's trailing "Skip" swipe action makes its row read ", skipped". Simulator results are never
// device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class CueHoldSkipUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }
    private var status: XCUIElement { app.staticTexts["showCueStatus"] }

    func testHoldTogglesAndSkipMarksACue() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestShowSeed", "-autostart", "inAppPlayback", "-uitestSettingsSection", "show"]
            + Self.noStore
        app.launch()
        if !controls.appears(within: 10) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")

        let hold = app.descendants(matching: .any)["showHold"].firstMatch   // the toggle trait reports a switch
        XCTAssertTrue(hold.appears(within: 3), "the Hold toggle is in the cue row")
        XCTAssertEqual(hold.value as? String, "Off")
        hold.tap()
        XCTAssertTrue(poll(3) { (hold.value as? String) == "On" }, "Hold on: \(hold.value as? String ?? "nil")")
        app.buttons["showNextCue"].tap()
        XCTAssertTrue(poll(3) { (self.status.value as? String)?.hasPrefix("Cue 2 of 5") == true },
                      "Next moves while held: \(status.value as? String ?? "nil")")
        hold.tap()
        XCTAssertTrue(poll(3) { (hold.value as? String) == "Off" }, "Hold off")

        if !app.buttons["settings"].exists { area.tap() }
        app.buttons["settings"].tap()
        let link = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(link), "the Show row is reachable")
        link.tap()
        let third = app.descendants(matching: .any)["showCue3"]
        XCTAssertTrue(third.appears(within: 5))
        XCTAssertFalse((third.value as? String ?? "").contains("skipped"))
        // A short trailing drag (a full swipe would delete); the context menu over the live visualizer is slow to settle.
        let start = third.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: third.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let skip = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "showCueSkip", "Skip Cue")).firstMatch
        XCTAssertTrue(skip.appears(within: 5), "Skip Cue is offered")
        skip.tap()
        XCTAssertTrue(poll(3) { (third.value as? String)?.hasSuffix(", skipped") == true }, "skipped: \(third.value ?? "nil")")
    }
}
