// SceneHUDUITests.swift — UIX-013-T08, T11 on the iOS Simulator (specs/233-uix-013-performance-hud; S3, S4, C2, C3).
// With the DEBUG show seed (`-uitestShowSeed`: five cues, standing on cue 1) and the HUD preference on through the
// argument domain (`-settings.visualizer.sceneHUD YES`):
// - portrait with the performance layout: the four lines read cue 1, "Next: Build", the tempo with its source and
//   the source; the HUD lies inside the safe area, clear of the screen's centre and the pad's targets; Next and four
//   taps update it ("Cue 2 of 5", "120 BPM · Tap");
// - AX5: the lines exist with their VoiceOver labels and the HUD stays inside the safe area;
// - Settings → Show HUD turns it off.
// Simulator results are never device evidence (UIX-013-T12 is the device check). Owner rule 7: each test < 30 s.
import XCTest

@MainActor
final class SceneHUDUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var hud: XCUIElement { app.descendants(matching: .any)["sceneHUD"].firstMatch }
    private func line(_ id: String) -> XCUIElement { app.staticTexts[id] }

    private func launch(_ extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestShowSeed", "-autostart", "inAppPlayback", "-uitestTapInterval", "500",
                               "-uitestDiagnostics", "-settings.visualizer.sceneHUD", "YES"] + extra + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    /// The safe area in window coordinates, from UIX-005's probe ("x,y,w,h"; needs the performance layout).
    private func safeArea() -> CGRect {
        let probe = app.staticTexts["performanceSafeArea"]
        XCTAssertTrue(probe.appears(within: 3), "safe-area probe")
        let parts: [Double] = ((probe.value as? String) ?? "").split(separator: ",").compactMap { (s: Substring) -> Double? in Double(s) }
        XCTAssertEqual(parts.count, 4)
        guard parts.count == 4 else { return .null }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]).insetBy(dx: -0.5, dy: -0.5)
    }

    private func value(_ id: String) -> String? { line(id).value as? String }

    func testHUDShowsTheShowAndStaysClearOfTheOutput() {
        launch(["-uitestPerformanceLayout"])
        XCTAssertTrue(hud.appears(within: 3), "on through the preference")
        XCTAssertTrue(poll(3) { self.value("hudCurrentCue") == "Cue 1 of 5, Opening" }, "current: \(value("hudCurrentCue") ?? "nil")")
        XCTAssertEqual(line("hudCurrentCue").label, "Current cue")
        XCTAssertEqual(value("hudNextCue"), "Next: Build")
        XCTAssertEqual(line("hudTempo").label, "Tempo")
        let tempo: String = value("hudTempo") ?? ""
        XCTAssertTrue(tempo == "No tempo" || tempo.hasSuffix("estimated"), "before any tap: none or the estimate: \(tempo)")
        let source: String = value("hudSource") ?? ""
        XCTAssertTrue(source.hasPrefix("In-App Playback"), "FR-042's source text: \(source)")

        // C3: inside the safe area, clear of the centre and of the pad's targets.
        let frame: CGRect = hud.frame
        let window: CGRect = app.windows.firstMatch.frame
        XCTAssertTrue(safeArea().contains(frame), "\(frame) inside the safe area")
        XCTAssertFalse(frame.contains(CGPoint(x: window.midX, y: window.midY)), "\(frame) does not cover the centre")
        XCTAssertLessThan(frame.maxY, window.midY, "in the top band")
        XCTAssertLessThanOrEqual(frame.width, 360.5)
        for id in ["perfPreviousCue", "perfNextCue", "perfTapTempo", "perfBlackout"] {
            XCTAssertFalse(frame.intersects(app.buttons[id].frame), "clear of \(id)")
        }

        // S3: the HUD follows a cue step and a tapped tempo.
        app.buttons["perfNextCue"].tap()
        XCTAssertTrue(poll(3) { self.value("hudCurrentCue") == "Cue 2 of 5, Build" }, "after Next: \(value("hudCurrentCue") ?? "nil")")
        XCTAssertEqual(value("hudNextCue"), "Next: Drop")
        let tap = app.buttons["perfTapTempo"]
        for _ in 0..<4 { tap.tap() }
        XCTAssertTrue(poll(3) { self.value("hudTempo") == "120 BPM from tap" }, "tempo: \(value("hudTempo") ?? "nil")")
        XCTAssertTrue(line("hudTempo").label == "Tempo")
    }

    func testLargestTextKeepsTheHUDOnScreen() {
        launch(["-uitestPerformanceLayout", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(hud.appears(within: 3))
        for (id, label) in [("hudCurrentCue", "Current cue"), ("hudNextCue", "Next cue"), ("hudTempo", "Tempo"), ("hudSource", "Audio source")] {
            XCTAssertTrue(line(id).exists, id)
            XCTAssertEqual(line(id).label, label)
        }
        XCTAssertTrue(safeArea().contains(hud.frame), "\(hud.frame) inside the safe area at AX5")
    }

    func testSettingsSwitchTurnsTheHUDOff() {
        launch(["-uitestSettingsSection", "sceneHUD"])
        XCTAssertTrue(hud.appears(within: 3))
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 3))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let toggle = app.switches["sceneHUDToggle"]
        XCTAssertTrue(toggle.appears(within: 3) || app.reveal(toggle), "Settings → Performance → Show HUD")
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(2) { (toggle.value as? String) == "0" })
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(hud.disappears(within: 3), "off: no HUD")
    }
}
