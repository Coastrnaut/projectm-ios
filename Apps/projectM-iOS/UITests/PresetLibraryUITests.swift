// Feature 002 T223 and T233: the preset library browser on the iOS Simulator with the real
// bundled index. Before purchase (`-uitestUnlocked NO`): home rows and counts, drill-down, search
// grouping and cap, Included-only playback, and a locked tap opening the purchase sheet. Unlocked
// (`-uitestUnlocked YES`, no StoreKit): the Fractal › Nested Spiral scope, Next wrapping, Random
// staying inside, and the scope line. Simulator results are never device evidence (Constitution X).
// Shortened 2026-11-13 under owner rule 7: `-autostart inAppPlayback` replaces the notice and chooser
// taps, and waits poll every 0.1 s (UITestWaits.swift) instead of about once a second.
import XCTest

@MainActor
final class PresetLibraryUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// `-autostart inAppPlayback` (Debug) starts the reference track as the chooser's row does.
    private func start(unlocked: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", unlocked ? "YES" : "NO",
                               "-autostart", "inAppPlayback"]
        app.launch()
        XCTAssertTrue(scopeLine.appears(within: 15))
    }

    private var scopeLine: XCUIElement { app.staticTexts["scopeLine"] }
    private var current: XCUIElement { app.staticTexts["currentPreset"] }

    /// Shows the controls if they auto-hid, then taps one.
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

    /// Scrolls the list until a row is on screen (lists build rows lazily).
    private func scrollTo(_ element: XCUIElement) {
        _ = element.appears(within: 2)
        var swipes = 0
        while swipes < 10 && !(element.exists && element.isHittable) { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(element.appears(within: 3), element.debugDescription)
    }

    private func waitForScopeLine(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        if !poll(5, { self.scopeLine.exists && self.scopeLine.label == text }) {
            XCTFail("scope line “\(scopeLine.exists ? scopeLine.label : "<missing>")”, expected “\(text)”", file: file, line: line)
        }
    }

    // MARK: - T223 (before purchase)

    func testHomeRowsCountsAndLocks() {
        start(unlocked: false)
        waitForScopeLine("Included · 28")
        openBrowser()
        XCTAssertEqual(app.buttons["node:included"].label, "Included, 28 presets")
        XCTAssertEqual(app.buttons["node:cream-of-the-crop"].label, "Cream of the Crop, 9,728 presets, locked")
        XCTAssertEqual(app.buttons["node:projectm-classic"].label, "projectM Classic, 2,569 presets, locked")
        XCTAssertEqual(app.buttons["node:milkdrop-original"].label, "Milkdrop Original, 487 presets, locked")
        XCTAssertEqual(app.buttons["node:en-d"].label, "En D, 35 presets, locked")
        XCTAssertTrue(app.buttons["node:all"].exists)
    }

    func testDrillDownAndALockedTapOpensThePurchaseSheet() {
        start(unlocked: false)
        openBrowser()
        app.buttons["node:cream-of-the-crop"].tap()
        XCTAssertTrue(app.buttons["unlockBanner"].appears(within: 5), "locked pack offers the unlock")
        let fractal = app.buttons["node:cream-of-the-crop/Fractal"]
        scrollTo(fractal)
        fractal.tap()
        let spiral = app.buttons["node:cream-of-the-crop/Fractal/Nested Spiral"]
        XCTAssertTrue(app.buttons["node:cream-of-the-crop/Fractal/Blobby"].appears(within: 5))
        scrollTo(spiral)
        spiral.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch
        XCTAssertTrue(row.appears(within: 5))
        XCTAssertTrue(row.label.hasSuffix(", locked"), row.label)
        let before = current.label
        row.tap()
        XCTAssertTrue(app.otherElements["purchaseSheet"].appears(within: 5) || app.collectionViews["purchaseSheet"].exists,
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
        XCTAssertTrue(field.appears(within: 5))
        field.tap()
        field.typeText("a")
        XCTAssertTrue(app.staticTexts["refineSearch"].appears(within: 5), "a broad query is capped (FR-113)")
        let header = NSPredicate(format: "label ==[c] %@", "Included")
        XCTAssertTrue(app.staticTexts.matching(header).firstMatch.appears(within: 5),
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
        waitForScopeLine("Cream of the Crop · 9728")
        openBrowser()
        app.buttons["node:cream-of-the-crop"].tap()
        let fractal = app.buttons["node:cream-of-the-crop/Fractal"]
        scrollTo(fractal)
        fractal.tap()
        let spiral = app.buttons["node:cream-of-the-crop/Fractal/Nested Spiral"]
        XCTAssertTrue(app.buttons["node:cream-of-the-crop/Fractal/Blobby"].appears(within: 5))
        scrollTo(spiral)
        XCTAssertEqual(spiral.label, "Nested Spiral, 178 presets")
        spiral.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'"))
        XCTAssertTrue(rows.firstMatch.appears(within: 5))
        let first = String(rows.firstMatch.identifier.dropFirst("preset:".count))
        rows.firstMatch.tap()   // choosing a preset closes the browser
        waitForScopeLine("Fractal › Nested Spiral · 178")
        XCTAssertEqual(current.label, first)
        tapControl("previous")
        XCTAssertNotEqual(current.label, first, "Previous from the first wraps to the last")
        tapControl("next")
        XCTAssertEqual(current.label, first, "and Next wraps back")
        for _ in 0..<5 {
            tapControl("random")
            XCTAssertEqual(scopeLine.label, "Fractal › Nested Spiral · 178", "Random stays in the scope")
        }
    }
}
