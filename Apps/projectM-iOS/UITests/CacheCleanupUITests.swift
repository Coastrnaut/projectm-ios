// CacheCleanupUITests.swift — FILE-010-T08 (FILE-010-S4): Settings › Storage › Clear Caches… on the
// simulator with FILE-009's DEBUG fixture container (`-uitestStorageFixture`: known sizes, the real
// stores untouched). The confirmation states the size and what is kept; after Clear, Recordings, Shares
// and exports and Caches show Zero KB and the user-data rows keep their values. Simulator results are
// never device evidence.
import XCTest

@MainActor
final class CacheCleanupUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func row(_ id: String) -> XCUIElement { app.descendants(matching: .any)["storage.\(id)"].firstMatch }

    private func value(_ id: String) -> String { (row(id).value as? String) ?? "" }

    func testClearCachesEmptiesTheCacheCategoriesAndKeepsUserData() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestStorageFixture", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "storage"] + Self.noStore   // Settings opens at Storage (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))

        // Open Settings (see SettingsUITests.openSettings).
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let link = app.buttons["storageLink"]
        XCTAssertTrue(app.reveal(link))
        link.tap()
        XCTAssertTrue(app.navigationBars["Storage"].appears(within: 5))

        XCTAssertTrue(poll(10) { self.value("recordings") == "1 MB" }, "seeded recording: \(value("recordings"))")
        let user = ["photos", "videos", "scenes", "presets", "importedAudio"]
        var before: [String: String] = [:]
        for id in user { before[id] = value(id) }
        XCTAssertEqual(before["photos"], "2 MB")
        XCTAssertNotEqual(value("caches"), "Zero KB")
        XCTAssertNotEqual(value("sharesAndExports"), "Zero KB")

        let clear = app.buttons["storageClearCaches"]
        XCTAssertTrue(app.reveal(clear))
        XCTAssertTrue(poll(5) { clear.isEnabled })
        clear.tap()
        let alert = app.alerts["Clear Caches?"]
        XCTAssertTrue(alert.appears(within: 5), "the confirmation")
        let message = alert.staticTexts.allElementsBoundByIndex.map { (text: XCUIElement) -> String in text.label }.joined(separator: " ")
        XCTAssertTrue(message.contains("Frees "), message)
        XCTAssertTrue(message.contains("Photos, videos, scenes, the show, presets, imported audio and settings are kept."), message)
        alert.buttons["Clear"].firstMatch.tap()   // the alert lists its buttons twice on iOS 27
        XCTAssertTrue(alert.disappears(within: 5))

        XCTAssertTrue(app.staticTexts["storageCleanupResult"].appears(within: 10), "the cleared size")
        XCTAssertFalse(app.staticTexts["storageCleanupFailed"].exists)
        // The nine rows stay loaded above the short Clear Caches section: values read without scrolling.
        XCTAssertTrue(poll(10) { self.value("recordings") == "Zero KB" }, "recordings: \(value("recordings"))")
        XCTAssertEqual(value("sharesAndExports"), "Zero KB")
        XCTAssertEqual(value("caches"), "Zero KB")
        for id in user { XCTAssertEqual(value(id), before[id], "\(id) unchanged") }
    }
}
