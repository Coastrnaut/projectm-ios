// PrimaryScreensAccessibilityUITests.swift — QA-009 (specs/177-qa-009-accessibility-suite; QA-009-R2-R7,
// contract M2-M5): every primary screen of `PrimaryScreens.all`, at each layout, in portrait.
// For each required control, in manifest order: it exists, its label is non-empty and is not its identifier,
// and it lies wholly in the visible area and can be hit after at most one scroll (one held drag of at most 70 %
// of the visible area, research D3). Then the system audit passes with the existing documented filters only:
// ACC-004's types and filters at the default size, ACC-006's types (plus element description and traits) and
// filters at AX3 and AX5 (research D2). Failures read "[screen @ layout] control: what failed".
// Default run: standard and AX5. `TEST_RUNNER_QA009_FULL=1` adds AX3 (research D4).
// Owner rule 7: one screen and layout per test, each under 30 s. Simulator results are UI evidence only
// (Constitution X); the device walk is QA-009-T10 {device}.
import XCTest

@MainActor
final class PrimaryScreensAccessibilityUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private var problems: [String] = []

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Run

    private func run(_ name: String, _ layout: PrimaryLayout) throws {
        let full: Bool = ProcessInfo.processInfo.environment["QA009_FULL"].map { (v: String) -> Bool in !v.isEmpty && v != "0" } ?? false
        try XCTSkipUnless(layout.inDefaultRun || full, "AX3 runs with QA009_FULL=1 (QA-009 research D4)")
        let screen: PrimaryScreen = PrimaryScreens.screen(name)
        let tag = "[\(screen.name) @ \(layout.rawValue)]"
        launch(screen, layout)
        guard open(screen, tag: tag) else { return }
        var overlay = false
        if case .controls = screen.route { overlay = true }
        // The controls over a blacked-out output, a stable background (ACC-004 C3), for the walk too: over the
        // moving picture every query waited for the app to idle (about 1 s per control, 2026-11-14).
        for control in screen.controls where control.live { check(control, tag: tag, overlay: overlay) }
        if overlay { blackOut(tag: tag) }
        for control in screen.controls where !control.live { check(control, tag: tag, overlay: overlay) }
        if layout != .standard || screen.auditsAtStandardSize { try audit(screen, layout, tag: tag) }
        if !problems.isEmpty {
            attachScreenshot("qa009-\(screen.name)-\(layout.rawValue)")
            XCTFail(problems.joined(separator: "\n"))
        }
    }

    private func launch(_ screen: PrimaryScreen, _ layout: PrimaryLayout) {
        XCUIDevice.shared.orientation = .portrait
        let base: [String] = ["-uitestResetNotice", "-uitestKeepControls", "-autostart", "inAppPlayback",
                              "-UIPreferredContentSizeCategoryName", layout.category]
        app.launchArguments = base + screen.launch + Self.noStore
        app.launch()
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Opening a screen (navigation only; not part of the checks)

    private var controlsOverlay: XCUIElement { app.otherElements["controls"] }

    private func showControls(tag: String) -> Bool {
        let area = app.otherElements["visualizerTapArea"].firstMatch
        guard area.appears(within: 15) else { return fail(tag, "the visualizer did not come up") }
        // Below the middle: at AX5 a notice at the top can cover the centre (ACC-006).
        if !controlsOverlay.exists { area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap() }
        return controlsOverlay.appears(within: 3) || fail(tag, "the controls did not show")
    }

    /// Taps a control of the overlay, scrolling the overlay first when it is out of view (AX5).
    private func tapOverlayButton(_ id: String, tag: String) -> Bool {
        let button = app.buttons[id]
        guard button.appears(within: 5) else { return fail(tag, "navigation: \(id) missing") }
        bringIntoView(id)
        button.tap()
        return true
    }

    private func openSettings(tag: String) -> Bool {
        guard showControls(tag: tag), tapOverlayButton("settings", tag: tag) else { return false }
        return app.navigationBars["Settings"].appears(within: 5) || fail(tag, "Settings did not open")
    }

    private func open(_ screen: PrimaryScreen, tag: String) -> Bool {
        switch screen.route {
        case .controls:
            guard showControls(tag: tag) else { return false }
            // A projectM preset is showing (its controls are complete).
            return poll(10) { self.app.buttons["duplicateCurrent"].exists } || fail(tag, "no preset is showing")
        case .settings:
            return openSettings(tag: tag)
        case let .settingsLink(id, title):
            guard openSettings(tag: tag) else { return false }
            let link = app.buttons[id]
            guard app.reveal(link) else { return fail(tag, "navigation: the \(id) row was not reached") }
            link.tap()
            return app.navigationBars[title].appears(within: 10) || fail(tag, "\(title) did not open")
        case .presetBrowser:
            guard showControls(tag: tag), tapOverlayButton("presets", tag: tag) else { return false }
            return app.buttons["node:included"].appears(within: 10) || fail(tag, "the library home did not open")
        case .sceneSwitcher:
            // Over a blacked-out output, as ACC-004 audits the controls: the card's translucent surface over the moving
            // picture drew contrast failures without an element that came and went from run to run.
            guard showControls(tag: tag) else { return false }
            blackOut(tag: tag)
            // Then the controls are hidden, as they are once their auto-hide runs (`-uitestKeepControls` keeps them up):
            // dimmed behind the switcher's backdrop, their texts were sampled as failing contrast.
            app.otherElements["visualizerTapArea"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            _ = controlsOverlay.disappears(within: 3)
            app.typeKey("k", modifierFlags: .command)
            return app.descendants(matching: .any)["sceneSwitcherField"].firstMatch.appears(within: 5)
                || fail(tag, "⌘K did not open the switcher")
        case .parameterInspector:
            guard showControls(tag: tag), tapOverlayButton("settings", tag: tag) else { return false }
            return app.buttons["parameterInspector.done"].appears(within: 15) || fail(tag, "the inspector did not open")
        }
    }

    /// Records a navigation failure (the screen's checks cannot run) and fails the test at once.
    private func fail(_ tag: String, _ message: String) -> Bool {
        attachScreenshot("qa009-navigation")
        XCTFail("\(tag) \(message)")
        return false
    }

    // MARK: - Required controls (contract M2)

    /// Each control is read from one snapshot of the app's tree (frame, label, the bars and the overlay's scroll
    /// view): reading them one query at a time cost 1-8 s per control (`navigationBars.count` alone took 7.8 s
    /// under Settings at AX5, 2026-11-14). Only `isHittable` is asked of the live element.
    /// At most `control.scrolls` gestures (1 unless the manifest says otherwise) bring it into the tree and
    /// wholly into view; a vertical gesture for a list, a horizontal one for a row that scrolls sideways (the
    /// shelf's strip at standard sizes).
    private func check(_ control: RequiredControl, tag: String, overlay: Bool) {
        let prefix = "\(tag) \(control.id):"
        var tree = ScreenTree(app, live: { () -> XCUIElement in self.app.descendants(matching: control.type)[control.id].firstMatch })
        if tree.find(control) == nil { _ = poll(2) { () -> Bool in tree = tree.refreshed(self.app); return tree.find(control) != nil } }
        var gestures = 0
        while gestures < control.scrolls {
            if let snapshot = tree.find(control), tree.visible(snapshot, bar: control.bar) { break }
            scroll(tree, towards: tree.find(control), overlay: overlay)
            gestures += 1
            tree = tree.refreshed(app)
        }
        let limit: String = control.scrolls == 1 ? "one scroll" : "\(control.scrolls) scrolls"
        guard let snapshot = tree.find(control) else {
            problems.append("\(prefix) not found (after \(limit)); nearby: \(tree.similar(control).joined(separator: ", "))")
            return
        }
        let label: String = snapshot.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty { problems.append("\(prefix) has no label") }
        else if label == control.id { problems.append("\(prefix) its label is its identifier") }
        guard tree.visible(snapshot, bar: control.bar) else {
            problems.append("\(prefix) not wholly visible after \(limit) (\(NSCoder.string(for: snapshot.frame)))")
            return
        }
        // Polled briefly: a sheet or card still fading in reports not hittable. A wrapper that carries the identifier
        // (ACC-005's accessible slider: an element around the system Slider) counts when the control inside it can be
        // hit: a touch there operates it.
        guard control.hitTest else { return }
        let element = app.descendants(matching: control.type)[control.id].firstMatch
        let inner = element.children(matching: .any).firstMatch
        // A text field that already holds the keyboard focus takes typed input without a touch (the scene switcher's
        // query: focused on open, UIX-002).
        let focused: () -> Bool = { () -> Bool in (element.value(forKey: "hasKeyboardFocus") as? Bool) == true }
        if !poll(2, { () -> Bool in element.isHittable || (inner.exists && inner.isHittable) || focused() }) {
            problems.append("\(prefix) cannot be hit")
        }
    }

    /// One held drag (no momentum), by what is missing plus 24 pt, at most 70 % of the visible area (research
    /// D3); 70 % along the list when the element is not in the tree yet. Vertical drags run in the right-hand
    /// lane; a row cut off at the side is dragged sideways along its own middle. In the visualizer's controls
    /// the drag runs in their scroll view.
    private func scroll(_ tree: ScreenTree, towards found: XCUIElementSnapshot?, overlay: Bool) {
        // A lazy row built but not laid out reports an empty frame at the origin: direction unknown, so down the list
        // as for a row not built yet (taken for "above", it sent the browser's list back to its top at AX5).
        let target: XCUIElementSnapshot? = found.flatMap { (s: XCUIElementSnapshot) -> XCUIElementSnapshot? in
            s.frame.isEmpty ? nil : s
        }
        let area: CGRect = target.map { (s: XCUIElementSnapshot) -> CGRect in tree.area(for: s, bar: false) }
            ?? tree.defaultArea(overlay: overlay)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        if let frame = target?.frame, frame.minY >= area.minY - 0.5, frame.maxY <= area.maxY + 0.5,
           frame.maxX > area.maxX + 0.5 || frame.minX < area.minX - 0.5 {
            let left: Bool = frame.maxX > area.maxX   // cut off at the right: drag the row to the left
            let needed: CGFloat = (left ? frame.maxX - area.maxX : area.minX - frame.minX) + 24
            let distance: CGFloat = min(max(needed + 16, 60), area.width * 0.7)
            let startX: CGFloat = left ? area.maxX - area.width * 0.1 : area.minX + area.width * 0.1
            let start = origin.withOffset(CGVector(dx: startX, dy: frame.midY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: left ? -distance : distance, dy: 0)),
                        withVelocity: .slow, thenHoldForDuration: 0.15)
            return
        }
        let span: CGFloat = max(area.height, 100)
        let towardsTop: Bool = target.map { (s: XCUIElementSnapshot) -> Bool in s.frame.minY < area.minY } ?? false   // above: drag down
        var needed: CGFloat = span * 0.7
        if let frame = target?.frame { needed = towardsTop ? area.minY - frame.minY + 24 : frame.maxY - area.maxY + 24 }
        // Plus the touch slop a drag spends before the list moves; at least 60 pt so the drag registers.
        let distance: CGFloat = min(max(needed + 16, 60), span * 0.7)
        let startY: CGFloat = towardsTop ? area.minY + span * 0.15 : area.maxY - span * 0.15
        // The right-hand lane of the scroll view that holds the target (the scene switcher's card is narrower than
        // the window), else of the area.
        let lane: CGRect = tree.scrollContainer(for: target?.frame) ?? area
        // At 0.88, not the shared `reveal`'s 0.96: on a long list the right margin catches the scroll indicator once it
        // shows, which scrubs the list (the preset browser at AX5 jumped back to its top, as LibraryEraseUITests saw).
        // In the visualizer's controls the 0.96 margin stays: there 0.88 lands on the grid's buttons, which took the drag.
        let inControls: Bool = target.map { (t: XCUIElementSnapshot) -> Bool in tree.inOverlay(t) } ?? overlay
        let fraction: CGFloat = inControls ? 0.96 : 0.88
        let start = origin.withOffset(CGVector(dx: lane.minX + lane.width * fraction, dy: startY))
        let end = start.withOffset(CGVector(dx: 0, dy: towardsTop ? distance : -distance))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
    }

    /// Opens a screen's way in: scrolls the overlay to a button that is out of view or not built yet (the
    /// controls' lazy grid at AX5), at most three times.
    private func bringIntoView(_ id: String) {
        let control = RequiredControl(id, .button)
        for _ in 0..<3 {
            let tree = ScreenTree(app)
            let snapshot: XCUIElementSnapshot? = tree.find(control)
            if let snapshot, tree.visible(snapshot, bar: false) { return }
            scroll(tree, towards: snapshot, overlay: true)
        }
    }

    // MARK: - Audit (research D2)

    private static let standardTypes: XCUIAccessibilityAuditType = [
        .sufficientElementDescription, .hitRegion, .contrast, .dynamicType, .trait,
    ]
    private static let largeTypes: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .sufficientElementDescription, .trait]

    /// ACC-004 screen keys; the other screens get only ACC-004's system Done filter (the sheets' Done).
    private static let acc004Keys: Set<String> = ["browser", "pack", "collections", "myPresets", "settings", "showEditor", "controls"]

    /// Per-element filters for system-drawn elements on screens new to the audit (contract M2; never the app's
    /// own content, never a whole type or screen).
    private static let qa009Filters: [AccessibilityScreensUITests.AuditFilter] = {
        typealias Filter = AccessibilityScreensUITests.AuditFilter
        let glass = "a system glass navigation-bar item; the audit samples the live visualization behind the sheet's "
            + "glass, as for ACC-004's system Done"
        let bar = "a navigation-bar item: iOS keeps bar items at a fixed size and shows them in the Large Content Viewer (ACC-006)"
        let footer = "the system section footer style (Apple's secondary grey), as ACC-004's Settings and Show footers"
        let header = "the system section header style, as ACC-004's \"Cues\" and \"Visual\" headers"
        let bottom = "the last row of a list at the bottom of the screen, pushed out of the visible list at the audit's larger "
            + "sizes (ACC-004's bottom-row artefact); the walk reaches it and its label wraps at AX5 (QA-009 screenshots)"
        // A list section's header or footer text, drawn by the system List style: both audit types it draws findings
        // for at the default size (Apple's secondary grey; a header pushed off the visible list at the audit's sizes).
        func section(_ screen: String, _ labels: [String], prefixes: [String] = []) -> [Filter] {
            let reason = "a system list section header or footer (" + header + "; " + footer + ")"
            var list: [Filter] = []
            for type in [XCUIAccessibilityAuditType.contrast, .dynamicType] {
                list += labels.map { (l: String) -> Filter in Filter(screen: screen, type: type, element: l, reason: reason) }
                list += prefixes.map { (p: String) -> Filter in Filter(screen: screen, type: type, element: p, labelPrefix: true, reason: reason) }
            }
            return list
        }
        let inspectorRows = "the inspector's label-and-value rows (ViewThatFits: side by side, stacked when the text grows) "
            + "re-lay out while the audit changes the text size; the AX5 audit of the inspector, Dynamic Type included, "
            + "passes (QA-009 run 2026-11-14)"
        return section("effectOrder", ["Presets"], prefixes: ["Effects run from top to bottom"])
            + section("midiMappings", ["Mappings", "Transport", "Scene triggers"],
                      prefixes: ["Learn waits up to 30 seconds", "Assign MIDI", "Program number"])
            + section("licenses", ["This app", "Visualization engine", "ANGLE (Metal renderer)", "Presets", "Assets", "Preset packs"])
            + section("parameterInspector", ["Parameter", "Details", "Value", "Modulation"], prefixes: ["Audio bindings and MIDI"])
            + section("storage", [], prefixes: ["The space this app's own data takes", "Removes leftover recordings"])
            + ["Name", "Group", "ID", "Unit", "Range", "Step", "Default", "Value", "Effective value"].map { (l: String) -> Filter in
                Filter(screen: "parameterInspector", type: .dynamicType, element: l, reason: inspectorRows)
            }
            // The same rows' value texts ("1%", "50%", "Percent"): they change with the parameter, so they are matched
            // by the row's value strings for the inspected parameter (Glow intensity, the manifest's seed).
            + ["Glow", "Intensity", "Percent", "0% … 100%", "0%…100%", "1%", "50%", "effect.bloom.intensity"].map { (l: String) -> Filter in
                Filter(screen: "parameterInspector", type: .dynamicType, element: l, reason: inspectorRows)
            } + [
            Filter(screen: "storage", type: .dynamicType, element: "storageRefresh", reason: bar),
        ] + ["Collections", "My Presets", "0", "Recently Played"].map { (l: String) -> Filter in
            // ACC-004's bottom rows (its `bottomRows` filter), reported at AX3 too when they sit at the screen's foot.
            Filter(screen: "browser", type: .dynamicType, element: l, reason: bottom)
        } + [
            Filter(screen: "browser", type: .dynamicType, element: "", elementless: true, limit: 2,
                   reason: "the same bottom rows reported without an element (AX3); bounded to two"),
            Filter(screen: "midiMappings", type: .textClipped, element: "", elementless: true, limit: 3,
                   reason: "a text cut by the top or bottom edge of the screen, reported without an element (AX3; the AX3 "
                       + "screenshot shows no clipped text); bounded to three"),
            Filter(screen: "settingsRecording", type: .textClipped, element: "", elementless: true, limit: 3,
                   reason: "the recording sections' long footer cut by the bottom edge of the screen, reported without an "
                       + "element (AX3; the screenshot shows no clipped text); bounded to three"),
            Filter(screen: "parameterInspector", type: .dynamicType, element: "parameterInspector.reset", reason: bottom),
            Filter(screen: "sceneSwitcher", type: .contrast, element: "", elementless: true, limit: 6,
                   reason: "the rows' preview placeholders (five) and the current row's play mark: decorative images hidden "
                       + "from accessibility (QA-009), which the audit still samples and reports as bare SwiftUI nodes with "
                       + "no element (grey symbol on the dark thumbnail); bounded to six, one per hidden image"),
            Filter(screen: "sceneSwitcher", type: .contrast, element: "Visual unavailable",
                   reason: "PERF-014's placeholder behind the switcher, caught while fading or behind the live visual "
                       + "(ACC-004's filter for the controls; at full opacity its grey on black is about 6:1)"),
            Filter(screen: "midiMappings", type: .contrast, element: "midiMappingsUndo",
                   reason: "disabled until there is something to undo (an inactive control is exempt from contrast, "
                       + "WCAG 1.4.3); " + glass),
            Filter(screen: "effectOrder", type: .dynamicType, element: "effectChain.savePreset", reason: bottom),
            Filter(screen: "effectOrder", type: .dynamicType, element: "effectChain.edit", reason: bar),
            Filter(screen: "licenses", type: .contrast, element: "", elementless: true, limit: 6,
                   reason: "the section headers (\"This app\", the groups) reported without an element; " + header + "; bounded"),
            Filter(screen: "effectOrder", type: .dynamicType, element: "", elementless: true, limit: 1,
                   reason: "Save current as preset, the last row, reported without an element; " + bottom),
            Filter(screen: "midiMappings", type: .dynamicType, element: "midiMappingsUndo", reason: bar),
            Filter(screen: "parameterInspector", type: .contrast, element: "", elementless: true, limit: 5,
                   reason: "the inspector's section headers and footer (Value, Modulation) reported without an element; "
                       + footer + "; bounded"),
            Filter(screen: "storage", type: .contrast, element: "storageRefresh", reason: glass),
            Filter(screen: "storage", type: .contrast, element: "", elementless: true, limit: 4,
                   reason: "Storage's section headers and footers reported without an element; " + footer + "; bounded"),
            Filter(screen: "licenses", type: .textClipped, element: "", elementless: true, limit: 1,
                   reason: "a row cut by the bottom edge of the screen (ANGLE's section at AX5, reported without an element); "
                       + "bounded to one, so a new one fails"),
            Filter(screen: "parameterInspector", type: .contrast, element: "parameterInspector.done", reason: glass),
            Filter(screen: "parameterInspector", type: .contrast, element: "parameterInspector.pin", reason: glass),
            Filter(screen: "parameterInspector", type: .dynamicType, element: "parameterInspector.done", reason: bar),
            Filter(screen: "parameterInspector", type: .dynamicType, element: "parameterInspector.pin", reason: bar),
        ]
    }()

    private struct Rule {
        let limit: Int
        let matches: (String, XCUIAccessibilityAuditType, String, String, Bool) -> Bool
    }

    private static func rules(_ layout: PrimaryLayout, key: String) -> [Rule] {
        if layout == .standard {
            var filters = AccessibilityScreensUITests.filters
            if !acc004Keys.contains(key) { filters += AccessibilityScreensUITests.systemDone(key) }
            filters += qa009Filters
            return filters.map { (f: AccessibilityScreensUITests.AuditFilter) -> Rule in
                Rule(limit: f.limit, matches: f.matches(screen:type:identifier:label:hasElement:))
            }
        }
        return DynamicTypeInspectorUITests.filters.map { (f: DynamicTypeInspectorUITests.AuditFilter) -> Rule in
            Rule(limit: f.limit, matches: f.matches(screen:type:identifier:label:hasElement:))
        } + qa009Filters.map { (f: AccessibilityScreensUITests.AuditFilter) -> Rule in
            Rule(limit: f.limit, matches: f.matches(screen:type:identifier:label:hasElement:))
        }
    }

    private static func name(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .sufficientElementDescription: "sufficientElementDescription"
        case .hitRegion: "hitRegion"
        case .contrast: "contrast"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "type(\(type.rawValue))"
        }
    }

    private func audit(_ screen: PrimaryScreen, _ layout: PrimaryLayout, tag: String) throws {
        let rules: [Rule] = Self.rules(layout, key: screen.auditKey)
        let types: XCUIAccessibilityAuditType = layout == .standard ? Self.standardTypes : Self.largeTypes
        var used: [Int: Int] = [:]
        var found: [String] = []
        try app.performAccessibilityAudit(for: types) { (issue: XCUIAccessibilityAuditIssue) -> Bool in
            // One snapshot per issue (ACC-004: reading a stale element's properties one by one is slow).
            let snapshot: XCUIElementSnapshot? = try? issue.element?.snapshot()
            let identifier: String = snapshot?.identifier ?? ""
            let label: String = snapshot?.label ?? ""
            let index: Int? = rules.indices.first { (i: Int) -> Bool in
                used[i, default: 0] < rules[i].limit
                    && rules[i].matches(screen.auditKey, issue.auditType, identifier, label, snapshot != nil)
            }
            if let index {
                used[index, default: 0] += 1
            } else {
                let frame: String = snapshot.map { (s: XCUIElementSnapshot) -> String in NSCoder.string(for: s.frame) } ?? "-"
                let head: String = "\(tag) audit: \(Self.name(issue.auditType)) id=\"\(identifier)\" label=\"\(label)\" frame=\(frame): "
                found.append(head + issue.compactDescription + " | " + issue.detailedDescription)
            }
            return true
        }
        problems += found
    }

    /// The controls are audited over a blacked-out output, a stable background (ACC-004 C3).
    private func blackOut(tag: String) {
        bringIntoView("blackout")
        app.buttons["blackout"].tap()
        if !app.descendants(matching: .any)["blackoutBadge"].firstMatch.appears(within: 8) {
            problems.append("\(tag) navigation: the output did not black out before the audit")
        }
    }

    // MARK: - Tests (QA-009-R6: standard and AX5 by default, AX3 with QA009_FULL=1)

    func testControlsStandard() throws { try run("controls", .standard) }
    func testControlsAX3() throws { try run("controls", .ax3) }
    func testControlsAX5() throws { try run("controls", .ax5) }
    func testParameterShelfStandard() throws { try run("parameterShelf", .standard) }
    func testParameterShelfAX3() throws { try run("parameterShelf", .ax3) }
    func testParameterShelfAX5() throws { try run("parameterShelf", .ax5) }
    func testSettingsStandard() throws { try run("settings", .standard) }
    func testSettingsAX3() throws { try run("settings", .ax3) }
    func testSettingsAX5() throws { try run("settings", .ax5) }
    func testPresetBrowserStandard() throws { try run("presetBrowser", .standard) }
    func testPresetBrowserAX3() throws { try run("presetBrowser", .ax3) }
    func testPresetBrowserAX5() throws { try run("presetBrowser", .ax5) }
    func testSceneSwitcherStandard() throws { try run("sceneSwitcher", .standard) }
    func testSceneSwitcherAX3() throws { try run("sceneSwitcher", .ax3) }
    func testSceneSwitcherAX5() throws { try run("sceneSwitcher", .ax5) }
    func testShowEditorStandard() throws { try run("showEditor", .standard) }
    func testShowEditorAX3() throws { try run("showEditor", .ax3) }
    func testShowEditorAX5() throws { try run("showEditor", .ax5) }
    func testMIDIMappingsStandard() throws { try run("midiMappings", .standard) }
    func testMIDIMappingsAX3() throws { try run("midiMappings", .ax3) }
    func testMIDIMappingsAX5() throws { try run("midiMappings", .ax5) }
    func testStorageStandard() throws { try run("storage", .standard) }
    func testStorageAX3() throws { try run("storage", .ax3) }
    func testStorageAX5() throws { try run("storage", .ax5) }
    func testLicensesStandard() throws { try run("licenses", .standard) }
    func testLicensesAX3() throws { try run("licenses", .ax3) }
    func testLicensesAX5() throws { try run("licenses", .ax5) }
    func testParameterInspectorStandard() throws { try run("parameterInspector", .standard) }
    func testParameterInspectorAX3() throws { try run("parameterInspector", .ax3) }
    func testParameterInspectorAX5() throws { try run("parameterInspector", .ax5) }
    func testEffectOrderStandard() throws { try run("effectOrder", .standard) }
    func testEffectOrderAX3() throws { try run("effectOrder", .ax3) }
    func testEffectOrderAX5() throws { try run("effectOrder", .ax5) }
    func testRecordingQualityStandard() throws { try run("recordingQuality", .standard) }
    func testRecordingQualityAX3() throws { try run("recordingQuality", .ax3) }
    func testRecordingQualityAX5() throws { try run("recordingQuality", .ax5) }
    func testRecordingFrameRateStandard() throws { try run("recordingFrameRate", .standard) }
    func testRecordingFrameRateAX3() throws { try run("recordingFrameRate", .ax3) }
    func testRecordingFrameRateAX5() throws { try run("recordingFrameRate", .ax5) }
}

