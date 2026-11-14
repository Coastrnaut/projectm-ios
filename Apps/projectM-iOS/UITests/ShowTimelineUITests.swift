// ShowTimelineUITests.swift — SHOW-007-T13 on the iOS Simulator (SHOW-007-S4): with the SHOW-001 DEBUG seed and
// `-uitestShowTimelineSeed` (five cues, 30 s each: a 2:30 timeline), the cue row shows the timeline transport; dragging
// the scrub slider to the middle moves the show to cue 3 on release, and Loop toggles On/Off. Simulator results are never
// device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class ShowTimelineUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }
    private var status: XCUIElement { app.staticTexts["showCueStatus"] }

    func testScrubbingTheTimelineMovesTheShowOnRelease() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestShowSeed", "-uitestShowTimelineSeed", "-autostart", "inAppPlayback"]
            + Self.noStore
        app.launch()
        if !controls.appears(within: 10) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")

        let scrub: XCUIElement = app.slider("showTimelineScrub")
        XCTAssertTrue(scrub.appears(within: 3), "the timeline transport is in the cue row")
        XCTAssertEqual(app.staticTexts["showTimelinePosition"].label, "0:00 / 2:30")
        XCTAssertTrue((status.value as? String)?.hasPrefix("Cue 1 of 5") == true)

        scrub.dragSlider(from: 0, to: 0.5)
        XCTAssertTrue(poll(3) { (self.status.value as? String)?.hasPrefix("Cue 3 of 5") == true },
                      "the release seeks once into cue 3: \(status.value as? String ?? "nil")")

        if !controls.exists { area.tap() }
        let loop = app.descendants(matching: .any)["showTimelineLoop"].firstMatch   // the toggle trait reports a switch
        XCTAssertTrue(loop.appears(within: 3))
        XCTAssertEqual(loop.value as? String, "Off")
        loop.tap()
        XCTAssertTrue(poll(3) { (loop.value as? String) == "On" }, "Loop on: \(loop.value as? String ?? "nil")")
    }
}
