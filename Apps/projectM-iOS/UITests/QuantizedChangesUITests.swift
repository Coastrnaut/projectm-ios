// QuantizedChangesUITests.swift — MOD-017-T10 (US3; R9; S5) on the iOS Simulator: with Quantize changes set to Cue
// and a five-cue show, turning the glow on in the parameter inspector shows "Queued for the next cue" under the
// switch, and turning it back off cancels it. The mode comes from the launch arguments' defaults domain
// (`-settings.modulation.quantize cue`). Under 30 s (owner rule 7). Simulator results are UI evidence only.
import XCTest

@MainActor
final class QuantizedChangesUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var inspector: XCUIElement { app.collectionViews["parameterInspector"].firstMatch }
    private func element(_ id: String) -> XCUIElement { inspector.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testQueuedIndicationAppearsAndCancels() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback", "-uitestShowSeed",
                               "-settings.modulation.quantize", "cue", "-uitestInspectParameter", "effect.bloom.enabled"]
        app.launch()
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        let toggle = element("parameterInspector.toggle")
        XCTAssertTrue(toggle.appears(within: 5), "the inspector opens on the glow switch")
        let queued = element("quantize.queued.effect.bloom.enabled")
        XCTAssertFalse(queued.exists, "nothing queued at launch")

        flip(toggle)
        XCTAssertTrue(queued.appears(within: 5), "the change waits for the next cue")
        XCTAssertEqual(queued.label, "Queued for the next cue")

        flip(toggle)
        XCTAssertTrue(poll(5) { !queued.exists }, "setting it back cancels the queued change")
    }

    private func flip(_ toggle: XCUIElement) {
        let control: XCUIElement = toggle.switches.firstMatch
        if control.exists { control.tap() } else { toggle.tap() }
    }
}
