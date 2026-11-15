// LeftHandedUITests.swift — ACC-010-T07 on the iOS Simulator (specs/248-acc-010-left-handed-layout; S2, R2, R3, R5).
// With the DEBUG show seed (`-uitestShowSeed`) and the safe-area probe (`-uitestDiagnostics`):
// - portrait: SHOW-014's emergency button, then UIX-005's bottom bar; Settings → Left-handed controls on; the bar's
//   Tap tempo and Black out sit at the mirror of their right-handed frames (within 1 pt), the cue pair at the mirror
//   of its pair with Previous still left of Next, the same four `perf*` identifiers; with the pad off the emergency
//   button sits at the mirror of its right-handed frame;
// - landscape with the setting on at launch: Tap tempo and Black out in the leading column, the cue targets in the
//   trailing one, the two columns mirrored within 1 pt.
// Simulator results are never device evidence (ACC-010-T13 is the device check). Owner rule 7: each test < 30 s.
import XCTest

@MainActor
final class LeftHandedUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static let targets = ["perfPreviousCue", "perfNextCue", "perfTapTempo", "perfBlackout"]
    private var pad: XCUIElement { app.descendants(matching: .any)["performancePad"].firstMatch }
    private var controls: XCUIElement { app.otherElements["controls"] }

    private func launch(_ extra: [String]) {
        app.launchArguments = ["-uitestResetNotice", "-uitestShowSeed", "-autostart", "inAppPlayback", "-uitestDiagnostics"]
            + extra + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    /// The safe area in window coordinates, from UIX-005's probe ("x,y,w,h"; needs the pad).
    private func safeArea() -> CGRect {
        let probe = app.staticTexts["performanceSafeArea"]
        XCTAssertTrue(probe.appears(within: 3), "safe-area probe")
        let parts: [Double] = ((probe.value as? String) ?? "").split(separator: ",").compactMap { (s: Substring) -> Double? in Double(s) }
        XCTAssertEqual(parts.count, 4)
        guard parts.count == 4 else { return .null }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// The pad's targets by identifier, and the identifiers of every `perf*` button on screen (R5).
    private func padFrames() -> (frames: [String: CGRect], ids: Set<String>) {
        var frames: [String: CGRect] = [:]
        for id in Self.targets {
            let target = app.buttons[id]
            XCTAssertTrue(target.appears(within: 5), "\(id) exists")
            frames[id] = target.frame
        }
        // Every pad button on screen: the four targets and nothing else (`performanceLayout` is the controls' toggle).
        let others = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'perf' AND identifier != 'performanceLayout'"))
        XCTAssertEqual(others.count, Self.targets.count, "no other pad button")
        let present: [String] = Self.targets.filter { (id: String) -> Bool in app.buttons[id].exists }
        return (frames, Set(present))
    }

    /// `left` lies at the horizontal mirror of `right` about the vertical line at `axis` (within 1 pt).
    private func assertMirrored(_ left: CGRect, _ right: CGRect, axis: CGFloat, _ what: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(left.minX, 2 * axis - right.maxX, accuracy: 1, "\(what) x: \(left) vs \(right)", file: file, line: line)
        XCTAssertEqual(left.minY, right.minY, accuracy: 1, "\(what) y", file: file, line: line)
        XCTAssertEqual(left.width, right.width, accuracy: 1, "\(what) width", file: file, line: line)
    }

    private func showControls() {
        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 3))
    }

    func testSwitchingMirrorsThePadAndTheEmergencyButton() {
        XCUIDevice.shared.orientation = .portrait
        launch(["-uitestSettingsSection", "leftHanded"])
        let emergency = app.buttons["emergencyBlackout"]
        XCTAssertTrue(emergency.appears(within: 3))
        let window: CGRect = app.windows.firstMatch.frame
        let emergencyRight: CGRect = emergency.frame
        XCTAssertGreaterThan(emergencyRight.minX, window.midX, "right-handed: bottom trailing corner")

        showControls()
        app.buttons["performanceLayout"].tap()
        XCTAssertTrue(pad.appears(within: 3))
        let right = padFrames()
        let axis: CGFloat = safeArea().midX

        // Settings → Left-handed controls (the controls stay up after the layout button: it restarts the auto-hide).
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let toggle = app.switches["leftHandedToggle"]
        XCTAssertTrue(toggle.appears(within: 3) || app.reveal(toggle), "Settings → Performance → Left-handed controls")
        XCTAssertEqual(toggle.value as? String, "0", "off by default")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(2) { (toggle.value as? String) == "1" })
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(poll(3) { self.app.buttons["perfBlackout"].frame.maxX < axis }, "Black out moved left")

        let left = padFrames()
        XCTAssertEqual(left.ids, right.ids, "identical identifiers (R5)")
        XCTAssertEqual(left.ids, Set(Self.targets))
        for id in ["perfTapTempo", "perfBlackout"] {
            assertMirrored(left.frames[id]!, right.frames[id]!, axis: axis, id)
        }
        assertMirrored(left.frames["perfPreviousCue"]!.union(left.frames["perfNextCue"]!),
                       right.frames["perfPreviousCue"]!.union(right.frames["perfNextCue"]!), axis: axis, "cue pair")
        XCTAssertLessThan(left.frames["perfPreviousCue"]!.minX, left.frames["perfNextCue"]!.minX, "reading order kept")
        XCTAssertEqual(app.buttons["perfBlackout"].label, "Black out output", "labels unchanged")

        // Pad off: the emergency button returns in the bottom leading corner.
        showControls()
        app.buttons["performanceLayout"].tap()
        XCTAssertTrue(pad.disappears(within: 3))
        XCTAssertTrue(emergency.appears(within: 3))
        assertMirrored(emergency.frame, emergencyRight, axis: window.midX, "emergencyBlackout")
    }

    func testLandscapeColumnsSwapSides() {
        XCUIDevice.shared.orientation = .portrait
        launch(["-uitestPerformanceLayout", "-settings.controls.leftHanded", "YES"])
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(pad.appears(within: 3))
        XCTAssertTrue(poll(3) { self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height }, "rotated")
        XCTAssertTrue(poll(3) { self.app.buttons["perfTapTempo"].frame.maxX < self.app.windows.firstMatch.frame.midX }, "columns laid out")
        // The rotation animates: wait until every target holds still at full size and the probe reports a landscape area.
        for id in Self.targets { app.buttons[id].settles(within: 3) }
        XCTAssertTrue(poll(3) { self.app.buttons["perfPreviousCue"].frame.width >= 59.5 }, "rotation finished")
        XCTAssertTrue(poll(3) { self.safeArea().height <= self.app.windows.firstMatch.frame.height }, "probe updated")
        let (frames, ids) = padFrames()
        XCTAssertEqual(ids, Set(Self.targets))
        let safe: CGRect = safeArea()
        for id in ["perfTapTempo", "perfBlackout"] {
            XCTAssertLessThan(frames[id]!.maxX, safe.midX - safe.width / 4, "\(id) in the leading column")
        }
        for id in ["perfPreviousCue", "perfNextCue"] {
            XCTAssertGreaterThan(frames[id]!.minX, safe.midX + safe.width / 4, "\(id) in the trailing column")
        }
        // The columns are mirror images: same inset from their edges (within 1 pt).
        XCTAssertEqual(frames["perfTapTempo"]!.minX - safe.minX, safe.maxX - frames["perfPreviousCue"]!.maxX, accuracy: 1)
        XCTAssertLessThan(frames["perfPreviousCue"]!.minY, frames["perfNextCue"]!.minY, "Previous above Next")
    }
}