/// One snapshot of the app's accessibility tree, with the visible area a list's rows show in (QA-009 research D3):
/// below the lowest navigation bar at the top, above a search field floating at the bottom (the preset
/// browser's), and inside the overlay's scroll view for the visualizer's controls (only for an element inside
/// the `controls` overlay, with no sheet or card's bar over it).
@MainActor
struct ScreenTree {
    private let root: XCUIElementSnapshot?
    let window: CGRect
    private var bars: [CGRect] = []
    private var searchFields: [CGRect] = []
    private var scrollers: [CGRect] = []
    private var overlay: XCUIElementSnapshot?
    private var overlayScroll: CGRect?
    /// The control's live element, asked only when the app snapshot does not reach it: a deep element (the
    /// parameter inspector's slider, a row deep in the browser's list) can lie below the snapshot's depth limit.
    private let live: (@MainActor () -> XCUIElement)?

    init(_ app: XCUIApplication, live: (@MainActor () -> XCUIElement)? = nil) {
        root = try? app.snapshot()
        window = root?.frame ?? .zero
        self.live = live
        if let root { collect(root, scroll: nil) }
    }

    func refreshed(_ app: XCUIApplication) -> ScreenTree { ScreenTree(app, live: live) }

    private mutating func collect(_ node: XCUIElementSnapshot, scroll: CGRect?) {
        switch node.elementType {
        case .navigationBar: bars.append(node.frame)
        case .searchField: searchFields.append(node.frame)
        case .scrollView, .collectionView, .table: scrollers.append(node.frame)
        default: break
        }
        if node.identifier == "controls", overlay == nil {
            overlay = node
            overlayScroll = scroll
        }
        let inner: CGRect? = node.elementType == .scrollView ? node.frame : scroll
        for child in node.children { collect(child, scroll: inner) }
    }

