// ShowKeyframeUITests.swift — SHOW-008-T11 on the iOS Simulator (SHOW-008-S5; contract K7): with the SHOW-001 DEBUG seed and
// `-uitestShowTimelineSeed` (five cues, 30 s each), Settings → Show → Keyframe Tracks: Add Track… → Glow Intensity, then
// Add Keyframe at Playhead lists a keyframe row ("0:04.250, 0.70, Linear"). Simulator results are never device evidence.
// Owner rule 7: under 30 s.
import XCTest

@MainActor
final class ShowKeyframeUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }

    func testAddingATrackAndAKeyframeAtThePlayhead() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestShowSeed", "-uitestShowTimelineSeed", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "show"] + Self.noStore
        app.launch()
        if !controls.appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        let editor = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(editor), "the Show row is reachable")
        editor.tap()
        let link = app.buttons["showKeyframeTracksLink"]
        XCTAssertTrue(link.appears(within: 5), "Keyframe Tracks is offered")
        link.tap()
        XCTAssertTrue(app.staticTexts["showKeyframePlayhead"].appears(within: 3), "the playhead is shown")

        app.buttons["showKeyframeAddTrack"].tap()
        let glow = app.buttons["Glow Intensity"].firstMatch
        XCTAssertTrue(glow.appears(within: 3), "Glow Intensity is offered")
        glow.tap()
        let add = app.buttons["showKeyframeAddKey"]
        XCTAssertTrue(add.appears(within: 3), "the track has Add Keyframe at Playhead")
        add.tap()

        let row = app.buttons["showKeyframeRow"].firstMatch
        XCTAssertTrue(row.appears(within: 3), "a keyframe row is listed")
        XCTAssertTrue(row.label.hasSuffix(", Linear") && row.label.hasPrefix("0:"), "row reads \(row.label)")
    }
}
