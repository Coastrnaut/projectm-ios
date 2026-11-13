// ShowCueUITests.swift — SHOW-001-T13, T17 on the iOS Simulator (SHOW-001-S4, S5): with the DEBUG
// seed (`-uitestShowSeed`: five cues over five distinct scenes, standing on cue 1), Next four times
// shows cues 2…5 (label and the applied-scene probe), Next at the end does nothing, Previous returns
// to cue 4, the audio source was started once; while blacked out the Right Arrow key steps to cue 5
// and the output stays black. Simulator results are never device evidence. Owner rule 7: under 30 s;
// UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class ShowCueUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static let labels = ["Opening", "Build", "Drop", "Break", "Finale"]
    private static let visuals = ["circularSpectrum", "linearSpectrum", "circularSpectrum", "linearSpectrum", "text"]
    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }
    private var applied: String? { app.staticTexts["showAppliedScene"].value as? String }
    private var output: String? { app.staticTexts["outputBlackout"].value as? String }
    private var status: XCUIElement { app.staticTexts["showCueStatus"] }
    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    /// The probe's applied scene and visual; with `row`, first the row's VoiceOver value (read right
    /// after a tap on the row, which restarts the controls' 5 s hide delay).
    private func expectCue(_ n: Int, row: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        if row {
            let value = "Cue \(n) of 5, \(Self.labels[n - 1])"
            XCTAssertTrue(poll(2) { self.status.exists && (self.status.value as? String) == value }, "row shows cue \(n)",
                          file: file, line: line)
        }
        let expected = "\(Self.sceneID(n))|\(Self.visuals[n - 1])"
        XCTAssertTrue(poll(3) { self.applied == expected }, "cue \(n) applied: \(applied ?? "nil")", file: file, line: line)
    }

    private func showControls() {
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
    }

    func testFiveCuesStepDeterministicallyWithoutRestartingTheSource() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-autostart", "inAppPlayback"]
            + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        expectCue(1)
        showControls()
        XCTAssertTrue(status.appears(within: 3))
        XCTAssertEqual(status.label, "Show")
        XCTAssertEqual(status.value as? String, "Cue 1 of 5, Opening", "VoiceOver reads the position and label")
        let next = app.buttons["showNextCue"]
        let previous = app.buttons["showPreviousCue"]
        XCTAssertFalse(previous.isEnabled, "Previous is unavailable on cue 1")

        for n in 2...5 {
            showControls()   // the controls hide after 5 s; a step's tap restarts that delay
            next.tap()
            expectCue(n, row: true)
        }
        showControls()
        XCTAssertFalse(next.isEnabled, "the show stops at its end (no wrap)")
        previous.tap()
        expectCue(4, row: true)
        XCTAssertEqual(starts, "1", "the audio source was never restarted")

        // SHOW-001-R10, R15: black out (B), step with the Right Arrow key: the output stays black.
        app.typeKey("b", modifierFlags: [])
        XCTAssertTrue(poll(2) { self.output == "black" }, "blacked out")
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        expectCue(5)
        XCTAssertEqual(output, "black", "stepping keeps the output black")
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: [])
        expectCue(4)
        XCTAssertEqual(starts, "1")
    }

    /// SHOW-001-T15 (US2): Settings → Show → Add Current Scene twice, then the controls show the show
    /// row at Standby and Next applies cue 1. Under 30 s: no visual change, one scroll.
    func testTheEditorAddsTheCurrentSceneAsCues() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        XCTAssertFalse(status.exists, "no show row without cues")
        app.buttons["settings"].tap()
        let link = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(link), "the Show row is reachable")
        link.tap()
        let add = app.buttons["showAddCurrentScene"]
        XCTAssertTrue(add.appears(within: 5))
        add.tap()
        add.tap()
        let second = app.descendants(matching: .any)["showCue2"]
        XCTAssertTrue(second.appears(within: 3))
        XCTAssertEqual(second.label, "projectM", "labelled after the visual")
        XCTAssertEqual(second.value as? String, "Cue 2 of 2")
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to Settings
        app.navigationBars["Settings"].buttons["Done"].tap()

        showControls()
        XCTAssertTrue(status.appears(within: 3))
        XCTAssertEqual(status.value as? String, "Standby, 2 cues")
        app.buttons["showNextCue"].tap()
        XCTAssertTrue(poll(3) { (self.status.value as? String) == "Cue 1 of 2, projectM" })
        XCTAssertTrue(poll(3) { self.applied?.hasSuffix("|projectM") == true && self.applied?.hasPrefix("none") == false },
                      "cue 1's scene is applied")
        XCTAssertEqual(starts, "1")
    }
}
