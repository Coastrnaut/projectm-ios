// PRE-008-T13 (spec PRE-008-S5): a smart collection on the iOS Simulator. Create one from the Included pack,
// see its count with the Smart marker, edit its rules (add Favorites, All) and see the count change. Launched
// with the fixed fake entitlement (`-uitestUnlocked NO`, no StoreKit) and the reset flag; Included presets only.
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class PresetSmartCollectionUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func tap(_ id: String) {
        let element = app.buttons[id]
        if !(element.appears(within: 3) && element.isHittable) { app.reveal(element) }
        XCTAssertTrue(element.appears(within: 3), id)
        element.tap()
    }

    /// The number in "N presets match" (or "1 preset matches").
    private func draftCount() -> Int {
        let text = app.staticTexts["smartDraftCount"]
        XCTAssertTrue(text.appears(within: 5))
        return Int(text.label.split(separator: " ").first?.replacingOccurrences(of: ",", with: "") ?? "") ?? -1
    }

    func testCreatingASmartCollectionAndEditingItsRulesChangesTheCount() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))
        app.tapFreshControl("presets")
        tap("node:collections")

        // Create: name, the Included pack; the live count shows before saving.
        tap("newSmartCollection")
        let name = app.textFields["smartName"]
        XCTAssertTrue(name.appears(within: 5))
        name.tap()
        name.typeText("Mine")
        XCTAssertEqual(draftCount(), 0, "no rule: nothing")
        tap("smartRule:pack:included")
        let included = draftCount()
        XCTAssertGreaterThan(included, 0)
        tap("smartSave")

        let row = app.buttons["smartCollection:Mine"]
        XCTAssertTrue(row.appears(within: 5))
        XCTAssertTrue(poll(5) { row.label.hasPrefix("Mine, smart collection, \(included) ") }, row.label)

        // Edit: add Favorites (match All). Nothing is a favorite after the reset, so the count drops to 0.
        row.tap()
        tap("editSmartRules")
        tap("smartRule:favorite")
        XCTAssertEqual(draftCount(), 0)
        tap("smartSave")
        XCTAssertTrue(app.staticTexts["smartCollectionEmpty"].appears(within: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(poll(5) { row.exists && row.label == "Mine, smart collection, 0 presets" }, row.label)
    }
}
