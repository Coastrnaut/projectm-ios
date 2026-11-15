// SceneRotationUITests.swift — SHOW-013-T09 on the iOS Simulator (SHOW-013-S4): with the DEBUG seed (`-uitestShowSeed`:
// five cues on cue 1) and `-uitestSceneRotation 2` (rotation on at launch, 2 s timer, seed 1), the applied scene changes by
// itself twice, never to the scene already shown; Settings shows Rotate scenes on with its status line.
// Simulator results are never device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class SceneRotationUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var applied: String { (app.staticTexts["showAppliedScene"].value as? String) ?? "" }
    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    /// The scene ID part of the probe ("<sceneID>…").
    private func scene(_ text: String) -> String { String(text.prefix(36)) }

    func testRotationSwitchesScenesByItself() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestSceneRotation", "2", "-uitestSettingsSection", "sceneRotation"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let first: String = scene(applied)
        XCTAssertTrue(poll(6) { !self.applied.isEmpty && self.scene(self.applied) != first },
                      "rotation switched the scene: \(first) → \(applied)")
        let second: String = scene(applied)
        XCTAssertTrue(poll(6) { self.scene(self.applied) != second }, "and again: \(second) → \(applied)")
        XCTAssertNotEqual(scene(applied), second, "never the scene already shown")

        if !app.buttons["settings"].exists { area.tap() }
        app.buttons["settings"].tap()
        let toggle = app.switches["sceneRotation.toggle"].firstMatch
        XCTAssertTrue(toggle.appears(within: 5) || app.reveal(toggle), "the Rotate scenes row is shown")
        XCTAssertEqual(toggle.value as? String, "1", "rotation is on")
        let status = app.descendants(matching: .any).matching(identifier: "sceneRotation.status").firstMatch
        XCTAssertTrue(status.exists, "the status line is shown")
    }
}