    private static func first(_ control: RequiredControl, in root: XCUIElementSnapshot) -> XCUIElementSnapshot? {
        var stack: [XCUIElementSnapshot] = [root]
        while let node = stack.popLast() {
            if node.identifier == control.id && (control.type == .any || node.elementType == control.type) { return node }
            stack.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    /// The first element in tree order with the control's identifier and type (`.any` matches every type).
    func find(_ control: RequiredControl) -> XCUIElementSnapshot? {
        if let found = root.flatMap({ (r: XCUIElementSnapshot) -> XCUIElementSnapshot? in Self.first(control, in: r) }) { return found }
        guard let element = live?(), element.exists else { return nil }
        return try? element.snapshot()
    }

    /// Identifiers sharing the control's prefix (up to its first "." or ":"), with frames: failure context.
    func similar(_ control: RequiredControl) -> [String] {
        guard let root else { return ["no snapshot"] }
        let stem: Substring = control.id.split(whereSeparator: { (c: Character) -> Bool in c == "." || c == ":" }).first ?? Substring(control.id)
        var found: [String] = []
        var stack: [XCUIElementSnapshot] = [root]
        while let node = stack.popLast(), found.count < 6 {
            if node.identifier.hasPrefix(stem) { found.append("\(node.identifier)@\(Int(node.frame.minY))") }
            stack.append(contentsOf: node.children.reversed())
        }
        return found
    }

    /// The overlay's scroll area when `element` is inside the visualizer's controls and nothing with a bar covers them.
    private func overlayArea(_ element: XCUIElementSnapshot?) -> CGRect? {
        guard bars.isEmpty, let overlay else { return nil }
        if let element {
            guard Self.contains(overlay, element) else { return nil }
        }
        return overlayScroll.map { (s: CGRect) -> CGRect in window.intersection(s) } ?? window
    }

    private static func contains(_ root: XCUIElementSnapshot, _ element: XCUIElementSnapshot) -> Bool {
        var stack: [XCUIElementSnapshot] = [root]
        while let node = stack.popLast() {
            if node.identifier == element.identifier && node.elementType == element.elementType && node.frame == element.frame { return true }
            stack.append(contentsOf: node.children)
        }
        return false
    }

    /// The narrowest scroll view (or list) around `frame`, or around the window's centre for a target not built yet.
    func scrollContainer(for frame: CGRect?) -> CGRect? {
        let point = CGPoint(x: frame?.midX ?? window.midX, y: frame?.midY ?? window.midY)
        return scrollers.filter { (r: CGRect) -> Bool in r.contains(point) && r.width > 100 }
            .min { (a: CGRect, b: CGRect) -> Bool in a.width < b.width }
    }

    /// True when the element sits in the visualizer's controls (no sheet over them).
    func inOverlay(_ element: XCUIElementSnapshot) -> Bool { overlayArea(element) != nil }

    /// Where a list's rows show: the overlay's scroll area for its controls, else below the bars and above a
    /// bottom search field.
    func area(for element: XCUIElementSnapshot, bar: Bool) -> CGRect {
        if let overlayArea = overlayArea(element) { return overlayArea }
        if bar { return window }
        return listArea()
    }

    /// The area to scroll when the target is not in the tree yet.
    func defaultArea(overlay: Bool) -> CGRect {
        if overlay, let overlayArea = overlayArea(nil) { return overlayArea }
        return listArea()
    }

    private func listArea() -> CGRect {
        var top: CGFloat = window.minY
        for barFrame in bars where barFrame.minY < window.minY + 200 { top = max(top, barFrame.maxY) }
        var bottom: CGFloat = window.maxY
        for field in searchFields where field.minY > window.midY { bottom = min(bottom, field.minY) }
        return CGRect(x: window.minX, y: top, width: window.width, height: max(0, bottom - top))
    }

    /// Wholly inside the visible area (an element taller than the area need only overlap it vertically).
    func visible(_ element: XCUIElementSnapshot, bar: Bool) -> Bool {
        let frame: CGRect = element.frame
        let area: CGRect = self.area(for: element, bar: bar)
        guard frame.height > 0, area.height > 0 else { return false }
        // Within 4 pt: the visualizer's controls end 2 pt past their scroll view's frame at AX5 (rounding of the
        // scaled grid inside its backing); a touch there still lands on the control.
        let slack: CGFloat = 4
        let horizontal: Bool = frame.minX >= area.minX - slack && frame.maxX <= area.maxX + slack
        if frame.height > area.height { return horizontal && frame.intersects(area) }
        return horizontal && frame.minY >= area.minY - slack && frame.maxY <= area.maxY + slack
    }
}
