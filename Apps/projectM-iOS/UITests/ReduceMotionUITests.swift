// ReduceMotionUITests.swift — ACC-001-T06 on the iOS Simulator (specs/080-acc-001-reduce-motion-mode;
// ACC-001-R2, R3, R5, R8, R9; S1, S2, S4). XCUITest cannot change the system Reduce Motion setting, so
// the Debug build takes `-uitestReduceMotion YES` as the starting state and a hidden button
// (`simulateReduceMotionToggle`) that changes it through the same handler as the system notification
// (contract C2). `motionProbe` reports the duration the last controls transition was given by the
// policy — a configured value, never a wall-clock measurement. Simulator results are never device
// evidence (Constitution X); the real toggle on D1 is ACC-001-T12.
import XCTest

@MainActor
final class ReduceMotionUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: String { (app.staticTexts["motionProbe"].value as? String) ?? "" }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }
    private var controls: XCUIElement { app.otherElements["controls"] }

    /// Taps the visualization once and waits until the controls' visibility flipped and the probe
    /// reports `expected` for that transition.
    private func toggleControls(expect expected: String, _ message: String) {
        let wasShown = controls.exists
        area.tap()
        XCTAssertTrue(poll(5) { self.controls.exists != wasShown }, "the controls toggled: \(message)")
        XCTAssertTrue(poll(5) { self.probe.hasSuffix("controls=\(expected)") }, "\(message): probe \(probe)")
    }

    /// Ends with the controls shown, the last transition reporting `expected`.
    private func showControls(expect expected: String, _ message: String) {
        if controls.exists { toggleControls(expect: expected, message) }
        toggleControls(expect: expected, message)
        XCTAssertTrue(controls.exists)
    }

    private func assertControlsLabelled(_ message: String) {
        for id in ["settings", "stop", "pauseResume"] { XCTAssertTrue(app.buttons[id].exists, "\(id): \(message) (R8)") }
    }

    func testReduceMotionMakesControlsInstantAndFollowsASystemChangeAtOnce() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestReduceMotion", "YES"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["motionProbe"].appears(within: 15))
        XCTAssertTrue(probe.hasPrefix("reduce=on"), probe)
        XCTAssertTrue(poll(10) { (self.app.staticTexts["visualRunning"].value as? String) == "yes" }, "the visualization draws (S4)")

        // US1: hide and show with Reduce Motion on → instant.
        showControls(expect: "0.00", "Reduce Motion on")
        assertControlsLabelled("Reduce Motion on")

        // Settings opens and closes as before (system sheet, R6).
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))

        // US2: the system setting turns off while running → the very next transition fades (0.2 s).
        app.buttons["simulateReduceMotionToggle"].tap()
        XCTAssertTrue(poll(3) { self.probe.hasPrefix("reduce=off") }, probe)
        toggleControls(expect: "0.20", "first transition after Reduce Motion turned off")
        showControls(expect: "0.20", "Reduce Motion off")
        assertControlsLabelled("Reduce Motion off")

        // And back on → the next transition is instant again.
        app.buttons["simulateReduceMotionToggle"].tap()
        XCTAssertTrue(poll(3) { self.probe.hasPrefix("reduce=on") }, probe)
        toggleControls(expect: "0.00", "first transition after Reduce Motion turned on")
        XCTAssertEqual(app.staticTexts["visualRunning"].value as? String, "yes", "the visualization keeps drawing (R5, S4)")
    }
}
