// OneHandedUITests.swift — ACC-009-T09, T11, T12 on the iOS Simulator (specs/244-acc-009-one-handed-mode; S3, S4).
// The acceptance "Layout switch preserves every critical action on phone sizes", run on two phone sizes (iPhone 17
// and the 375 × 667 pt iPhone SE):
// - a projectM preset with the standard layout: the critical actions present are noted; Settings → One-handed layout
//   → Right hand; back on the visualizer the same identifiers exist, are hittable, at least 44 pt, and lie inside the
//   bottom-right thumb zone (the layer's `oneHandedZone` probe); Pause from the cluster pauses;
// - the show seed (cues; its cue 1 is a native visual) with Left hand and the HUD on: the same set as the standard
//   layout's for that state in the bottom-left zone, none intersecting the HUD;
// - with the UIX-005 pad on (Right hand): the pad's four targets are 60 pt, in the zone, with the controls hidden.
// Simulator results are UI evidence only (ACC-009-T14 is the device pass). Owner rule 7: each test < 30 s.
import XCTest

@MainActor
final class OneHandedUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// Every critical identifier (ShowControl's `CriticalAction.identifier`), in layout order.
    private static let critical = ["showPreviousCue", "showNextCue", "tapTempo", "blackout", "previous", "next", "random",
                                   "pauseResume", "presets", "settings", "stop"]

    private var controls: XCUIElement { app.otherElements["controls"] }
    private var tapArea: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    private func launch(_ extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + extra + Self.noStore
        app.launch()
    }

    private func showControls() {
        XCTAssertTrue(tapArea.appears(within: 15), "the visualizer came up")
        if !controls.exists { tapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls show")
    }

    /// The critical identifiers present now.
    private func presentCritical() -> [String] {
        Self.critical.filter { (id: String) -> Bool in app.buttons[id].exists }
    }

    /// The thumb zone in window coordinates, from the layer's probe ("x,y,w,h").
    private func zone(file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let probe = app.staticTexts["oneHandedZone"]
        XCTAssertTrue(probe.appears(within: 3), "zone probe", file: file, line: line)
        let parts: [Double] = ((probe.value as? String) ?? "").split(separator: ",").compactMap { (s: Substring) -> Double? in Double(s) }
        XCTAssertEqual(parts.count, 4, file: file, line: line)
        guard parts.count == 4 else { return .null }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// S3, S4: each identifier exists, is hittable, at least `side` square, inside the zone (and the zone on the side).
    @discardableResult
    private func assertInZone(_ ids: [String], side: CGFloat = 44, right: Bool, file: StaticString = #filePath,
                              line: UInt = #line) -> [CGRect] {
        let thumb: CGRect = zone(file: file, line: line)
        let window: CGRect = app.windows.firstMatch.frame
        XCTAssertGreaterThan(thumb.minY, window.midY, "the zone is in the bottom half \(thumb)", file: file, line: line)
        if right {
            XCTAssertEqual(thumb.maxX, window.maxX, accuracy: 60, "the zone is on the right \(thumb)", file: file, line: line)
        } else {
            XCTAssertEqual(thumb.minX, window.minX, accuracy: 60, "the zone is on the left \(thumb)", file: file, line: line)
        }
        let inside: CGRect = thumb.insetBy(dx: -0.5, dy: -0.5)
        var frames: [CGRect] = []
        for id in ids {
            let target = app.buttons[id]
            XCTAssertTrue(target.appears(within: 3), "\(id) exists", file: file, line: line)
            XCTAssertEqual(app.buttons.matching(identifier: id).count, 1, "\(id) once", file: file, line: line)
            XCTAssertTrue(poll(2) { target.isHittable }, "\(id) is hittable \(target.frame)", file: file, line: line)
            let frame: CGRect = target.frame
            XCTAssertGreaterThanOrEqual(min(frame.width, frame.height), side - 0.5, "\(id) \(frame) size", file: file, line: line)
            XCTAssertTrue(inside.contains(frame), "\(id) \(frame) inside the zone \(thumb)", file: file, line: line)
            frames.append(frame)
        }
        return frames
    }

    /// S3: Standard → Right hand in Settings keeps every critical action, now in the bottom-right zone.
    func testSwitchToRightHandKeepsEveryCriticalAction() {
        launch(["-uitestKeepControls", "-uitestSettingsSection", "oneHanded"])
        showControls()
        XCTAssertTrue(app.buttons["duplicateCurrent"].appears(within: 10), "a projectM preset is showing")
        let standard: [String] = presentCritical()
        XCTAssertEqual(standard, Self.critical.filter { !$0.hasPrefix("show") }, "the standard set (no show loaded)")
        XCTAssertFalse(app.staticTexts["oneHandedZone"].exists, "standard layout: no cluster")

        app.buttons["settings"].tap()
        let right = app.buttons["oneHanded.right"]
        XCTAssertTrue(right.appears(within: 5) || app.reveal(right, down: true), "the One-handed rows")
        right.tap()
        XCTAssertTrue(poll(2) { right.isSelected }, "Right hand chosen")
        app.navigationBars["Settings"].buttons["Done"].tap()

        showControls()
        XCTAssertEqual(presentCritical(), standard, "the switch keeps every critical action")
        assertInZone(standard, right: true)
        XCTAssertFalse(app.otherElements["controlsPrimary"].exists, "the card's main row moved into the cluster")

        let pause = app.buttons["pauseResume"]
        pause.tap()
        XCTAssertTrue(app.staticTexts["pausedLabel"].appears(within: 3), "Pause from the cluster pauses")
        XCTAssertTrue(poll(2) { pause.label == "Resume" })
    }

    /// S4: Left hand with a show and the HUD: the standard set for that state, bottom-left, clear of the HUD.
    func testLeftHandWithShowAndHUD() {
        launch(["-uitestKeepControls", "-uitestShowSeed", "-settings.visualizer.sceneHUD", "YES",
                "-settings.controls.oneHanded", "left"])
        showControls()
        // Cue 1 of the seed is a native visual: no preset actions, as in the standard layout (VIS-001-R13).
        let expected: [String] = ["showPreviousCue", "showNextCue", "tapTempo", "blackout", "pauseResume", "settings", "stop"]
        XCTAssertTrue(poll(5) { self.presentCritical() == expected }, "the native visual's set: \(presentCritical())")
        let frames: [CGRect] = assertInZone(expected, right: false)
        let hud = app.descendants(matching: .any)["sceneHUD"].firstMatch
        XCTAssertTrue(hud.appears(within: 3), "the HUD shows")
        for (id, frame) in zip(expected, frames) {
            XCTAssertFalse(frame.intersects(hud.frame), "\(id) \(frame) clear of the HUD \(hud.frame)")
        }
        XCTAssertFalse(controls.frame.intersects(frames.reduce(CGRect.null) { $0.union($1) }), "the card sits clear of the cluster")
    }

    /// R7: with the pad on, its four targets stay in the zone at 60 pt without the controls.
    func testPadTargetsInTheZoneWithoutTheControls() {
        launch(["-uitestShowSeed", "-uitestPerformanceLayout", "-settings.controls.oneHanded", "right"])
        XCTAssertTrue(tapArea.appears(within: 15))
        if controls.exists { tapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        XCTAssertTrue(controls.disappears(within: 8), "controls hidden")
        assertInZone(["perfPreviousCue", "perfNextCue", "perfTapTempo", "perfBlackout"], side: 60, right: true)
        XCTAssertTrue(app.staticTexts["perfCueReadout"].exists, "the cue readout stays")
        XCTAssertFalse(app.buttons["stop"].exists, "the main group shows only with the controls")
    }
}
