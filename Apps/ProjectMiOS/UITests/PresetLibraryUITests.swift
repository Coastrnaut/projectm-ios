// Feature 002 T223 and T233: the preset library browser on the iOS Simulator with the real
// bundled index. Before purchase (`-uitestUnlocked NO`): home rows and counts, drill-down, search
// grouping and cap, Included-only playback, and a locked tap opening the purchase sheet. Unlocked
// (`-uitestUnlocked YES`, no StoreKit): the Fractal › Nested Spiral scope, Next wrapping, Random
// staying inside, and the scope line. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class PresetLibraryUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func start(unlocked: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", unlocked ? "YES" : "NO"]
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        acknowledge.tap()
        let inApp = app.buttons["In-App Playback"]
        XCTAssertTrue(inApp.waitForExistence(timeout: 10))
        inApp.tap()
        XCTAssertTrue(scopeLine.waitForExistence(timeout: 10))
    }

    private var scopeLine: XCUIElement { app.staticTexts["scopeLine"] }
    private var current: XCUIElement { app.staticTexts["currentPreset"] }

    /// Shows the controls if they auto-hid, then taps one.
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

    /// Scrolls the list until a row is on screen (lists build rows lazily).
    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<10 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 3), element.debugDescription)
    }

    private func waitForScopeLine(_ text: String) {
        let predicate = NSPredicate(format: "label == %@", text)
        expectation(for: predicate, evaluatedWith: scopeLine)
        waitForExpectations(timeout: 5)
    }

    // MARK: - T223 (before purchase)

    func testHomeRowsCountsAndLocks() {
        start(unlocked: false)
        waitForScopeLine("Included · 28")
        openBrowser()
        XCTAssertEqual(app.buttons["node:included"].label, "Included, 28 presets")
        XCTAssertEqual(app.buttons["node:cream-of-the-crop"].label, "Cream of the Crop, 9,795 presets, locked")
        XCTAssertEqual(app.buttons["node:projectm-classic"].label, "projectM Classic, 2,584 presets, locked")
        XCTAssertEqual(app.buttons["node:milkdrop-original"].label, "Milkdrop Original, 497 presets, locked")
        XCTAssertEqual(app.buttons["node:en-d"].label, "En D, 37 presets, locked")
        XCTAssertTrue(app.buttons["node:all"].exists)
    }

    func testDrillDownAndALockedTapOpensThePurchaseSheet() {
        start(unlocked: false)
        openBrowser()
        app.buttons["node:cream-of-the-crop"].tap()
        XCTAssertTrue(app.buttons["unlockBanner"].waitForExistence(timeout: 5), "locked pack offers the unlock")
        let fractal = app.buttons["node:cream-of-the-crop/Fractal"]
        scrollTo(fractal)
        fractal.tap()
        let spiral = app.buttons["node:cream-of-the-crop/Fractal/Nested Spiral"]
        XCTAssertTrue(app.buttons["node:cream-of-the-crop/Fractal/Blobby"].waitForExistence(timeout: 5))
        scrollTo(spiral)
        spiral.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.hasSuffix(", locked"), row.label)
        let before = current.label
        row.tap()
        XCTAssertTrue(app.otherElements["purchaseSheet"].waitForExistence(timeout: 5) || app.collectionViews["purchaseSheet"].exists,
                      "a locked preset opens the purchase sheet (FR-106)")
        XCTAssertTrue(app.buttons["buyLibrary"].exists)
        XCTAssertTrue(app.buttons["restorePurchases"].exists)
        app.buttons["Close"].tap()
        XCTAssertEqual(current.label, before, "nothing locked played")
    }

    func testSearchIsGroupedAndCapped() {
        start(unlocked: false)
        openBrowser()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("a")
        XCTAssertTrue(app.staticTexts["refineSearch"].waitForExistence(timeout: 5), "a broad query is capped (FR-113)")
        let header = NSPredicate(format: "label ==[c] %@", "Included")
        XCTAssertTrue(app.staticTexts.matching(header).firstMatch.waitForExistence(timeout: 5),
                      "results are grouped by pack, Included first")
    }

    func testIncludedOnlyPlaybackWithNextAndRandom() {
        start(unlocked: false)
        waitForScopeLine("Included · 28")
        var seen: Set<String> = [current.label]
        for _ in 0..<5 { tapControl("next"); seen.insert(current.label) }
        for _ in 0..<5 { tapControl("random"); seen.insert(current.label) }
        XCTAssertGreaterThan(seen.count, 1)
        XCTAssertEqual(scopeLine.label, "Included · 28", "still Included; nothing locked plays (SC-107)")
    }

    // MARK: - T233 (unlocked)

    func testFolderScopeNextWrapsAndRandomStaysInside() {
        start(unlocked: true)
        waitForScopeLine("Cream of the Crop · 9795")
        openBrowser()
        app.buttons["node:cream-of-the-crop"].tap()
        let fractal = app.buttons["node:cream-of-the-crop/Fractal"]
        scrollTo(fractal)
        fractal.tap()
        let spiral = app.buttons["node:cream-of-the-crop/Fractal/Nested Spiral"]
        XCTAssertTrue(app.buttons["node:cream-of-the-crop/Fractal/Blobby"].waitForExistence(timeout: 5))
        scrollTo(spiral)
        XCTAssertEqual(spiral.label, "Nested Spiral, 179 presets")
        spiral.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let first = String(rows.firstMatch.identifier.dropFirst("preset:".count))
        rows.firstMatch.tap()   // choosing a preset closes the browser
        waitForScopeLine("Fractal › Nested Spiral · 179")
        XCTAssertEqual(current.label, first)
        tapControl("previous")
        XCTAssertNotEqual(current.label, first, "Previous from the first wraps to the last")
        tapControl("next")
        XCTAssertEqual(current.label, first, "and Next wraps back")
        for _ in 0..<5 {
            tapControl("random")
            XCTAssertEqual(scopeLine.label, "Fractal › Nested Spiral · 179", "Random stays in the scope")
        }
    }
}
