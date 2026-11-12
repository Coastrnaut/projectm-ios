// PRE-007-T16, T21: preset collections on the iOS Simulator (specs/005-pre-007-preset-collections;
// PRE-007-S1, S2, S4). Create, fill, reorder by hand, relaunch and compare; play a collection as the
// scope; delete it and find its presets and favorites untouched. Launched with the fixed fake
// entitlement (`-uitestUnlocked NO`, no StoreKit). Uses only Included presets, so it runs with or
// without the pack submodules. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class PresetCollectionsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// `reset` starts from a fresh state (notice, favorites, settings and collections removed);
    /// without it the app relaunches with what the previous launch saved.
    private func start(reset: Bool, extraArguments: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics", "-uitestUnlocked", "NO"] + extraArguments
        app.launch()
        if reset {
            let acknowledge = app.buttons["acknowledgeNotice"]
            XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
            acknowledge.tap()
        }
        let inApp = app.buttons["In-App Playback"]
        if !inApp.waitForExistence(timeout: 10) { app.swipeUp() }   // very large text: the row may be below the fold
        XCTAssertTrue(inApp.waitForExistence(timeout: 5))
        inApp.tap()
        XCTAssertTrue(scopeLine.waitForExistence(timeout: 10))
    }

    private var scopeLine: XCUIElement { app.staticTexts["scopeLine"] }
    private var current: XCUIElement { app.staticTexts["currentPreset"] }

    private func tapControl(_ id: String) {
        let button = app.buttons[id]
        if !button.waitForExistence(timeout: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(button.waitForExistence(timeout: 3), id)
        button.tap()
    }

    private func openBrowser() {
        tapControl("presets")
        XCTAssertTrue(app.buttons["node:included"].waitForExistence(timeout: 10), "library home")
    }

    private func open(_ id: String) {
        let element = app.buttons[id]
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func waitForLabel(_ element: XCUIElement, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let done = expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: element)
        if XCTWaiter().wait(for: [done], timeout: 8) != .completed {
            XCTFail("expected “\(text)”, found “\(element.exists ? element.label : "<missing>")”", file: file, line: line)
        }
    }

    /// The preset rows on screen, top to bottom (names).
    private var presetRows: [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).allElementsBoundByIndex
            .map { String($0.identifier.dropFirst("preset:".count)) }
    }

    private var collectionRows: [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'collection:'")).allElementsBoundByIndex
            .map { String($0.identifier.dropFirst("collection:".count)) }
    }

    private func typeName(_ name: String) {
        let field = app.textFields["collectionName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
    }

    /// On the collections list: New Collection → name → Save.
    private func createCollection(_ name: String) {
        open("newCollection")
        typeName(name)
        app.buttons["saveCollectionName"].tap()
        XCTAssertTrue(app.buttons["collection:\(name)"].waitForExistence(timeout: 5), name)
    }

    /// Touch and hold a row, then pick a menu item.
    private func menu(_ row: XCUIElement, _ item: String) {
        XCTAssertTrue(row.waitForExistence(timeout: 5), row.debugDescription)
        row.press(forDuration: 1.0)
        let button = app.buttons[item]
        XCTAssertTrue(button.waitForExistence(timeout: 5), item)
        button.tap()
    }

    /// In a preset list: add `preset` to `collection`; `creating` makes the collection in the same step (R4).
    private func add(_ preset: String, to collection: String, creating: Bool = false) {
        menu(app.buttons["preset:\(preset)"], "Add to Collection…")
        if creating {
            open("newCollection")
            typeName(collection)
            app.buttons["saveCollectionName"].tap()
        } else {
            open("addTo:\(collection)")
        }
        let sheetTitle = app.navigationBars["Add to Collection"]
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheetTitle)
        wait(for: [gone], timeout: 8)
    }

    /// The first three Included presets, as listed.
    private func openIncludedAndTakeThree() -> [String] {
        open("node:included")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch.waitForExistence(timeout: 5))
        let names = Array(presetRows.prefix(3))
        XCTAssertEqual(names.count, 3)
        return names
    }

    // MARK: - S1: manual order persists across a relaunch

    func testCreateFillReorderAndRelaunch() {
        executionTimeAllowance = 300   // a long flow; the shared Mac can be slow
        start(reset: true)
        openBrowser()
        XCTAssertEqual(app.buttons["node:collections"].label, "Collections, 0 collections")
        open("node:collections")
        XCTAssertTrue(app.staticTexts["collectionsEmpty"].waitForExistence(timeout: 5))
        createCollection("Friday set")
        XCTAssertEqual(app.buttons["collection:Friday set"].label, "Friday set, 0 presets")

        // A name that differs only in case is refused, with the reason, before saving (R9).
        open("newCollection")
        typeName("friday SET")
        waitForLabel(app.staticTexts["collectionNameError"], "A collection with this name already exists.")
        XCTAssertFalse(app.buttons["saveCollectionName"].isEnabled)
        app.buttons["Cancel"].tap()
        XCTAssertEqual(collectionRows, ["Friday set"])

        goBack()
        let names = openIncludedAndTakeThree()
        add(names[0], to: "Friday set")
        add(names[1], to: "Friday set")
        add(names[2], to: "Friday set")
        add(names[0], to: "Second", creating: true)   // a new collection made from the add sheet (R4)

        // Adding a preset that is already there is not offered again.
        menu(app.buttons["preset:\(names[0])"], "Add to Collection…")
        let already = app.buttons["addTo:Friday set"]
        XCTAssertTrue(already.waitForExistence(timeout: 5))
        XCTAssertFalse(already.isEnabled)
        XCTAssertEqual(already.label, "Friday set, already contains this preset")
        app.buttons["Cancel"].tap()

        goBack()
        waitForLabel(app.buttons["node:collections"], "Collections, 2 collections")
        open("node:collections")
        XCTAssertEqual(app.buttons["collection:Friday set"].label, "Friday set, 3 presets")
        XCTAssertEqual(app.buttons["collection:Second"].label, "Second, 1 preset")
        XCTAssertEqual(collectionRows, ["Friday set", "Second"], "in the order created")

        open("collection:Friday set")
        XCTAssertTrue(app.buttons["preset:\(names[0])"].waitForExistence(timeout: 5))
        XCTAssertEqual(presetRows, names, "in the order added")
        menu(app.buttons["preset:\(names[2])"], "Move Up")
        let reordered = [names[0], names[2], names[1]]
        XCTAssertEqual(presetRows, reordered)

        goBack()
        menu(app.buttons["collection:Second"], "Move Up")
        XCTAssertEqual(collectionRows, ["Second", "Friday set"])

        // Relaunch without the reset: what was saved is what is shown (S1).
        app.terminate()
        start(reset: false)
        openBrowser()
        XCTAssertEqual(app.buttons["node:collections"].label, "Collections, 2 collections")
        open("node:collections")
        XCTAssertTrue(app.buttons["collection:Second"].waitForExistence(timeout: 5))
        XCTAssertEqual(collectionRows, ["Second", "Friday set"])
        open("collection:Friday set")
        XCTAssertTrue(app.buttons["preset:\(names[0])"].waitForExistence(timeout: 5))
        XCTAssertEqual(presetRows, reordered)

        // Edit mode offers the standard drag handles; dragging the last row to the top reorders.
        app.buttons["Edit"].tap()
        let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'"))
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 5), "reorder handles in Edit mode")
        XCTAssertEqual(handles.count, 3)
        handles.element(boundBy: 2).press(forDuration: 0.8, thenDragTo: handles.element(boundBy: 0),
                                          withVelocity: .slow, thenHoldForDuration: 0.5)
        app.toolbars.buttons["Done"].tap()   // the Edit button's other title: leaves Edit mode
        XCTAssertEqual(presetRows, [reordered[2], reordered[0], reordered[1]])
    }

    // MARK: - S4, S2: play a collection; deleting it preserves presets and favorites

    func testPlayACollectionThenDeleteIt() {
        executionTimeAllowance = 300   // a long flow; the shared Mac can be slow
        start(reset: true)
        waitForLabel(scopeLine, "Included · 28")
        openBrowser()
        let names = openIncludedAndTakeThree()
        add(names[2], to: "Friday set", creating: true)
        add(names[0], to: "Friday set")
        add(names[1], to: "Friday set")
        let order = [names[2], names[0], names[1]]   // the user's order, not the alphabet
        app.buttons["star:\(names[0])"].tap()
        XCTAssertEqual(app.buttons["star:\(names[0])"].label, "Remove from favorites")

        goBack()
        open("node:collections")
        open("collection:Friday set")
        XCTAssertTrue(app.buttons["preset:\(order[0])"].waitForExistence(timeout: 5))
        XCTAssertEqual(presetRows, order)
        app.buttons["preset:\(order[1])"].tap()   // choosing closes the browser
        waitForLabel(scopeLine, "Friday set · 3")
        waitForLabel(current, order[1])
        tapControl("next")
        waitForLabel(current, order[2])
        tapControl("next")
        waitForLabel(current, order[0])   // wraps, in the user's order
        tapControl("previous")
        waitForLabel(current, order[2])
        for _ in 0..<5 {
            tapControl("random")
            XCTAssertTrue(order.contains(current.label), "Random stays in the collection")
            XCTAssertEqual(scopeLine.label, "Friday set · 3")
        }

        // Remove one preset: gone from the collection only (R5).
        openBrowser()
        open("node:collections")
        open("collection:Friday set")
        menu(app.buttons["preset:\(order[2])"], "Remove from Collection")
        XCTAssertEqual(presetRows, [order[0], order[1]])
        goBack()
        waitForLabel(app.buttons["collection:Friday set"], "Friday set, 2 presets")

        // Delete the collection: only the list goes (S2).
        menu(app.buttons["collection:Friday set"], "Delete")
        let confirm = app.buttons["confirmDeleteCollection"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["collectionsEmpty"].waitForExistence(timeout: 5))
        goBack()
        open("node:included")
        for name in names { XCTAssertTrue(app.buttons["preset:\(name)"].waitForExistence(timeout: 5), "\(name) is still in the library") }
        XCTAssertEqual(app.buttons["star:\(names[0])"].label, "Remove from favorites", "still a favorite")
        app.buttons["Done"].firstMatch.tap()
        waitForLabel(scopeLine, "Included · 28")   // the scope fell back; nothing else changed
    }

    // MARK: - T21: the largest text size

    func testTheCollectionScreensWorkAtTheLargestTextSize() {
        start(reset: true, extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openBrowser()
        open("node:collections")
        createCollection("A long collection name for large text")
        let row = app.buttons["collection:A long collection name for large text"]
        XCTAssertTrue(row.isHittable)
        XCTAssertEqual(row.label, "A long collection name for large text, 0 presets")
        row.tap()
        XCTAssertTrue(app.staticTexts["collectionEmpty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["renameCollection"].isHittable)
        open("renameCollection")
        let field = app.textFields["collectionName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveCollectionName"].isHittable)
        app.buttons["Cancel"].tap()
        goBack()
        XCTAssertTrue(app.buttons["newCollection"].isHittable)
    }
}
