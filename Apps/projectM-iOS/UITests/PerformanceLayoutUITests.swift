// PerformanceLayoutUITests.swift — UIX-005-T08-T11 on the iOS Simulator (specs/193-uix-005-performance-
// controls; UIX-005-S1-S3). With the DEBUG show seed (`-uitestShowSeed`: five cues, standing on cue 1):
// - portrait: "Performance layout" from the controls shows the pad; each target (Previous cue, Next cue,
//   Tap tempo, Blackout) exists, is hittable, is at least 60 × 60 pt and lies inside the safe area (the
//   `performanceSafeArea` probe); the pad stays when the controls auto-hide; Next applies cue 2 without
//   showing the controls; Blackout blacks out and restores; Tap reads "Tap 1 of 4"; "Standard layout"
//   removes the pad and SHOW-014's emergency button returns;
// - landscape: the same geometry in two side columns clear of the centre; Next and Blackout work;
// - AX5 (portrait): the same geometry;
// - the system accessibility audit on the performance layout (no `-uitestDiagnostics`, whose
//   near-transparent probes would be audited), then B blacks out through the pad.
// Simulator results are never device evidence (UIX-005-T13 is the device pass). Owner rule 7: each
// test < 30 s; UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class PerformanceLayoutUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static let targets = ["perfPreviousCue", "perfNextCue", "perfTapTempo", "perfBlackout"]
    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }
    private static let visuals = ["circularSpectrum", "linearSpectrum", "circularSpectrum", "linearSpectrum", "text"]
    static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    private var pad: XCUIElement { app.descendants(matching: .any)["performancePad"].firstMatch }
    private var controls: XCUIElement { app.otherElements["controls"] }
    private var applied: String? { app.staticTexts["showAppliedScene"].value as? String }
    private var output: String? { app.staticTexts["outputBlackout"].value as? String }

    private func launch(_ extra: [String], diagnostics: Bool = true) {
        app.launchArguments = ["-uitestResetNotice", "-uitestShowSeed", "-autostart", "inAppPlayback",
                               "-uitestTapInterval", "500"] + (diagnostics ? ["-uitestDiagnostics"] : []) + extra + Self.noStore
        app.launch()
    }

    /// The safe area in window coordinates, from the pad's probe ("x,y,w,h").
    private func safeArea(file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let probe = app.staticTexts["performanceSafeArea"]
        XCTAssertTrue(probe.appears(within: 3), "safe-area probe", file: file, line: line)
        let parts: [Double] = ((probe.value as? String) ?? "").split(separator: ",").compactMap { (s: Substring) -> Double? in Double(s) }
        XCTAssertEqual(parts.count, 4, file: file, line: line)
        guard parts.count == 4 else { return .null }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// UIX-005-S1, S2: each target exists, is hittable, is at least `side` square and inside the safe area.
    @discardableResult
    private func assertTargets(side: CGFloat = 60, file: StaticString = #filePath, line: UInt = #line) -> [String: CGRect] {
        let safe: CGRect = safeArea(file: file, line: line).insetBy(dx: -0.5, dy: -0.5)
        var frames: [String: CGRect] = [:]
        for id in Self.targets {
            let target = app.buttons[id]
            XCTAssertTrue(target.appears(within: 5), "\(id) exists", file: file, line: line)
            XCTAssertTrue(target.isHittable, "\(id) is hittable", file: file, line: line)
            let frame: CGRect = target.frame
            XCTAssertGreaterThanOrEqual(frame.width, side - 0.5, "\(id) width \(frame)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.height, side - 0.5, "\(id) height \(frame)", file: file, line: line)
            XCTAssertTrue(safe.contains(frame), "\(id) \(frame) inside the safe area \(safe)", file: file, line: line)
            frames[id] = frame
        }
        return frames
    }

    private func expectCue(_ n: Int, file: StaticString = #filePath, line: UInt = #line) {
        let expected = "\(Self.sceneID(n))|\(Self.visuals[n - 1])"
        XCTAssertTrue(poll(3) { self.applied == expected }, "cue \(n) applied: \(applied ?? "nil")", file: file, line: line)
    }

    /// Blackout blacks out, then restores (OUT-010 probe).
    private func toggleBlackout(file: StaticString = #filePath, line: UInt = #line) {
        let blackout = app.buttons["perfBlackout"]
        XCTAssertEqual(blackout.label, "Black out output", file: file, line: line)
        XCTAssertEqual(blackout.value as? String, "Live", file: file, line: line)
        blackout.tap()
        XCTAssertTrue(poll(2) { self.output == "black" }, "blacked out", file: file, line: line)
        XCTAssertTrue(poll(2) { blackout.label == "Restore output" }, file: file, line: line)
        blackout.tap()
        XCTAssertTrue(poll(3) { self.output != "black" }, "restored: \(output ?? "nil")", file: file, line: line)
    }

    func testPortraitPadFromTheControls() {
        XCUIDevice.shared.orientation = .portrait
        launch([])
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        expectCue(1)
        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        let toggle = app.buttons["performanceLayout"]
        XCTAssertTrue(toggle.appears(within: 3))
        XCTAssertEqual(toggle.label, "Performance layout")
        XCTAssertFalse(pad.exists, "off at launch")
        toggle.tap()
        XCTAssertTrue(pad.appears(within: 3))
        XCTAssertFalse(app.buttons["emergencyBlackout"].exists, "the pad's Blackout replaces SHOW-014's corner button")
        let frames = assertTargets()
        // A bottom bar: one row, below the middle of the screen.
        let rows = Set(frames.values.map { (f: CGRect) -> Int in Int(f.midY.rounded()) })
        XCTAssertEqual(rows.count, 1, "one row \(frames)")
        XCTAssertGreaterThan(frames["perfNextCue"]!.minY, app.windows.firstMatch.frame.midY)
        XCTAssertEqual(app.staticTexts["perfCueReadout"].value as? String, "Cue 1 of 5, Opening")

        // UIX-005-R2: the pad stays when the controls auto-hide (5 s).
        XCTAssertTrue(controls.disappears(within: 8), "the controls auto-hide as before")
        XCTAssertTrue(app.buttons["perfNextCue"].isHittable, "the pad stays")

        app.buttons["perfNextCue"].tap()
        expectCue(2)
        XCTAssertFalse(controls.exists, "a pad step does not show the controls (UIX-005-R5)")
        XCTAssertTrue(poll(2) { (self.app.staticTexts["perfCueReadout"].value as? String) == "Cue 2 of 5, Build" })

        toggleBlackout()

        let tap = app.buttons["perfTapTempo"]
        tap.tap()
        XCTAssertTrue(poll(2) { (tap.value as? String) == "Tap 1 of 4" }, "a tap is recorded: \(tap.value as? String ?? "nil")")
        XCTAssertFalse(controls.exists)

        // "Standard layout" removes the pad; the emergency button returns.
        app.otherElements["visualizerTapArea"].firstMatch.tap()
        XCTAssertTrue(toggle.appears(within: 3))
        XCTAssertEqual(toggle.label, "Standard layout")
        toggle.tap()
        XCTAssertTrue(pad.disappears(within: 3))
        XCTAssertTrue(app.buttons["emergencyBlackout"].appears(within: 3))
    }

    func testLandscapeSideColumns() {
        XCUIDevice.shared.orientation = .portrait
        launch(["-uitestPerformanceLayout"])
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(pad.appears(within: 3))
        let window: CGRect = app.windows.firstMatch.frame
        XCTAssertTrue(poll(3) { self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height }, "rotated")
        XCTAssertTrue(poll(3) { self.app.buttons["perfNextCue"].frame.maxX < self.app.windows.firstMatch.frame.midX }, "columns laid out")
        let frames = assertTargets()
        let mid: CGFloat = app.windows.firstMatch.frame.midX
        let quarter: CGFloat = app.windows.firstMatch.frame.width / 4
        for id in ["perfPreviousCue", "perfNextCue"] {
            XCTAssertLessThan(frames[id]!.maxX, mid - quarter, "\(id) in the leading column, clear of the centre")
        }
        for id in ["perfTapTempo", "perfBlackout"] {
            XCTAssertGreaterThan(frames[id]!.minX, mid + quarter, "\(id) in the trailing column, clear of the centre")
        }
        _ = window
        app.buttons["perfNextCue"].tap()
        expectCue(2)
        toggleBlackout()
    }

    func testAX5PortraitKeepsTheTargets() {
        XCUIDevice.shared.orientation = .portrait
        launch(["-uitestPerformanceLayout", "-UIPreferredContentSizeCategoryName", Self.ax5])
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(pad.appears(within: 3))
        assertTargets()
        app.buttons["perfNextCue"].tap()
        expectCue(2)
    }

    // MARK: - Accessibility audit (UIX-005-T11, S3)

    private static let auditTypes: XCUIAccessibilityAuditType = [
        .sufficientElementDescription, .hitRegion, .contrast, .dynamicType, .trait, .textClipped,
    ]

    /// The one documented filter, shared with ACC-004's audit (AccessibilityScreensUITests): the PERF-014
    /// placeholder "Visual unavailable" is caught while fading or hidden behind the live visual; at full
    /// opacity its grey on black is about 6:1. Nothing on the pad is filtered.
    private static func isFiltered(type: XCUIAccessibilityAuditType, label: String) -> Bool {
        type == .contrast && label == "Visual unavailable"
    }

    func testAccessibilityAuditOnThePerformanceLayout() throws {
        XCUIDevice.shared.orientation = .portrait
        launch(["-uitestPerformanceLayout"], diagnostics: false)
        let next = app.buttons["perfNextCue"]
        XCTAssertTrue(next.appears(within: 15))
        XCTAssertTrue(controls.disappears(within: 8), "audit the pad over the visual, controls hidden")
        var issues: [String] = []
        try app.performAccessibilityAudit(for: Self.auditTypes) { (issue: XCUIAccessibilityAuditIssue) -> Bool in
            let snapshot: XCUIElementSnapshot? = try? issue.element?.snapshot()
            let id: String = snapshot?.identifier ?? ""
            let label: String = snapshot?.label ?? ""
            let frame: String = snapshot.map { (s: XCUIElementSnapshot) -> String in NSCoder.string(for: s.frame) } ?? "-"
            if Self.isFiltered(type: issue.auditType, label: label) { return true }
            issues.append("type(\(issue.auditType.rawValue)) id=\"\(id)\" label=\"\(label)\" frame=\(frame): "
                          + issue.compactDescription + " | " + issue.detailedDescription)
            return true
        }
        if !issues.isEmpty {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "audit-performance-layout"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertTrue(issues.isEmpty, "audit issues:\n" + issues.joined(separator: "\n"))

        // UIX-005-R8: B blacks out through the pad while live.
        let blackout = app.buttons["perfBlackout"]
        XCTAssertEqual(blackout.label, "Black out output")
        app.typeKey("b", modifierFlags: [])
        XCTAssertTrue(poll(3) { blackout.label == "Restore output" }, "B blacked out: \(blackout.label)")
    }
}
