// CueRehearsalUITests.swift — SHOW-006-T15 on the iOS Simulator (SHOW-006-S4, R1, R10): with the SHOW-001 DEBUG seed
// (`-uitestShowSeed`, five cues standing on cue 1), the cue row's Rehearse toggle shows the rehearsal panel naming the
// next cue ("Cue 2 · Build") while the show stays on cue 1; the panel stays when the controls hide; Close ends it.
// Simulator results are never device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class CueRehearsalUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }
    private var status: XCUIElement { app.staticTexts["showCueStatus"] }

    func testRehearsePreviewsTheNextCueWithoutMovingTheShow() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestShowSeed", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        if !controls.appears(within: 10) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        XCTAssertTrue(poll(3) { (self.status.value as? String)?.hasPrefix("Cue 1 of 5") == true })

        let rehearse = app.descendants(matching: .any)["showRehearse"].firstMatch
        XCTAssertTrue(rehearse.appears(within: 3), "the Rehearse toggle is in the cue row")
        XCTAssertEqual(rehearse.value as? String, "Off")
        rehearse.tap()
        let title = app.descendants(matching: .any)["cueRehearsalTitle"].firstMatch
        XCTAssertTrue(title.appears(within: 5), "the rehearsal panel shows")
        XCTAssertTrue(title.label.contains("Cue 2, Build"), "it names the next cue: \(title.label)")
        XCTAssertTrue(app.descendants(matching: .any)["cueRehearsalPicture"].firstMatch.exists, "with its picture")
        XCTAssertTrue((status.value as? String)?.hasPrefix("Cue 1 of 5") == true, "the show stays on cue 1")

        area.tap()   // hide the controls
        XCTAssertTrue(poll(5) { !self.controls.exists }, "the controls hide")
        XCTAssertTrue(title.exists, "R10: the panel stays without the controls")
        let close = app.buttons["cueRehearsalClose"]
        close.tap()
        XCTAssertTrue(poll(3) { !title.exists }, "Close ends rehearsal")
    }
}
