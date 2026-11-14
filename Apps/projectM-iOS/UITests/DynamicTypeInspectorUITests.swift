// DynamicTypeInspectorUITests.swift — ACC-006 (specs/087-acc-006-dynamic-type-inspector): the
// Dynamic Type inspector. For each core screen, at the largest accessibility size (AX5,
// `UICTContentSizeCategoryAccessibilityXXXL`) and at a middle one (AX3,
// `UICTContentSizeCategoryAccessibilityXL`), it:
// (a) runs the system audit for Dynamic Type and clipped text, failing on any issue not matched by a
//     documented per-element filter (contract C2 of this feature);
// (b) checks the screen's affordances: scrolling reaches its last control, that control can be hit,
//     and text fields accept typed input (ACC-006-R2 to R4).
// Survey mode (ACC-006-R6): `TEST_RUNNER_ACC006_SIZE=<content size category name>` runs every test at
// that size instead (AX1-AX5, or `UICTContentSizeCategoryXXXL`, the largest standard size), so the whole
// walk can be repeated at any size without editing the suite.
// Simulator results are never device evidence; the device pass is ACC-006-T12 {device}.
// Owner rule 7: each test < 30 s (one screen group per test); UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class DynamicTypeInspectorUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        // Survey runs (`TEST_RUNNER_ACC006_SURVEY=1`) keep going to list every issue of a screen group.
        continueAfterFailure = ProcessInfo.processInfo.environment["ACC006_SURVEY"] != nil
    }

    // MARK: - Sizes

    static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"
    static let ax3 = "UICTContentSizeCategoryAccessibilityXL"

    /// The size a test runs at: the survey override when set, else the test's own.
    private func size(_ own: String) -> String {
        ProcessInfo.processInfo.environment["ACC006_SIZE"].flatMap { (value: String) -> String? in value.isEmpty ? nil : value } ?? own
    }

    // MARK: - Audit filters (contract C2)

    /// One filtered audit issue: screen, audit type, element identifier (or whole label when the element
    /// has none, or a label prefix), and why it is not the app's to fix. Never a whole type or screen.
    struct AuditFilter: Sendable {
        let screen: String
        let type: XCUIAccessibilityAuditType
        let element: String
        var labelPrefix = false
        /// Matches an issue the audit reports without an element (system alerts report one).
        var elementless = false
        /// At most this many matches per audit, so a new issue of the same shape still fails.
        var limit = Int.max
        let reason: String

        func matches(screen: String, type: XCUIAccessibilityAuditType, identifier: String, label: String, hasElement: Bool) -> Bool {
            guard self.screen == screen || self.screen == "*", self.type == type else { return false }
            if elementless { return !hasElement }
            guard hasElement else { return false }
            if !identifier.isEmpty && identifier == element { return true }
            guard identifier.isEmpty || identifier == label else { return false }
            return labelPrefix ? label.hasPrefix(element) : label == element
        }
    }

    /// System-drawn elements only (contract C2 outcome); nothing the app lays out itself.
    static let filters: [AuditFilter] = {
        let bar = "a navigation-bar item: iOS keeps bar items at a fixed size at every text size and shows them "
            + "in the Large Content Viewer on long press"
        var list: [AuditFilter] = [
            AuditFilter(screen: "*", type: .dynamicType, element: "Done", reason: "the sheets' system Done; " + bar),
            AuditFilter(screen: "storage", type: .dynamicType, element: "storageRefresh", reason: "Storage's Refresh toolbar button; " + bar),
            AuditFilter(screen: "presetEditor", type: .dynamicType, element: "presetEditorCancel", reason: "the editor's Cancel; " + bar),
            AuditFilter(screen: "presetEditor", type: .dynamicType, element: "presetEditorSave", reason: "the editor's Save; " + bar),
        ]
        // System alerts (UIAlertController via SwiftUI `.alert`): iOS lays out their title, message and
        // field; at AX5 the alert scrolls its content, which the audit reports as partly unsupported.
        let alert = "a system alert laid out by iOS; at accessibility sizes its content scrolls (the suite types into its field)"
        list.append(AuditFilter(screen: "renameSceneAlert", type: .dynamicType, element: "Rename Scene", reason: "the alert title; " + alert))
        list.append(AuditFilter(screen: "renameSceneAlert", type: .dynamicType, element: "", elementless: true,
                                reason: "the alert body; " + alert))
        // Settings' Undo and Redo bar glyphs (SCN-010), enabled once a visual row changed the scene: the
        // audit reports their fixed-size symbols without an element (two buttons: at most two per type).
        // They are navigation-bar items and show the Large Content Viewer on long press (ACC-006).
        // Not attributed (open item, contract C2): 1 to 7 Dynamic Type and clipped-text issues without an
        // element (the count varies run to run) appear only once a native visual's rows are shown (Undo enabled, glow sliders whose
        // visible title/value row is hidden from accessibility because VoiceOver reads the slider). The
        // audit names no element and the AX5 screenshots show no clipped text. Bounded per audit.
        let unnamed = "unattributed element-less findings on the native visuals' Settings rows (Undo/Redo bar glyphs and "
            + "the glow sliders' accessibility-hidden title rows are the only unnamed candidates); bounded, so a new one fails"
        // The Glow toggle (a system Toggle) when it sits at the top edge of the scrolled list: the audit's
        // larger sizes push it out of the visible list (ACC-004's Glow filter, same artefact; seen at AX3).
        let glow = "the system Glow Toggle at the edge of the scrolled list is pushed out of view at the audit's larger "
            + "sizes (ACC-004's Glow filter); its label scales"
        for screen in ["settingsLinear", "settingsOscilloscope", "settingsText"] {
            list.append(AuditFilter(screen: screen, type: .dynamicType, element: "", elementless: true, limit: 8, reason: unnamed))
            list.append(AuditFilter(screen: screen, type: .textClipped, element: "", elementless: true, limit: 8, reason: unnamed))
            list.append(AuditFilter(screen: screen, type: .dynamicType, element: "Glow", reason: glow))
            list.append(AuditFilter(screen: screen, type: .textClipped, element: "Glow", reason: glow))
        }
        list.append(AuditFilter(screen: "showEditor", type: .dynamicType, element: "Cues",
                                reason: "the system section header (`Section(\"Cues\")`), pushed below the visible list at the audit's "
                                    + "larger sizes when the editor starts at AX3 (the ACC-004 bottom-row artefact); not reported at AX5"))
        list.append(AuditFilter(screen: "renameSceneAlert", type: .dynamicType, element: "Every cue that shows this scene", labelPrefix: true,
                                reason: "the alert message; " + alert))
        return list
    }()

    private static let auditTypes: XCUIAccessibilityAuditType = [.dynamicType, .textClipped]

    private static func name(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        default: "type(\(type.rawValue))"
        }
    }

    /// Runs the audit on what is on screen; every unfiltered issue is listed in one failure. A
    /// screenshot of the screen is kept either way (the audit record, research ACC-006-D4).
    private func audit(_ screen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        var unfiltered: [String] = []
        var used: [Int: Int] = [:]
        try app.performAccessibilityAudit(for: Self.auditTypes) { (issue: XCUIAccessibilityAuditIssue) -> Bool in
            // One snapshot per issue (ACC-004: reading a stale element's properties one by one is slow).
            let snapshot: XCUIElementSnapshot? = try? issue.element?.snapshot()
            let identifier = snapshot?.identifier ?? ""
            let label = snapshot?.label ?? ""
            var filtered = false
            for (index, filter) in Self.filters.enumerated()
            where filter.matches(screen: screen, type: issue.auditType, identifier: identifier, label: label, hasElement: snapshot != nil)
                && used[index, default: 0] < filter.limit {
                used[index, default: 0] += 1
                filtered = true
                break
            }
            if !filtered {
                let frame: String = snapshot.map { (s: XCUIElementSnapshot) -> String in NSCoder.string(for: s.frame) } ?? "-"
                let typeName: String = Self.name(issue.auditType)
                let entry: String = "[\(screen)] \(typeName) id=\"\(identifier)\" label=\"\(label)\" frame=\(frame): "
                unfiltered.append(entry + issue.compactDescription + " | " + issue.detailedDescription)
            }
            return true
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "dynamic-type-\(screen)"
        shot.lifetime = unfiltered.isEmpty ? .deleteOnSuccess : .keepAlways
        add(shot)
        XCTAssertTrue(unfiltered.isEmpty, "unfiltered audit issues:\n" + unfiltered.joined(separator: "\n"), file: file, line: line)
    }

    // MARK: - Affordance checks

    /// The element sits wholly inside the window and can be hit (not clipped off screen).
    private func requireOnScreen(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, "\(what) exists", file: file, line: line)
        let frame = element.frame, window = app.windows.firstMatch.frame
        XCTAssertTrue(frame.minX >= window.minX - 0.5 && frame.maxX <= window.maxX + 0.5
                      && frame.minY >= window.minY - 0.5 && frame.maxY <= window.maxY + 0.5,
                      "\(what) is inside the window: \(NSCoder.string(for: frame)) in \(NSCoder.string(for: window))",
                      file: file, line: line)
        XCTAssertTrue(element.isHittable, "\(what) can be hit", file: file, line: line)
    }

    /// Scrolls until `element` is wholly visible (inside the window, below a navigation bar) and can be
    /// hit. While the element is not in the tree (lazy lists), long drags without momentum; once it
    /// exists, drags by what is missing. The drags run inside the controls' scroll view when
    /// the element is in it (a drag that starts on the scrubber would seek instead of scroll).
    @discardableResult
    private func scrollTo(_ element: XCUIElement, down: Bool = false) -> Bool {
        let window = app.windows.firstMatch
        // Below a compact navigation bar. A large title grows the bar when a list returns to its top,
        // so the bar counts at most up to 130 pt; otherwise drags would oscillate around a row.
        func top() -> CGFloat {
            let bar = app.navigationBars.firstMatch
            return bar.exists ? min(bar.frame.maxY, window.frame.minY + 130) : window.frame.minY
        }
        let controlsScroll = app.scrollViews.containing(.other, identifier: "controls").firstMatch
        let controlsContent = app.otherElements["controls"]
        // Frames only: `isHittable` fails the test outright for an element caught mid-scroll ("activation
        // point invalid"), so the callers check it once the scrolling has stopped.
        func visible() -> Bool {
            guard element.exists else { return false }
            let frame = element.frame
            var area = window.frame
            area.origin.y = top()
            area.size.height = window.frame.maxY - top()
            // Inside the visualizer controls' scroll view: its own frame is the visible part.
            if controlsScroll.exists, controlsContent.exists, controlsContent.frame.contains(frame) {
                area = area.intersection(controlsScroll.frame)
            }
            guard frame.height > 0, !area.isNull else { return false }
            if frame.height > area.height { return frame.intersects(area) }   // taller than the visible area
            return frame.minY >= area.minY - 0.5 && frame.maxY <= area.maxY + 0.5
        }
        var dragDown = down
        var blind = 0
        for _ in 0..<32 where !visible() {
            let known = element.exists && element.frame.height > 0
            // Inside the visualizer controls' scroll view when it is on screen (not under a sheet).
            let inControls = controlsScroll.exists && !app.navigationBars.firstMatch.exists
            if !known && !inControls {
                // Not in the tree yet (a lazy row): long drags held at the end (no momentum, so no row is
                // skipped). After sixteen without finding it (Settings at AX5 is about a dozen screens), the
                // other way: it is above.
                if blind == 16 { dragDown.toggle() }
                blind += 1
                // Up: from 0.8 (lower starts land on sheets' bottom bars and do not scroll).
                let high = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dragDown ? 0.4 : 0.2))
                let low = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dragDown ? 0.75 : 0.8))
                let (from, to) = dragDown ? (high, low) : (low, high)
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0.1)
                continue
            }
            let area: XCUIElement = inControls ? controlsScroll : window
            let upper: CGFloat = inControls ? controlsScroll.frame.minY : top()
            let lower: CGFloat = inControls ? controlsScroll.frame.maxY : window.frame.maxY
            let towardsTop = known ? element.frame.minY < upper : down   // above the visible area: drag down
            // Drag by what is missing (plus a margin), at most 60 % of the area, so a tall row does not
            // overshoot back and forth; held at the end, so there is no momentum.
            let span = area.frame.height
            var needed: CGFloat = span * 0.6
            if known {
                let frame = element.frame
                needed = towardsTop ? upper - frame.minY + 24 : frame.maxY - lower + 24
            }
            let fraction: CGFloat = min(max(needed / span, 0.12), 0.6)
            let middle = area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardsTop ? 0.2 : 0.8))
            let to = middle.withOffset(CGVector(dx: 0, dy: (towardsTop ? 1 : -1) * fraction * span))
            middle.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        return visible()
    }

    /// Scrolling reaches `element` (ACC-006-R2) and it can then be hit.
    private func requireReachable(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(scrollTo(element), "scrolling reaches \(what)", file: file, line: line)
        XCTAssertTrue(element.isHittable, "\(what) can be hit", file: file, line: line)
    }

    /// The field takes focus and keeps what is typed (ACC-006-R3).
    private func requireAcceptsInput(_ field: XCUIElement, _ text: String, _ what: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.appears(within: 5), "\(what) exists", file: file, line: line)
        XCTAssertTrue(field.isHittable, "\(what) can be hit", file: file, line: line)
        field.tap()
        field.typeText(text)
        XCTAssertTrue(poll(3) { ((field.value as? String) ?? "").contains(text) },
                      "\(what) shows the typed text: \(field.value ?? "nil")", file: file, line: line)
    }

    // MARK: - Navigation

    private func launch(_ size: String, _ extra: [String] = [], autostart: Bool = true) {
        XCUIDevice.shared.orientation = .portrait
        let start: [String] = autostart ? ["-autostart", "inAppPlayback"] : []
        app.launchArguments = ["-uitestResetNotice", "-uitestKeepControls", "-UIPreferredContentSizeCategoryName", self.size(size)]
            + start + extra + Self.noStore
        app.launch()
    }

    private var controls: XCUIElement { app.otherElements["controls"] }

    private func showControls() {
        let area = app.otherElements["visualizerTapArea"].firstMatch
        XCTAssertTrue(area.appears(within: 15), "the visualizer is up")
        // Below the middle: at AX5 a notice at the top can cover the centre of the screen.
        if !controls.exists { area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
    }

    private func tapControl(_ id: String) {
        let button = app.buttons[id]
        if !button.isHittable { scrollTo(button) }
        button.tap()
    }

    private func openSettings() {
        showControls()
        tapControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private func openPresetBrowser() {
        showControls()
        tapControl("presets")
        XCTAssertTrue(app.buttons["node:included"].appears(within: 10), "library home")
    }

    private func back() {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    }

    // MARK: - Screen groups

    /// The photosensitivity notice and the source chooser (no autostart).
    private func noticeAndChooser(_ size: String) throws {
        launch(size, autostart: false)
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.appears(within: 15))
        requireOnScreen(acknowledge, "I understand")
        try audit("notice")
        acknowledge.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.appears(within: 10), "the chooser")
        try audit("chooser")
        requireReachable(app.buttons["In-App Playback"], "In-App Playback, the last source row")
    }

    /// The visualizer controls: every button inside the window and hittable (ACC-006-R1).
    private func visualizerControls(_ size: String) throws {
        launch(size)
        showControls()
        XCTAssertTrue(poll(10) { self.app.buttons["duplicateCurrent"].exists }, "a projectM preset is showing")
        for id in ["stop", "pauseResume", "blackout", "saveFrame", "record", "previous", "next", "random", "presets",
                   "settings", "duplicateCurrent", "tapTempo"] {
            requireReachable(app.buttons[id], id)
        }
        app.buttons["blackout"].tap()   // a stable background (ACC-004 C3 design note)
        // The badge, not the button's label: at AX5 the badge above the controls can scroll the button away.
        XCTAssertTrue(app.descendants(matching: .any)["blackoutBadge"].firstMatch.appears(within: 8), "blacked out")
        try audit("controls")
    }

    /// Settings and the OSC port field.
    private func settings(_ size: String) throws {
        launch(size)
        openSettings()
        try audit("settings")
        let port = app.textFields["oscPortField"].firstMatch
        XCTAssertTrue(scrollTo(port), "the OSC port field")
        requireAcceptsInput(port, "1", "the OSC port field")
    }

    /// Storage and Licenses, the last rows of Settings (split from Settings: owner rule 7).
    private func storage(_ size: String) throws {
        launch(size)
        openSettings()
        let link = app.buttons["storageLink"]
        requireReachable(link, "Storage")
        link.tap()
        XCTAssertTrue(app.navigationBars["Storage"].appears(within: 10))
        try audit("storage")
        back()
        let licenses = app.buttons["licensesLink"]
        requireReachable(licenses, "Licenses")
        licenses.tap()
        XCTAssertTrue(app.navigationBars["Licenses"].appears(within: 10))
        try audit("licenses")
    }

    /// Settings with one native visual's own rows (owner rule 7: one visual per test): the visual's
    /// row, then its last row scrolled into view, then the audit; Text also takes typed input.
    private func settingsVisual(_ size: String, raw: String, screen: String, last: String) throws {
        launch(size, raw == "text" ? ["-uitestSeedText"] : [])
        openSettings()
        let row = app.buttons["visual.\(raw)"]
        XCTAssertTrue(scrollTo(row), "\(raw) row")
        row.tap()
        let element = app.descendants(matching: .any)[last].firstMatch
        XCTAssertTrue(scrollTo(element), "\(last) is reachable")
        try audit(screen)
        if raw == "text" {
            let message = app.descendants(matching: .any)["textMessageField"].firstMatch
            XCTAssertTrue(scrollTo(message, down: true), "the Text message field")
            requireAcceptsInput(message, "Hi", "the Text message field")
        }
    }

    /// The preset browser home, a pack, Collections and My Presets.
    /// The preset browser home (its last row reached) and a pack.
    private func browser(_ size: String) throws {
        launch(size)
        openPresetBrowser()
        try audit("browser")
        requireReachable(app.buttons["node:myPresets"], "My Presets row")
        let included = app.buttons["node:included"]
        XCTAssertTrue(scrollTo(included, down: true), "the pack row")
        included.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch
        XCTAssertTrue(row.appears(within: 5), "the pack lists presets")
        try audit("pack")
    }

    /// Collections and My Presets (split from the browser: owner rule 7).
    private func libraries(_ size: String) throws {
        launch(size)
        openPresetBrowser()
        let collections = app.buttons["node:collections"]
        requireReachable(collections, "Collections row")
        collections.tap()
        XCTAssertTrue(app.navigationBars["Collections"].appears(within: 10), "Collections opens")
        try audit("collections")
        back()
        requireReachable(app.buttons["node:myPresets"], "My Presets row")
        app.buttons["node:myPresets"].tap()
        XCTAssertTrue(app.buttons["importPreset"].appears(within: 5))
        try audit("myPresets")
    }

    /// The show editor (scene cards) and its two rename alerts: each field accepts input.
    private func showEditor(_ size: String) throws {
        launch(size, ["-uitestShowSeed"])
        showControls()
        requireReachable(app.buttons["showNextCue"], "Next cue")
        openSettings()
        let link = app.buttons["showEditorLink"]
        requireReachable(link, "the Show row")
        link.tap()
        XCTAssertTrue(app.navigationBars["Show"].appears(within: 5))
        try audit("showEditor")
        let cue = app.descendants(matching: .any)["showCue2"].firstMatch
        XCTAssertTrue(scrollTo(cue), "cue 2")
        swipeAction(cue, id: "showRenameScene", titles: ["Name", "Rename Scene"])
        let alert = app.alerts["Rename Scene"]
        XCTAssertTrue(alert.appears(within: 3), "the Rename Scene alert")
        try audit("renameSceneAlert")
        // At AX5 the alert's title and message fill it and the field sits below them: the alert's text
        // area scrolls (drag on the message, not on the buttons).
        let field = alert.textFields.firstMatch
        let message = alert.staticTexts.element(boundBy: alert.staticTexts.count > 1 ? 1 : 0)
        for _ in 0..<4 where !field.isHittable { message.swipeUp() }
        requireAcceptsInput(field, " B", "the scene name field")
        requireOnScreen(alert.buttons["Rename"], "Rename")
        alert.buttons["Cancel"].tap()
    }

    /// Swipes a cue row right (short drag) and picks one of its leading actions (SceneDuplicateUITests).
    private func swipeAction(_ row: XCUIElement, id: String, titles: [String]) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let button = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", id, titles)).firstMatch
        XCTAssertTrue(button.appears(within: 3), "\(id) is offered")
        button.tap()
    }

    /// The user preset editor (PRE-015) on a duplicate of the playing preset: both fields accept input,
    /// Save and Cancel can be hit.
    private func presetEditor(_ size: String) throws {
        launch(size)
        showControls()
        let current = app.staticTexts["currentPreset"]
        XCTAssertTrue(poll(10) { current.exists && current.label != "No preset" })
        let name = current.label
        tapControl("duplicateCurrent")
        let alert = app.alerts["Duplicate to My Presets"]
        XCTAssertTrue(alert.appears(within: 15))   // a system alert: not audited (iOS lays it out)
        alert.buttons["OK"].tap()
        tapControl("presets")
        XCTAssertTrue(app.buttons["node:included"].appears(within: 10))
        requireReachable(app.buttons["node:myPresets"], "My Presets row")
        app.buttons["node:myPresets"].tap()
        let row = app.buttons["preset:\(name) copy"]
        XCTAssertTrue(row.appears(within: 5), "the copy is listed")
        row.swipeLeft()
        let edit = app.buttons["editUserPresetSwipe"]
        XCTAssertTrue(edit.appears(within: 3), "Edit is offered")
        edit.tap()
        let editor = app.textViews["presetEditorText"]
        XCTAssertTrue(editor.appears(within: 10), "the editor opens")
        try audit("presetEditor")
        for id in ["presetEditorSave", "presetEditorCancel"] { requireOnScreen(app.buttons[id], id) }
        requireAcceptsInput(app.descendants(matching: .any)["presetEditorName"].firstMatch, "Z", "the name field")
        requireAcceptsInput(editor, "zq", "the preset text")
    }

    /// The SCN-012 repair sheet: every button inside the window.
    private func repairSheet(_ size: String) throws {
        launch(size, ["-uitestShowRepairSeed"])
        showControls()
        tapControl("showNextCue")
        XCTAssertTrue(app.staticTexts["sceneRepairStatus"].appears(within: 5), "the repair report")
        try audit("repair")
        let last = app.staticTexts["sceneRepairGroup.invalidMappings"]
        XCTAssertTrue(scrollTo(last), "scrolling reaches the last group")
        // At AX sizes the buttons are the report's last section (ACC-006-R2): reached by scrolling.
        for id in ["sceneRepairOpenRepaired", "sceneRepairOpenAsIs", "sceneRepairCancel"] { requireReachable(app.buttons[id], id) }
    }

    /// The FILE-013 Local Network notice in Settings' OSC section.
    private func localNetworkNotice(_ size: String) throws {
        launch(size, ["-settings.osc.enabled", "NO", "-settings.osc.port", "47127", "-uitestOSCFailure", "localNetworkDenied"])
        openSettings()
        let toggle = app.switches["oscReceiverToggle"]
        XCTAssertTrue(scrollTo(toggle), "the OSC section")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        // The notice replaces the status below the toggle; at AX5 it can start below the screen (lazy).
        let text = app.staticTexts["localNetworkNoticeText"]
        XCTAssertTrue(poll(5) { text.exists } || scrollTo(text), "the Local Network notice")
        requireReachable(app.buttons["localNetworkOpenSettings"], "Open Settings (Local Network)")
        try audit("localNetworkNotice")
    }

    /// The FILE-013 camera notice over the visualizer (camera restricted), with the controls up.
    private func cameraNotice(_ size: String) throws {
        launch(size, ["-uitestCamera", "restricted"])
        openSettings()
        let camera = app.visualRow("Camera")
        XCTAssertTrue(scrollTo(camera))
        camera.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.otherElements["cameraNotice"].appears(within: 10), "the camera notice")
        requireOnScreen(app.buttons["cameraOpenSettings"], "Open Settings (camera)")
        try audit("cameraNotice")
        showControls()   // closing Settings can leave them hidden; one tap brings them back
        requireReachable(app.buttons["settings"], "Settings in the controls under the notice")
    }

    /// The UIX-001 guide: each step's buttons reachable.
    private func guide(_ size: String) throws {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestGuidedFirstScene", "-UIPreferredContentSizeCategoryName", self.size(size)]
            + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.appears(within: 15))
        acknowledge.tap()
        XCTAssertTrue(app.descendants(matching: .any)["guidedFirstScene"].firstMatch.appears(within: 5), "the guide")
        let next = app.buttons["guide.next"]
        // Audited: welcome (long text) and look (choice rows and fields); sound and visual repeat those
        // layouts (fixed-size wrapping text, as GuidedFirstSceneUITests' AX5 test checks). Every step's
        // Next is checked (owner rule 7: the walk stays under 30 s).
        for step in ["welcome", "sound", "visual", "look"] {
            if step == "welcome" || step == "look" { try audit("guide.\(step)") }
            requireReachable(next, "Next on \(step)")
            if step == "look" {
                let message = app.textFields["guide.message"].firstMatch.exists ? app.textFields["guide.message"].firstMatch
                    : app.textViews["guide.message"].firstMatch
                if message.exists { requireAcceptsInput(message, "Hi", "the guide's message field") }
            }
            next.tap()
        }
        try audit("guide.play")
        requireReachable(next, "Play")
        requireReachable(app.buttons["guide.skip"], "Skip")
    }

    // MARK: - Tests (AX5 and AX3 per group)

    func testNoticeAndChooserAX5() throws { try noticeAndChooser(Self.ax5) }
    func testNoticeAndChooserAX3() throws { try noticeAndChooser(Self.ax3) }
    func testVisualizerControlsAX5() throws { try visualizerControls(Self.ax5) }
    func testVisualizerControlsAX3() throws { try visualizerControls(Self.ax3) }
    func testSettingsAX5() throws { try settings(Self.ax5) }
    func testSettingsAX3() throws { try settings(Self.ax3) }
    func testStorageAX5() throws { try storage(Self.ax5) }
    func testStorageAX3() throws { try storage(Self.ax3) }
    func testLinearSpectrumRowsAX5() throws { try settingsVisual(Self.ax5, raw: "linearSpectrum", screen: "settingsLinear", last: "spacingPicker") }
    func testLinearSpectrumRowsAX3() throws { try settingsVisual(Self.ax3, raw: "linearSpectrum", screen: "settingsLinear", last: "spacingPicker") }
    func testOscilloscopeRowsAX5() throws {
        try settingsVisual(Self.ax5, raw: "oscilloscope", screen: "settingsOscilloscope", last: "oscilloscopeWindowPicker")
    }
    func testOscilloscopeRowsAX3() throws {
        try settingsVisual(Self.ax3, raw: "oscilloscope", screen: "settingsOscilloscope", last: "oscilloscopeWindowPicker")
    }
    func testTextRowsAX5() throws { try settingsVisual(Self.ax5, raw: "text", screen: "settingsText", last: "textFontPicker") }
    func testTextRowsAX3() throws { try settingsVisual(Self.ax3, raw: "text", screen: "settingsText", last: "textFontPicker") }
    func testBrowserAX5() throws { try browser(Self.ax5) }
    func testBrowserAX3() throws { try browser(Self.ax3) }
    func testCollectionsAndMyPresetsAX5() throws { try libraries(Self.ax5) }
    func testCollectionsAndMyPresetsAX3() throws { try libraries(Self.ax3) }
    func testShowEditorAX5() throws { try showEditor(Self.ax5) }
    func testShowEditorAX3() throws { try showEditor(Self.ax3) }
    func testPresetEditorAX5() throws { try presetEditor(Self.ax5) }
    func testPresetEditorAX3() throws { try presetEditor(Self.ax3) }
    func testRepairSheetAX5() throws { try repairSheet(Self.ax5) }
    func testRepairSheetAX3() throws { try repairSheet(Self.ax3) }
    func testLocalNetworkNoticeAX5() throws { try localNetworkNotice(Self.ax5) }
    func testLocalNetworkNoticeAX3() throws { try localNetworkNotice(Self.ax3) }
    func testCameraNoticeAX5() throws { try cameraNotice(Self.ax5) }
    func testCameraNoticeAX3() throws { try cameraNotice(Self.ax3) }
    func testGuideAX5() throws { try guide(Self.ax5) }
    func testGuideAX3() throws { try guide(Self.ax3) }
}
