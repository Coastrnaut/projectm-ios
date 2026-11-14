// SceneSwitcherUITests.swift — UIX-002-T11 to T13, T15 on the iOS Simulator (UIX-002-S1 to S3, S5;
// contract C1 to C4). With the DEBUG show seed (`-uitestShowSeed`: Opening, Build, Drop, Break,
// Finale, standing on cue 1) the switcher opens with its field focused, filters as the user types
// without losing focus or text, recalls the chosen cue through the cue path and reports the
// choice → applied latency (in-app monotonic clock, budget 250 ms; `sceneSwitcherProbe`). With the
// repair seed a problem scene shows SCN-012's report first. Simulator results are never device
// evidence. Owner rule 7: each test under 30 s; UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class SceneSwitcherUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    private var applied: String? { app.staticTexts["showAppliedScene"].value as? String }
    private var probe: String { (app.staticTexts["sceneSwitcherProbe"].value as? String) ?? "" }
    private var announcement: String { (app.staticTexts["announcementProbe"].value as? String) ?? "" }
    private var card: XCUIElement { app.otherElements["sceneSwitcher"] }
    /// A text field, or a text view at accessibility sizes (the query wraps there, ACC-006-R1).
    private var field: XCUIElement { app.descendants(matching: .any)["sceneSwitcherField"].firstMatch }
    private var count: XCUIElement { app.staticTexts["sceneSwitcherCount"] }
    private func entry(_ n: Int) -> XCUIElement { app.buttons["sceneSwitcherEntry.\(n)"] }
    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    private var fieldHasFocus: Bool { (field.value(forKey: "hasKeyboardFocus") as? Bool) == true }
    /// The field's text ("" while the placeholder shows).
    private var fieldText: String {
        let value = (field.value as? String) ?? ""
        return value == "Search scenes" ? "" : value
    }

    private func launch(_ seed: String, extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", seed, "-autostart", "inAppPlayback",
                               "-uitestUnlocked", "NO"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let opening = "\(Self.sceneID(1))|circularSpectrum"
        XCTAssertTrue(poll(3) { self.applied == opening }, "cue 1 applied: \(applied ?? "nil")")
        XCTAssertEqual(probe, "none")
    }

    private func openWithCommandK(file: StaticString = #filePath, line: UInt = #line) {
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(field.appears(within: 3), "⌘K opens the switcher", file: file, line: line)
        XCTAssertTrue(poll(2) { self.fieldHasFocus }, "the field is focused on open", file: file, line: line)
    }

    /// Types one string and checks focus, text and the result count right after (UIX-002-S3).
    private func type(_ text: String, expect: String, count expected: String, file: StaticString = #filePath, line: UInt = #line) {
        field.typeText(text)
        XCTAssertTrue(poll(2) { self.count.label == expected }, "count \(expected), got \(count.label) for \"\(fieldText)\" (output \(app.staticTexts["outputBlackout"].value as? String ?? "?"))", file: file, line: line)
        XCTAssertTrue(fieldHasFocus, "the field keeps keyboard focus after \"\(text)\"", file: file, line: line)
        XCTAssertEqual(fieldText, expect, "the field keeps its text", file: file, line: line)
    }

    private func expectApplied(_ n: Int, _ visual: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = "\(Self.sceneID(n))|\(visual)"
        XCTAssertTrue(poll(3) { self.applied == expected }, "scene \(n) applied: \(applied ?? "nil")", file: file, line: line)
    }

    /// The probe's measurement for a scene: outcome, ok verdict, and the milliseconds (UIX-002-S2).
    @discardableResult
    private func expectProbe(_ outcome: String, scene n: Int, file: StaticString = #filePath, line: UInt = #line) -> Double {
        let prefix = "\(outcome)|\(Self.sceneID(n))|"
        XCTAssertTrue(poll(3) { self.probe.hasPrefix(prefix) }, "probe \(prefix)…, got \(probe)", file: file, line: line)
        XCTAssertTrue(probe.hasSuffix("|ok"), "within the 250 ms budget: \(probe)", file: file, line: line)
        let parts = probe.split(separator: "|")
        let ms = parts.count == 4 ? Double(parts[2]) ?? -1 : -1
        XCTAssertGreaterThanOrEqual(ms, 0, file: file, line: line)
        print("UIX-002 latency \(outcome) scene \(n): \(ms) ms")
        return ms
    }

    // UIX-002-T11 (US1; S1, S2)
    func testTypeFilterAndRecallWithinBudget() {
        launch("-uitestShowSeed")
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 3))
        let button = app.buttons["showSceneSwitcher"]
        XCTAssertTrue(button.exists)
        XCTAssertEqual(button.label, "Scenes")
        button.tap()
        XCTAssertTrue(field.appears(within: 3), "the Scenes button opens the switcher")
        XCTAssertTrue(poll(2) { self.fieldHasFocus }, "the field is focused on open")
        XCTAssertEqual(count.label, "5 scenes")
        for n in 1...5 { XCTAssertTrue(entry(n).exists, "entry \(n) listed") }
        XCTAssertEqual(entry(3).label, "Drop")
        XCTAssertEqual(entry(1).value as? String, "Cue 1, current")
        XCTAssertTrue(entry(1).isSelected, "the active cue is highlighted")

        // US1 scenario 4: Down Arrow moves the highlight; the field keeps focus.
        app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(poll(2) { self.entry(2).isSelected }, "Down Arrow highlights entry 2")
        XCTAssertFalse(entry(1).isSelected)
        XCTAssertTrue(fieldHasFocus)

        type("dr", expect: "dr", count: "1 scene")
        XCTAssertTrue(entry(3).exists)
        XCTAssertFalse(entry(1).exists)
        XCTAssertTrue(entry(3).isSelected, "the only result is highlighted")
        field.typeText("\n")   // Return: 3 key presses after opening (S1)
        XCTAssertTrue(card.disappears(within: 3), "a choice closes the switcher")
        expectApplied(3, "circularSpectrum")
        expectProbe("applied", scene: 3)
        XCTAssertTrue(poll(2) { self.announcement == "cue|Scene: Drop" }, "announced: \(announcement)")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the audio source was not restarted")
    }

    // UIX-002-T12 (US2; S3) and the count announcement of T15
    func testTypingKeepsFocusTextAndRestoresAnAbandonedQuery() {
        launch("-uitestShowSeed")
        openWithCommandK()
        type("b", expect: "b", count: "2 scenes")   // Build, Break
        XCTAssertTrue(poll(2) { self.announcement == "search|2 scenes" }, "count announced: \(announcement)")
        XCTAssertTrue(entry(2).exists && entry(4).exists)
        XCTAssertTrue(entry(2).isSelected, "the active cue no longer matches: the first result")
        type("r", expect: "br", count: "1 scene")   // Break
        XCTAssertTrue(entry(4).isSelected)
        type("e", expect: "bre", count: "1 scene")
        type(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue, expect: "b", count: "2 scenes")
        XCTAssertTrue(entry(4).isSelected, "the highlight stays on a result that still matches")
        type("zz", expect: "bzz", count: "No matching scenes")
        field.typeText("\n")   // nothing to choose
        XCTAssertTrue(card.exists, "Return with no match keeps the switcher open")
        XCTAssertTrue(poll(2) { self.fieldHasFocus }, "and the field focused")
        XCTAssertEqual(fieldText, "bzz")
        type(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue, expect: "b", count: "2 scenes")
        XCTAssertTrue(entry(2).isSelected, "after no match, the first result is highlighted again")

        // ⌘K closes while the field is focused (contract C2). Escape is wired too (the field's key
        // handler and the Close button's cancel action), but XCUITest's Escape key event never reached
        // the focused field on the iOS 27.2 simulator (2026-11-14), so it is not asserted here.
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(card.disappears(within: 3), "⌘K closes (focus \(fieldHasFocus), text \(fieldText))")
        XCTAssertEqual(applied, "\(Self.sceneID(1))|circularSpectrum", "closing applies nothing")
        XCTAssertEqual(probe, "none")
        openWithCommandK()
        XCTAssertEqual(fieldText, "b", "the abandoned query is restored")
        XCTAssertEqual(count.label, "2 scenes")
        XCTAssertTrue(entry(2).isSelected, "with its highlight")

        entry(4).tap()
        XCTAssertTrue(card.disappears(within: 3))
        expectApplied(4, "linearSpectrum")
        expectProbe("applied", scene: 4)
        openWithCommandK()
        XCTAssertEqual(fieldText, "", "after a choice the switcher reopens empty")
        XCTAssertEqual(count.label, "5 scenes")
        XCTAssertTrue(entry(4).isSelected, "on the active cue")
    }

    // UIX-002-T13 (US3; S5)
    func testAProblemSceneShowsTheRepairReport() {
        launch("-uitestShowRepairSeed")
        openWithCommandK()
        type("brok", expect: "brok", count: "1 scene")
        field.typeText("\n")
        XCTAssertTrue(card.disappears(within: 3))
        let status = app.staticTexts["sceneRepairStatus"]
        XCTAssertTrue(status.appears(within: 5), "the repair report appears")
        XCTAssertEqual(status.label, "Opens with problems")
        let opening = "\(Self.sceneID(1))|circularSpectrum"
        XCTAssertEqual(applied, opening, "nothing is applied before the user chooses")
        expectProbe("repairShown", scene: 2)
        app.buttons["sceneRepairCancel"].tap()
        XCTAssertTrue(status.disappears(within: 5))
        XCTAssertEqual(applied, opening, "Close leaves the output unchanged")
    }

    // UIX-002-T15 (US4; R10): the largest accessibility text size.
    func testLargestTextSizeKeepsTheCardUsable() {
        launch("-uitestShowSeed", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openWithCommandK()
        let window = app.windows.firstMatch.frame
        let close = app.buttons["sceneSwitcherClose"]
        for (name, element) in [("field", field), ("Close", close), ("count", count)] {
            XCTAssertTrue(element.exists, "\(name) exists")
            XCTAssertTrue(window.contains(element.frame), "\(name) lies inside the window: \(element.frame) in \(window)")
        }
        XCTAssertTrue(card.frame.maxY <= window.maxY + 0.5, "the card never exceeds the screen")
        type("fin", expect: "fin", count: "1 scene")
        // The DEBUG probe texts (centered, enlarged at AX5) sit above the card for accessibility hit
        // tests, so the entry is checked by frame and tapped by coordinate (a real touch ignores them).
        let row = entry(5).frame
        let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : window.maxY
        XCTAssertTrue(card.frame.contains(row), "the entry lies inside the card: \(row) in \(card.frame)")
        XCTAssertLessThan(row.minY + 20, keyboardTop, "the entry is above the keyboard: \(row), keyboard top \(keyboardTop)")
        entry(5).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.15)).tap()
        XCTAssertTrue(card.disappears(within: 3))
        expectApplied(5, "text")
        expectProbe("applied", scene: 5)
    }
}
