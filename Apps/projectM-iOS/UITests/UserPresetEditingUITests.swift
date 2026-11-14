// PRE-015-T15: duplicating a built-in preset and editing the copy on the iOS Simulator with the
// real engine (specs/010-pre-015-user-preset-duplication; PRE-015-R1, R9-R18; S6). The built-in
// presets are the app's 28 Included files; the edited text is written here. Launched with the
// fixed fake entitlement (`-uitestUnlocked NO`, no StoreKit). Simulator only; never device
// evidence (Constitution X).
// Shortened 2026-11-13 under owner rule 7: `-autostart inAppPlayback` replaces the notice and chooser
// taps, waits poll every 0.1 s (UITestWaits.swift), and held drags (`app.reveal`) replace flinging
// swipes. testDuplicateFromTheBrowserThenEditFailAndSave is split in two (its valid save moved to
// testDuplicateFromTheBrowserThenEditAndSave). Every assertion is unchanged.
import XCTest

@MainActor
final class UserPresetEditingUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func start(extraArguments: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        // `-autostart inAppPlayback` (Debug) starts the reference track as the chooser's row does.
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO",
                               "-autostart", "inAppPlayback"] + extraArguments
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))   // a ceiling for a loaded Mac
    }

    /// Taps a control of the overlay. The controls hide by themselves 5 s after the last use and a
    /// tap on the picture toggles them, so the tap is retried until it lands on a visible control.
    private func tapControl(_ id: String) {
        app.tapFreshControl(id)
    }

    private func open(_ id: String) {
        let element = app.buttons[id]
        // Held drags only when needed: a flinging swipe waits seconds for the list to settle.
        if !(element.appears(within: 2) && element.isHittable) { app.reveal(element) }
        XCTAssertTrue(element.appears(within: 3), id)
        element.tap()
    }

    /// The first preset row of the Included list; returns its name.
    private func openIncludedAndPickFirst() -> (XCUIElement, String) {
        tapControl("presets")
        XCTAssertTrue(app.buttons["node:included"].appears(within: 10), "library home")
        open("node:included")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch
        XCTAssertTrue(row.appears(within: 10))
        return (row, String(row.identifier.dropFirst("preset:".count)))
    }

    private func contextMenuItem(on element: XCUIElement, _ id: String, label: String) -> XCUIElement {
        element.press(forDuration: 1.2)
        let byID = app.buttons[id]
        if byID.appears(within: 3) { return byID }
        let byLabel = app.collectionViews.buttons[label]
        XCTAssertTrue(byLabel.appears(within: 3), label)
        return byLabel
    }

    private func duplicateAlertMessage() -> String {
        let alert = app.alerts["Duplicate to My Presets"]
        XCTAssertTrue(alert.appears(within: 15), "the duplicate result is shown")
        let message = alert.staticTexts.allElementsBoundByIndex.map(\.label).first { $0 != "Duplicate to My Presets" } ?? ""
        alert.buttons["OK"].tap()
        XCTAssertTrue(alert.disappears(within: 5))
        return message
    }

    private func backToHome() {
        for _ in 0..<3 where !app.buttons["node:myPresets"].exists {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists else { break }
            back.tap()
        }
    }

    private func openMyPresetsRow(_ name: String) -> XCUIElement {
        backToHome()
        open("node:myPresets")
        let row = app.buttons["preset:\(name)"]
        _ = row.appears(within: 2)
        app.reveal(row)
        XCTAssertTrue(row.exists, name)
        return row
    }

    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Replaces the editor's whole text with `text` (select all, then type).
    /// Selects everything, then types `text`. Cmd-A right after the tap can land before the text
    /// view has keyboard focus; the typing then goes in after the first character (seen once the
    /// waits got faster, 2026-11-13). So wait for focus, and check the result and retry once.
    private func replaceText(_ editor: XCUIElement, with text: String) {
        for _ in 0..<2 {
            editor.tap()
            _ = poll(3) { (editor.value(forKey: "hasKeyboardFocus") as? Bool) == true }
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText(text)
            let value: String = editor.value as? String ?? ""
            if value == text { return }
        }
        XCTFail("the editor does not hold exactly the typed text")
    }

    private var editor: XCUIElement { app.textViews["presetEditorText"] }

    // MARK: - Tests

    /// Duplicates the first Included preset from the browser and opens the copy in the editor;
    /// returns the built-in preset's name.
    private func duplicateFromTheBrowserAndEdit() -> String {
        start()
        let (row, name) = openIncludedAndPickFirst()
        contextMenuItem(on: row, "duplicatePreset", label: "Duplicate to My Presets").tap()
        let message = duplicateAlertMessage()
        XCTAssertEqual(message, "Duplicated “\(name)” to My Presets as “\(name) copy”.")

        let copyRow = openMyPresetsRow("\(name) copy")
        contextMenuItem(on: copyRow, "editUserPreset", label: "Edit").tap()
        XCTAssertTrue(editor.appears(within: 10), "the editor opens")
        XCTAssertTrue(app.textFields["presetEditorName"].exists)
        XCTAssertTrue((editor.value as? String)?.contains("[preset00]") == true, "the copy's text is shown")
        return name
    }

    // Owner rule 7 (2026-11-13): the former single test (57 s; 30 s after the faster waits) is
    // split in two. Both duplicate from the browser and open the editor; the refusal and Keep
    // Editing stay here, the valid save moved to testDuplicateFromTheBrowserThenEditAndSave.

    func testDuplicateFromTheBrowserThenEditFailAndSave() throws {
        _ = duplicateFromTheBrowserAndEdit()

        // A setting before the header fails the checks: not saved, the editor stays with the reason.
        replaceText(editor, with: "zoom=2\n")
        app.buttons["presetEditorSave"].tap()
        let error = app.descendants(matching: .any)["presetEditorError"]
        XCTAssertTrue(error.appears(within: 10))
        XCTAssertTrue(error.label.contains("does not start with the [preset00] header"), error.label)
        XCTAssertTrue(editor.exists, "the editor stays open")
        keepScreenshot("editor-refused")

        // Cancel with changes asks first; Keep Editing stays.
        app.buttons["presetEditorCancel"].tap()
        XCTAssertTrue(app.alerts.buttons["Keep Editing"].appears(within: 5))
        app.alerts.buttons["Keep Editing"].tap()
        XCTAssertTrue(editor.exists)
    }

    func testDuplicateFromTheBrowserThenEditAndSave() throws {
        let name = duplicateFromTheBrowserAndEdit()

        // A valid text is checked by the real engine and saved.
        replaceText(editor, with: ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.95", "zoom=1.03",
                                   "per_frame_1=rot = 0.03*sin(time);", ""].joined(separator: "\n"))
        let nameField = app.textFields["presetEditorName"]
        nameField.tap()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("My edit")
        app.buttons["presetEditorSave"].tap()
        XCTAssertTrue(editor.disappears(within: 20), "a saved edit closes the editor")
        XCTAssertTrue(app.buttons["preset:My edit"].appears(within: 10))

        // The built-in preset is still listed under its own name in Included.
        backToHome()
        open("node:included")
        XCTAssertTrue(app.buttons["preset:\(name)"].appears(within: 10))
    }

    func testDiscardingChangesKeepsTheSavedVersion() throws {
        start()
        let (row, name) = openIncludedAndPickFirst()
        contextMenuItem(on: row, "duplicatePreset", label: "Duplicate to My Presets").tap()
        _ = duplicateAlertMessage()
        contextMenuItem(on: openMyPresetsRow("\(name) copy"), "editUserPreset", label: "Edit").tap()
        XCTAssertTrue(editor.appears(within: 10))
        let original = editor.value as? String
        editor.tap()
        editor.typeText("x")
        app.buttons["presetEditorCancel"].tap()
        let discard = app.alerts.buttons["Discard Changes"].firstMatch
        XCTAssertTrue(discard.appears(within: 5))
        // `.firstMatch`: the system alert reports its button twice (nested) to accessibility.
        discard.tap()
        XCTAssertFalse(app.alerts.firstMatch.appears(within: 2), "no second question")
        XCTAssertTrue(editor.disappears(within: 5))

        contextMenuItem(on: app.buttons["preset:\(name) copy"], "editUserPreset", label: "Edit").tap()
        XCTAssertTrue(editor.appears(within: 10))
        XCTAssertEqual(editor.value as? String, original, "nothing was saved")
        app.buttons["presetEditorCancel"].tap()   // unchanged: closes at once
        XCTAssertTrue(editor.disappears(within: 5))
    }

    func testDuplicateTheCurrentPresetFromTheControls() throws {
        start()
        let current = app.staticTexts["currentPreset"]
        XCTAssertTrue(current.appears(within: 10))
        let name = current.label
        tapControl("duplicateCurrent")
        XCTAssertEqual(duplicateAlertMessage(), "Duplicated “\(name)” to My Presets as “\(name) copy”.")
        tapControl("duplicateCurrent")
        XCTAssertEqual(duplicateAlertMessage(),
                       "“\(name)” was not duplicated. Its unchanged copy is already in My Presets as “\(name) copy”.")
        XCTAssertEqual(current.label, name, "the built-in preset keeps playing")
    }

    func testTheEditorAtTheLargestAccessibilityTextSize() throws {
        start(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tapControl("duplicateCurrent")
        _ = duplicateAlertMessage()
        tapControl("presets")
        XCTAssertTrue(app.buttons["node:included"].appears(within: 10))
        // At this text size the row can sit half under the bottom edge, where a tap lands on the
        // home indicator (seen in the PRE-014 run): retry until My Presets is open.
        for _ in 0..<4 where !app.buttons["importPreset"].exists {
            open("node:myPresets")
            if app.buttons["importPreset"].appears(within: 5) { break }
            app.reveal(app.buttons["node:myPresets"])
        }
        let row = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH ' copy'")).firstMatch
        _ = row.appears(within: 2)
        app.reveal(row)
        contextMenuItem(on: row, "editUserPreset", label: "Edit").tap()
        XCTAssertTrue(editor.appears(within: 10))
        for id in ["presetEditorName", "presetEditorText"] {
            let element = app.descendants(matching: .any)[id]
            XCTAssertTrue(element.exists, id)
            XCTAssertTrue(element.isHittable, id)
        }
        for id in ["presetEditorSave", "presetEditorCancel"] {
            XCTAssertTrue(app.buttons[id].isHittable, id)
        }
        XCTAssertEqual(editor.label, "Preset text")
        keepScreenshot("editor-accessibility-xxxl")
        app.buttons["presetEditorCancel"].tap()
        XCTAssertTrue(editor.disappears(within: 5))
    }
}
