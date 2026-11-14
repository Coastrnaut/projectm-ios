// ShowAutoAdvanceUITests.swift — SHOW-002-T13 on the iOS Simulator (SHOW-002-S6): with the DEBUG seed
// (`-uitestShowSeed -uitestShowDwellSeed`: five cues on cue 1, cue 2 with a 2 s dwell), Next shows cue 2 with the
// countdown in the row's VoiceOver value, and cue 3 then becomes active by itself (its scene applied) without a tap.
// Cue 3 has no dwell, so nothing else moves. Simulator results are never device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class ShowAutoAdvanceUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var applied: String? { app.staticTexts["showAppliedScene"].value as? String }
    private var status: XCUIElement { app.staticTexts["showCueStatus"] }
    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }
    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    func testACueWithADwellAdvancesByItself() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-uitestShowDwellSeed",
                               "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
        XCTAssertEqual(status.value as? String, "Cue 1 of 5, Opening", "cue 1 has no dwell: no countdown")
        app.buttons["showNextCue"].tap()
        XCTAssertTrue(poll(2) { (self.status.value as? String)?.hasPrefix("Cue 2 of 5, Build, next cue in ") == true },
                      "the row reads the countdown: \(status.value as? String ?? "nil")")
        XCTAssertTrue(poll(6) { self.applied?.hasPrefix(Self.sceneID(3)) == true },
                      "cue 3 applied by the timed advance: \(applied ?? "nil")")
        if !controls.exists { area.tap() }
        XCTAssertTrue(poll(3) { (self.status.value as? String) == "Cue 3 of 5, Drop" }, "cue 3 active, no countdown")
    }
}
