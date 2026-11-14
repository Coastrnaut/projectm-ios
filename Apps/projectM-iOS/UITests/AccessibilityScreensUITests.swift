// AccessibilityScreensUITests.swift — ACC-004-T08-T10 on the iOS Simulator
// (specs/082-acc-004-voiceover-scene-browser; ACC-004-R1, R2, R5, R8, R9; S1, S2, S4, S5).
//
// Each test walks one group of primary screens of the "scene browser" (spec: the visualizer controls,
// the show editor, the preset browser, Collections, My Presets, Settings) and on each screen:
// (a) runs the system accessibility audit for element description, hit region, contrast, Dynamic Type
//     and traits, failing on any issue not matched by a documented per-issue filter (`AuditFilter`);
// (b) checks the declared primary controls (contract C2): present, non-empty label, hittable, of the
//     declared element type (the button trait shows as `.button`).
// The audit tests launch without `-uitestDiagnostics`, whose near-transparent probes would be audited
// as app content; the announcement test uses it to read `announcementProbe`. `-uitestKeepControls`
// keeps the controls up the way VoiceOver does. Simulator results are never device evidence; the
// VoiceOver pass on D1 is ACC-004-T12. Owner rule 7: each test < 30 s; UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class AccessibilityScreensUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Audit filters (contract C3)

    /// One filtered audit issue: the screen, the audit type and the element (identifier, or label when
    /// the element has no identifier), with the reason it is not the app's to fix. Never a whole type
    /// or a whole screen.
    /// `element` matches the identifier, else the whole label; `labelPrefix` matches a long label by
    /// its start; `elementless` matches an issue the audit reports without an element, at most `limit`
    /// times per run, so a new unlabelled problem still fails the test.
    struct AuditFilter: Sendable {
        let screen: String
        let type: XCUIAccessibilityAuditType
        let element: String
        var labelPrefix = false
        var elementless = false
        var limit = Int.max
        let reason: String

        func matches(screen: String, type: XCUIAccessibilityAuditType, identifier: String, label: String, hasElement: Bool) -> Bool {
            guard self.screen == screen, self.type == type else { return false }
            if elementless { return !hasElement }
            guard hasElement else { return false }
            if identifier == element { return true }
            guard identifier.isEmpty else { return false }
            return labelPrefix ? label.hasPrefix(element) : label == element
        }
    }

    /// The sheets' system Done button (a toolbar `confirmationAction`, drawn by iOS as a glass button).
    /// Dynamic Type: navigation-bar items do not scale by design (iOS offers the Large Content Viewer).
    /// Contrast: the audit samples the glass, which shows the live visualization at the sheet's top
    /// edge; the button's black-on-white text is the system's (screenshot audit-browser, 2026-11-13).
    nonisolated private static func systemDone(_ screen: String) -> [AuditFilter] {
        [AuditFilter(screen: screen, type: .dynamicType, element: "Done",
                     reason: "system navigation-bar Done; bar items do not scale with Dynamic Type (Large Content Viewer)"),
         AuditFilter(screen: screen, type: .contrast, element: "Done",
                     reason: "system glass Done button; the audit samples the live visualization behind the glass")]
    }

    /// Rows at the bottom of the browser home: at the audit's larger text sizes they move below the
    /// visible list, which the audit reports as "partially unsupported". They do scale: see
    /// `testBrowserRowsScaleWithAccessibilityTextSizes` (ACC-004-T10). ACC-006 re-checked (2026-11-13):
    /// still reported when the screen starts at the default size; a walk that starts at AX3 or AX5
    /// (DynamicTypeInspectorUITests) reports nothing for these rows, so the filter stays here only.
    nonisolated private static func bottomRows(_ screen: String) -> [AuditFilter] {
        ["Collections", "My Presets", "0"].map { (label: String) -> AuditFilter in
            AuditFilter(screen: screen, type: .dynamicType, element: label,
                        reason: "row pushed off screen at the audit's larger sizes; scaling proven by a separate test")
        }
    }

    static let filters: [AuditFilter] =
        ["browser", "pack", "collections", "myPresets", "settings", "showEditor"].flatMap(systemDone)
        + bottomRows("browser")
        + [AuditFilter(screen: "controls", type: .contrast, element: "Visual unavailable",
                       reason: "PERF-014 placeholder caught while fading (opacity < 1) or hidden behind the live "
                           + "visual; at full opacity its grey 0.55 on black is about 6:1")]
        + [AuditFilter(screen: "settings", type: .contrast, element: "Visual", limit: 2,
                       reason: "the two system section headers (\"Visual\") in Apple's secondary grey"),
           AuditFilter(screen: "settings", type: .contrast, element: "", elementless: true, limit: 3,
                       reason: "\"nearly passed\" findings the audit reports without an element (1 to 9 per run, 2026-11-13; "
                           + "after the row-colour fix at most 3): the only grey text on screen is system styling, the two "
                           + "section headers and the disabled undo/redo toolbar glyphs. Bounded so a new one still fails"),
           AuditFilter(screen: "settings", type: .contrast, element: "projectM plays presets.", labelPrefix: true,
                       reason: "the system section footer style (Apple's secondary grey) of the Visual section (VIS-002)"),
           AuditFilter(screen: "settings", type: .dynamicType, element: "Glow",
                       reason: "the system Toggle at the bottom of the screen is pushed off screen at the audit's larger "
                           + "sizes, as the browser's bottom rows are (their scaling is proven by "
                           + "testBrowserRowsScaleWithAccessibilityTextSizes); a system control's label scales")]
        // ACC-003-R11: the "Add Current Scene" filter is gone; the app's AccentColor (0062CC, 5.8:1 on white)
        // replaced systemBlue (about 4:1).
        + [AuditFilter(screen: "showEditor", type: .contrast, element: "Adds a cue that keeps the visual", labelPrefix: true,
                       reason: "the system section footer style (Apple's secondary grey)"),
           AuditFilter(screen: "showEditor", type: .dynamicType, element: "Cues",
                       reason: "the system section header is pushed below the visible list at the audit's larger sizes "
                           + "(ACC-006 lets \"Add Current Scene\" wrap in its own column, so that row grows), as the "
                           + "browser's bottom rows are; DynamicTypeInspectorUITests audits the editor at AX3 and AX5"),
           AuditFilter(screen: "showEditor", type: .contrast, element: "Cues",
                       reason: "the system section header style (Apple's secondary grey)")]
        // The tempo readout's em-dash filter is gone (2026-11-14): the readout is one element, so the dash's
        // failure came without an element and never matched it; searching now reads "— BPM" and passes.

    private static let auditTypes: XCUIAccessibilityAuditType = [
        .sufficientElementDescription, .hitRegion, .contrast, .dynamicType, .trait,
    ]

    private static func name(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .sufficientElementDescription: "sufficientElementDescription"
        case .hitRegion: "hitRegion"
        case .contrast: "contrast"
        case .dynamicType: "dynamicType"
        case .trait: "trait"
        default: "type(\(type.rawValue))"
        }
    }

    /// Runs the audit on what is on screen; every unfiltered issue is listed in one failure.
    private func audit(_ screen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        var unfiltered: [String] = []
        var used: [Int: Int] = [:]
        try app.performAccessibilityAudit(for: Self.auditTypes) { (issue: XCUIAccessibilityAuditIssue) -> Bool in
            // One snapshot per issue: reading an element's properties one by one re-resolves it each time,
            // and a stale element costs three 1 s retries per property (83 s for one screen on 2026-11-13).
            let snapshot: XCUIElementSnapshot? = try? issue.element?.snapshot()
            let identifier = snapshot?.identifier ?? ""
            let label = snapshot?.label ?? ""
            var filtered = false
            for (index, filter) in Self.filters.enumerated()
            where filter.matches(screen: screen, type: issue.auditType, identifier: identifier, label: label,
                                 hasElement: snapshot != nil) && used[index, default: 0] < filter.limit {
                used[index, default: 0] += 1
                filtered = true
                break
            }
            if !filtered {
                unfiltered.append("[\(screen)] \(Self.name(issue.auditType)) id=\"\(identifier)\" label=\"\(label)\" "
                                  + "type=\(snapshot?.elementType.rawValue ?? 0) frame=\(snapshot.map { NSCoder.string(for: $0.frame) } ?? "-"): "
                                  + "\(issue.compactDescription) | \(issue.detailedDescription)")
            }
            return true   // collected here, reported together below
        }
        if !unfiltered.isEmpty {   // the screen as audited, for triage
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "audit-\(screen)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertTrue(unfiltered.isEmpty, "unfiltered audit issues:\n" + unfiltered.joined(separator: "\n"), file: file, line: line)
    }

    /// The controls float over the live visualization. The audit's contrast check samples its own
    /// capture of the moving picture, which need not match what is on screen: over a dark preset with
    /// white text it reported "Contrast failed" in one run of three (screenshot audit-controls,
    /// 2026-11-13). The controls are audited over a blacked-out output, a stable background; their dark
    /// thick backing (ACC-004) keeps the contrast over any picture. Restores the output afterwards.
    private func auditOverBlackedOutOutput(_ screen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        app.buttons["blackout"].tap()
        XCTAssertTrue(poll(3) { self.app.buttons["blackout"].label == "Restore output" }, "blacked out", file: file, line: line)
        try audit(screen, file: file, line: line)
        app.buttons["blackout"].tap()
    }

    /// Contract C2: each control exists with the declared type, a non-empty label, and can be hit.
    private func requireControls(_ controls: [(String, XCUIElement.ElementType)], screen: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        for (identifier, type) in controls {
            let element = app.descendants(matching: type)[identifier].firstMatch
            XCTAssertTrue(element.appears(within: 5), "[\(screen)] \(identifier) is in the tree", file: file, line: line)
            XCTAssertFalse(element.label.isEmpty, "[\(screen)] \(identifier) has a label", file: file, line: line)
            XCTAssertTrue(element.isHittable, "[\(screen)] \(identifier) is reachable", file: file, line: line)
        }
    }

    private func launch(_ extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestKeepControls", "-autostart", "inAppPlayback"] + extra + Self.noStore
        app.launch()
    }

    private var controls: XCUIElement { app.otherElements["controls"] }

    private func showControls() {
        let area = app.otherElements["visualizerTapArea"].firstMatch
        XCTAssertTrue(area.appears(within: 15), "the visualizer is up")
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
    }

    private func openPresetBrowser() {
        showControls()
        app.buttons["presets"].tap()
        XCTAssertTrue(app.buttons["node:included"].appears(within: 10), "library home")
    }

    // MARK: - Screens

    /// The visualizer controls with the show row (ACC-004-R1, R4).
    func testVisualizerControlsAreLabelledAndPassTheAudit() throws {
        launch()
        showControls()
        XCTAssertTrue(poll(10) { self.app.buttons["duplicateCurrent"].exists }, "a projectM preset is showing")
        let buttons = ["stop", "pauseResume", "blackout", "saveFrame", "record", "previous", "next", "random", "presets",
                       "settings", "duplicateCurrent", "emergencyBlackout"]
        requireControls(buttons.map { ($0, .button) }, screen: "controls")
        XCTAssertEqual(app.buttons["next"].label, "Next")
        try auditOverBlackedOutOutput("controls")
    }

    /// The preset browser's home and one pack's preset rows (ACC-004-R1, R2).
    func testPresetBrowserAndPackAreLabelledAndPassTheAudit() throws {
        launch()
        openPresetBrowser()
        requireControls([("favoritesFilter", .segmentedControl), ("node:included", .button),
                         ("node:collections", .button), ("node:myPresets", .button)], screen: "browser")
        try audit("browser")

        app.buttons["node:included"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch
        XCTAssertTrue(row.appears(within: 5), "the pack lists presets")
        let name = String(row.identifier.dropFirst("preset:".count))
        requireControls([(row.identifier, .button), ("star:\(name)", .button)], screen: "pack")
        XCTAssertEqual(row.label.hasPrefix("\(name), by "), true, "the row reads name and author: \(row.label)")
        try audit("pack")
    }

    /// Evidence for the `bottomRows` filter: at an accessibility text size the browser rows grow.
    func testBrowserRowsScaleWithAccessibilityTextSizes() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        openPresetBrowser()
        for id in ["node:collections", "node:myPresets"] {
            let row = app.buttons[id]
            XCTAssertTrue(app.reveal(row), "\(id) is reachable at AX L")
            XCTAssertGreaterThan(row.frame.height, 60, "\(id) grows with the text (52 pt at the default size)")
        }
    }

    /// Collections and My Presets (ACC-004-R1).
    func testCollectionsAndMyPresetsAreLabelledAndPassTheAudit() throws {
        launch()
        openPresetBrowser()
        app.buttons["node:collections"].tap()
        XCTAssertTrue(app.navigationBars["Collections"].appears(within: 5))
        requireControls([("newCollection", .button)], screen: "collections")
        try audit("collections")

        app.navigationBars["Collections"].buttons.element(boundBy: 0).tap()   // back to the home
        XCTAssertTrue(app.buttons["node:myPresets"].appears(within: 5))
        app.buttons["node:myPresets"].tap()
        requireControls([("importPreset", .button)], screen: "myPresets")
        try audit("myPresets")
    }

    /// The show row in the controls (SHOW-001, ACC-004-R1).
    func testShowRowIsLabelledAndPassesTheAudit() throws {
        launch(["-uitestShowSeed"])
        showControls()
        // The show row in the controls (SHOW-001; the seed's cue 1 shows a native visual).
        XCTAssertTrue(app.staticTexts["showCueStatus"].appears(within: 5))
        requireControls([("showNextCue", .button), ("settings", .button), ("stop", .button)], screen: "showRow")
        XCTAssertEqual(app.buttons["showPreviousCue"].label, "Previous cue", "disabled on cue 1, still labelled")
        XCTAssertEqual(app.staticTexts["showCueStatus"].label, "Show")
        XCTAssertTrue((app.staticTexts["showCueStatus"].value as? String ?? "").hasPrefix("Cue 1 of 5"))
        try auditOverBlackedOutOutput("showRow")
    }

    /// Settings and the show editor: the scene cards (ACC-004-R1, R2). Split from the show row to stay
    /// under 30 s (owner rule 7). The first Settings of the launch opens at the Show row (DEBUG
    /// `-uitestSettingsSection show -uitestSettingsSectionOnce`: the row sits below the reach of `reveal`
    /// as Settings grows, 2026-11-14); the second opens at the top, where the Settings audit runs.
    func testSettingsAndShowEditorAreLabelledAndPassTheAudit() throws {
        launch(["-uitestShowSeed", "-uitestSettingsSection", "show", "-uitestSettingsSectionOnce"])
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let link = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(link), "the Show row is reachable")
        requireControls([("showEditorLink", .button)], screen: "settings")
        link.tap()
        XCTAssertTrue(app.navigationBars["Show"].appears(within: 5))
        requireControls([("showAddCurrentScene", .button)], screen: "showEditor")
        let labels = ["Opening", "Build", "Drop", "Break", "Finale"]
        for n in 1...3 {   // the first three cue cards are on screen on every iPhone
            let cue = app.descendants(matching: .any)["showCue\(n)"].firstMatch
            XCTAssertTrue(cue.appears(within: 5), "cue \(n) is one element")
            XCTAssertEqual(cue.label, labels[n - 1])
            XCTAssertTrue((cue.value as? String ?? "").hasPrefix("Cue \(n) of 5"), "cue \(n) value: \(cue.value ?? "nil")")
            XCTAssertEqual(cue.isSelected, n == 1, "only the active cue is selected (ACC-004-R2)")
        }
        try audit("showEditor")

        app.navigationBars["Show"].buttons.element(boundBy: 0).tap()   // back to Settings
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        showControls()
        app.buttons["settings"].tap()   // the second Settings of the launch: at its top
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        requireControls([("visual.projectM", .button)], screen: "settings")
        try audit("settings")
    }

    /// User-caused changes are announced (ACC-004-R5, R9): Next, Pause, Black out.
    func testUserChangesAreAnnounced() {
        launch(["-uitestDiagnostics"])
        let probe = app.staticTexts["announcementProbe"]
        XCTAssertTrue(probe.appears(within: 15))
        showControls()
        let current = app.staticTexts["currentPreset"]
        XCTAssertTrue(poll(10) { current.exists && current.label != "No preset" }, "a preset is showing")
        let before = current.label

        app.buttons["next"].tap()
        XCTAssertTrue(poll(5) { current.label != before }, "Next changed the preset")
        let shown = current.label
        XCTAssertTrue(poll(3) { (probe.value as? String) == "preset|Preset: \(shown)" }, "probe: \(probe.value ?? "nil")")

        app.buttons["pauseResume"].tap()
        XCTAssertTrue(poll(3) { (probe.value as? String) == "playback|Visualization paused" }, "probe: \(probe.value ?? "nil")")
        app.buttons["pauseResume"].tap()
        XCTAssertTrue(poll(3) { (probe.value as? String) == "playback|Visualization resumed" }, "probe: \(probe.value ?? "nil")")

        app.buttons["blackout"].tap()
        XCTAssertTrue(poll(3) { (probe.value as? String) == "output|Output blacked out" }, "probe: \(probe.value ?? "nil")")
    }
}
