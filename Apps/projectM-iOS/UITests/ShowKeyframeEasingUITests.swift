// ShowKeyframeEasingUITests.swift — SHOW-009-T10 on the iOS Simulator (SHOW-009-S5; contract E8): with the SHOW-001 DEBUG
// seed and `-uitestShowTimelineSeed`, Settings → Show → Keyframe Tracks: add a Glow Intensity track and a keyframe, open
// it, pick Cubic (its description is shown), go back, and the row reads "…, Cubic". Simulator results are never device
// evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class ShowKeyframeEasingUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }

    func testChoosingCubicForAKeyframe() {
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

        app.buttons["showKeyframeAddTrack"].tap()
        let glow = app.buttons["Glow Intensity"].firstMatch
        XCTAssertTrue(glow.appears(within: 3), "Glow Intensity is offered")
        glow.tap()
        let add = app.buttons["showKeyframeAddKey"]
        XCTAssertTrue(add.appears(within: 3), "the track has Add Keyframe at Playhead")
        add.tap()
        let row = app.buttons["showKeyframeRow"].firstMatch
        XCTAssertTrue(row.appears(within: 3), "a keyframe row is listed")
        row.tap()

        let cubic = app.buttons["Cubic"].firstMatch
        XCTAssertTrue(cubic.appears(within: 3), "the picker offers Cubic")
        for name in ["Linear", "Stepped", "Hold", "Ease"] { XCTAssertTrue(app.buttons[name].firstMatch.exists, "the picker offers \(name)") }
        cubic.tap()
        XCTAssertTrue(app.staticTexts["Flows smoothly through Cubic keyframes without overshooting."].appears(within: 3),
                      "the chosen mode is described")
        app.navigationBars.buttons.firstMatch.tap()
        let updated = app.buttons["showKeyframeRow"].firstMatch
        XCTAssertTrue(updated.appears(within: 3), "back on the track list")
        XCTAssertTrue(updated.label.hasSuffix(", Cubic"), "row reads \(updated.label)")
    }
}
