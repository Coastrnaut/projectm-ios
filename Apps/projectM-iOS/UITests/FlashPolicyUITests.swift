// ACC-002-T15 (S2): the known high-flash fixture is flagged before its scene loads, on the iOS
// Simulator with the real engine. The app imports the checked-in fixture
// (Packages/PresetLibrary/Tests/PresetLibraryTests/FlashFixtures/high-flash.milk, written for this
// repository) through `-uitestImportPreset`, the Files picker's code path; Reduce flashing is on
// through the launch argument `-settings.reduceFlashing <true/>` (a Bool in the argument domain).
// Simulator only (the app reads the test's file from the host); never device evidence
// (Constitution X). Waits poll (owner rule 7).
import XCTest

@MainActor
final class FlashPolicyUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private var folder: URL?

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    /// The checked-in fixture, copied under the name the library will show ("Strobe" by "Fixture").
    private func fixtureCopy() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("Packages/PresetLibrary/Tests/PresetLibraryTests/FlashFixtures/high-flash.milk")
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("acc002-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        let copy = folder.appendingPathComponent("Fixture - Strobe.milk")
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }

    private var current: XCUIElement { app.staticTexts["currentPreset"] }

    /// Shows the controls with a fresh 5 s auto-hide (see NativeVisualUITests.showControls).
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func dismissImportAlert() {
        let alert = app.alerts["Import Preset"]
        if alert.exists { alert.buttons["OK"].tap() }
    }

    /// Opens the browser's My Presets list and returns the fixture's row.
    private func fixtureRow() -> XCUIElement {
        showControls()
        app.buttons["presets"].tap()
        XCTAssertTrue(app.buttons["node:included"].appears(within: 10), "library home")
        let myPresets = app.buttons["node:myPresets"]
        for _ in 0..<4 { if myPresets.exists && myPresets.isHittable { break }; app.swipeUp() }
        myPresets.tap()
        let row = app.buttons["preset:Strobe"]
        XCTAssertTrue(poll(20) { self.dismissImportAlert(); return row.exists && !self.app.alerts["Import Preset"].exists },
                      "the imported fixture is listed")
        return row
    }

    func testTheHighFlashFixtureIsFlaggedBeforeItLoads() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's file from the host; simulator only")
        #else
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.reduceFlashing", "<true/>",   // a plist Bool: AppSettings reads it `as? Bool`
                               "-uitestUnlocked", "NO",
                               "-uitestImportPreset", try fixtureCopy().path]
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        XCTAssertTrue(poll(10) { !self.current.label.isEmpty }, "a built-in preset plays")
        let before = current.label
        XCTAssertNotEqual(before, "Strobe")

        // R7: the row says so in words and to VoiceOver.
        var row = fixtureRow()
        XCTAssertEqual(row.label, "Strobe, by Fixture, may flash")

        // R6: choosing it warns first; nothing loads; Cancel keeps the scene and the browser.
        row.tap()
        let warning = app.alerts["May flash"]
        XCTAssertTrue(warning.appears(within: 5), "the warning appears before the scene loads")
        XCTAssertTrue(warning.staticTexts["“Strobe” may contain fast flashing. Reduce flashing still limits flashes while it plays."].exists)
        XCTAssertFalse(row.label.contains("current preset"), "not loaded while the warning is up")
        warning.buttons["Cancel"].firstMatch.tap()   // the alert lists its buttons twice in the tree
        XCTAssertTrue(warning.disappears(within: 5))
        XCTAssertTrue(row.exists, "the browser stays open after Cancel")
        app.buttons["Done"].firstMatch.tap()
        showControls()
        XCTAssertEqual(current.label, before, "Cancel loaded nothing")

        // Load Anyway loads it and closes the browser.
        row = fixtureRow()
        row.tap()
        XCTAssertTrue(warning.appears(within: 5))
        warning.buttons["Load Anyway"].firstMatch.tap()
        XCTAssertTrue(row.disappears(within: 10), "the browser closes")
        showControls()
        XCTAssertTrue(poll(10) { self.current.label == "Strobe" }, "found “\(current.label)”")
        #endif
    }
}
