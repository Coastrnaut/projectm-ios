// PRE-007-T16, T21: preset collections on the iOS Simulator (specs/005-pre-007-preset-collections;
// PRE-007-S1, S2, S4). Create, fill, reorder by hand, relaunch and compare; play a collection as the
// scope; delete it and find its presets and favorites untouched. Launched with the fixed fake
// entitlement (`-uitestUnlocked NO`, no StoreKit). Uses only Included presets, so it runs with or
// without the pack submodules. Simulator results are never device evidence (Constitution X).
// Shortened 2026-11-13 under owner rule 7: the two long flows are split into five tests, one rule
// group each, with two presets where three added nothing; `-autostart inAppPlayback` replaces the notice and chooser taps, and waits poll every
// 0.1 s (UITestWaits.swift) instead of about once a second; held drags (`app.reveal`) replace
// flinging swipes. Later the same day: the Edit-mode drag left testManualPresetOrderPersistsAcrossRelaunch
// for testEditModeDragHandlesReorderPresets, and removing and deleting became two tests. Every rule of the old flows is still checked.
import XCTest

@MainActor
final class PresetCollectionsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// `reset` starts from a fresh state (favorites, settings and collections removed); without it the
    /// app relaunches with what the previous launch saved. `-autostart inAppPlayback` (Debug) starts
    /// the reference track as the chooser's In-App Playback row does.
    private func start(reset: Bool, extraArguments: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : [])
            + ["-uitestDiagnostics", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback"] + extraArguments
        app.launch()
        XCTAssertTrue(scopeLine.appears(within: 15))
    }

    private var scopeLine: XCUIElement { app.staticTexts["scopeLine"] }
    private var current: XCUIElement { app.staticTexts["currentPreset"] }

    private func tapControl(_ id: String) {
        let button = app.buttons[id]
        if !button.appears(within: 0.5) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(button.appears(within: 3), id)
        button.tap()
    }

    private func openBrowser() {
        tapControl("presets")
        XCTAssertTrue(app.buttons["node:included"].appears(within: 10), "library home")
    }

    private func open(_ id: String) {
        let element = app.buttons[id]
        // Held drags only when needed: a flinging swipe waits seconds for the list to settle.
        if !(element.appears(within: 2) && element.isHittable) { app.reveal(element) }
        XCTAssertTrue(element.appears(within: 3), id)
        element.tap()
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func waitForLabel(_ element: XCUIElement, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        if !poll(8, { element.exists && element.label == text }) {
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
        XCTAssertTrue(field.appears(within: 5))
        field.tap()
        field.typeText(name)
    }

    /// On the collections list: New Collection → name → Save.
    private func createCollection(_ name: String) {
        open("newCollection")
        typeName(name)
        app.buttons["saveCollectionName"].tap()
        XCTAssertTrue(app.buttons["collection:\(name)"].appears(within: 5), name)
    }

    /// Touch and hold a row, then pick a menu item.
    private func menu(_ row: XCUIElement, _ item: String) {
        XCTAssertTrue(row.appears(within: 5), row.debugDescription)
        row.press(forDuration: 0.7)   // a context menu opens after about 0.5 s
        let button = app.buttons[item]
        XCTAssertTrue(button.appears(within: 5), item)
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
        XCTAssertTrue(app.navigationBars["Add to Collection"].disappears(within: 8), "the add sheet closes")
    }

    /// The first `count` Included presets, as listed.
    private func openIncludedAndTake(_ count: Int) -> [String] {
        open("node:included")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'"))
        XCTAssertTrue(rows.firstMatch.appears(within: 5))
        let names = (0..<count).map { String(rows.element(boundBy: $0).identifier.dropFirst("preset:".count)) }
        XCTAssertEqual(Set(names).count, count)
        return names
    }

    // MARK: - R9: names; the add sheet offers a collection only once per preset

    func testCreateRefusesADuplicateNameAndAddsEachPresetOnce() {
        start(reset: true)
        openBrowser()
        XCTAssertEqual(app.buttons["node:collections"].label, "Collections, 0 collections")
        open("node:collections")
        XCTAssertTrue(app.staticTexts["collectionsEmpty"].appears(within: 5))
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
        let names = openIncludedAndTake(1)
        add(names[0], to: "Friday set")

        // Adding a preset that is already there is not offered again.
        menu(app.buttons["preset:\(names[0])"], "Add to Collection…")
        let already = app.buttons["addTo:Friday set"]
        XCTAssertTrue(already.appears(within: 5))
        XCTAssertFalse(already.isEnabled)
        XCTAssertEqual(already.label, "Friday set, already contains this preset")
        app.buttons["Cancel"].tap()

        goBack()
        open("node:collections")
        waitForLabel(app.buttons["collection:Friday set"], "Friday set, 1 preset")
    }

    // MARK: - S1: manual order persists across a relaunch

    /// Opens Included, adds its first two presets to “Friday set” (the first creates the collection in
    /// the add sheet, R4), opens the collection and checks the rows are in the order added.
    private func makeFridaySetWithTwoPresets() -> [String] {
        start(reset: true)
        openBrowser()
        let names = openIncludedAndTake(2)
        add(names[0], to: "Friday set", creating: true)   // a new collection made from the add sheet (R4)
        add(names[1], to: "Friday set")
        goBack()
        open("node:collections")
        XCTAssertEqual(app.buttons["collection:Friday set"].label, "Friday set, 2 presets")
        open("collection:Friday set")
        XCTAssertTrue(app.buttons["preset:\(names[0])"].appears(within: 5))
        XCTAssertEqual(presetRows, names, "in the order added")
        return names
    }

    /// Presets: added through the add sheet, Move Up, relaunch, same order.
    func testManualPresetOrderPersistsAcrossRelaunch() {
        let names = makeFridaySetWithTwoPresets()
        menu(app.buttons["preset:\(names[1])"], "Move Up")
        let reordered = [names[1], names[0]]
        XCTAssertTrue(poll(5) { self.presetRows == reordered }, "\(presetRows)")

        // Relaunch without the reset: what was saved is what is shown (S1).
        app.terminate()
        start(reset: false)
        openBrowser()
        open("node:collections")
        open("collection:Friday set")
        XCTAssertTrue(app.buttons["preset:\(names[0])"].appears(within: 5))
        XCTAssertEqual(presetRows, reordered)
    }

    /// Edit mode offers the standard drag handles; dragging the last row to the top reorders.
    /// (Split from testManualPresetOrderPersistsAcrossRelaunch under owner rule 7; there it ran on
    /// the relaunched, Move-Up order, here on the order added.)
    func testEditModeDragHandlesReorderPresets() {
        let names = makeFridaySetWithTwoPresets()
        app.buttons["Edit"].tap()
        let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'"))
        XCTAssertTrue(handles.firstMatch.appears(within: 5), "reorder handles in Edit mode")
        XCTAssertEqual(handles.count, 2)
        handles.element(boundBy: 1).press(forDuration: 0.8, thenDragTo: handles.element(boundBy: 0),
                                          withVelocity: .slow, thenHoldForDuration: 0.5)
        app.toolbars.buttons["Done"].tap()   // the Edit button's other title: leaves Edit mode
        XCTAssertTrue(poll(5) { self.presetRows == [names[1], names[0]] }, "\(presetRows)")
    }

    /// Collections: listed in the order created; Move Up; relaunch, same order.
    func testManualCollectionOrderPersistsAcrossRelaunch() {
        start(reset: true)
        openBrowser()
        open("node:collections")
        createCollection("Friday set")
        createCollection("Second")
        XCTAssertEqual(collectionRows, ["Friday set", "Second"], "in the order created")
        goBack()
        waitForLabel(app.buttons["node:collections"], "Collections, 2 collections")
        open("node:collections")
        menu(app.buttons["collection:Second"], "Move Up")
        XCTAssertTrue(poll(5) { self.collectionRows == ["Second", "Friday set"] }, "\(collectionRows)")

        app.terminate()
        start(reset: false)
        openBrowser()
        XCTAssertEqual(app.buttons["node:collections"].label, "Collections, 2 collections")
        open("node:collections")
        XCTAssertTrue(app.buttons["collection:Second"].appears(within: 5))
        XCTAssertEqual(collectionRows, ["Second", "Friday set"])
    }

    // MARK: - S4: a collection as the playback scope

    func testPlayingACollectionKeepsNextPreviousAndRandomInside() {
        start(reset: true)
        waitForLabel(scopeLine, "Included · 28")
        openBrowser()
        let names = openIncludedAndTake(3)
        add(names[2], to: "Friday set", creating: true)
        add(names[0], to: "Friday set")
        add(names[1], to: "Friday set")
        let order = [names[2], names[0], names[1]]   // the user's order, not the alphabet

        goBack()
        open("node:collections")
        open("collection:Friday set")
        XCTAssertTrue(app.buttons["preset:\(order[0])"].appears(within: 5))
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
        for _ in 0..<3 {
            tapControl("random")
            XCTAssertTrue(order.contains(current.label), "Random stays in the collection")
            XCTAssertEqual(scopeLine.label, "Friday set · 3")
        }
    }

    // MARK: - R5, S2: removing and deleting preserve presets and favorites
    // Owner rule 7 (2026-11-13): the former single test (42 s) is split in two: removing a preset
    // (R5) and deleting the collection (S2), each with the checks it had.

    /// R5: removing a preset takes it out of the collection only; it is still in Included.
    func testRemovingAPresetKeepsItInTheLibrary() {
        let names = makeFridaySetWithTwoPresets()
        menu(app.buttons["preset:\(names[1])"], "Remove from Collection")
        XCTAssertTrue(poll(5) { self.presetRows == [names[0]] }, "\(presetRows)")
        goBack()
        waitForLabel(app.buttons["collection:Friday set"], "Friday set, 1 preset")
        goBack()
        open("node:included")
        XCTAssertTrue(app.buttons["preset:\(names[1])"].appears(within: 5), "\(names[1]) is still in the library")
    }

    /// S2: deleting a collection that is playing removes only the list; its preset and favorite
    /// stay, and the scope falls back to Included.
    func testDeletingACollectionKeepsItsPresetsAndFavorites() {
        start(reset: true)
        openBrowser()
        let names = openIncludedAndTake(1)
        add(names[0], to: "Friday set", creating: true)
        app.buttons["star:\(names[0])"].tap()
        XCTAssertEqual(app.buttons["star:\(names[0])"].label, "Remove from favorites")

        goBack()
        open("node:collections")
        open("collection:Friday set")
        XCTAssertTrue(app.buttons["preset:\(names[0])"].appears(within: 5))
        XCTAssertEqual(presetRows, names)
        app.buttons["preset:\(names[0])"].tap()   // play the collection, so deleting it moves the scope
        waitForLabel(scopeLine, "Friday set · 1")

        // Delete the collection: only the list goes (S2).
        openBrowser()
        open("node:collections")
        waitForLabel(app.buttons["collection:Friday set"], "Friday set, 1 preset")
        menu(app.buttons["collection:Friday set"], "Delete")
        let confirm = app.buttons["confirmDeleteCollection"].firstMatch
        XCTAssertTrue(confirm.appears(within: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["collectionsEmpty"].appears(within: 5))
        goBack()
        open("node:included")
        XCTAssertTrue(app.buttons["preset:\(names[0])"].appears(within: 5), "\(names[0]) is still in the library")
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
        XCTAssertTrue(app.staticTexts["collectionEmpty"].appears(within: 5))
        XCTAssertTrue(app.buttons["renameCollection"].isHittable)
        open("renameCollection")
        let field = app.textFields["collectionName"]
        XCTAssertTrue(field.appears(within: 5))
        XCTAssertTrue(app.buttons["saveCollectionName"].isHittable)
        app.buttons["Cancel"].tap()
        goBack()
        XCTAssertTrue(app.buttons["newCollection"].appears(within: 5))
        XCTAssertTrue(app.buttons["newCollection"].isHittable)
    }
}
