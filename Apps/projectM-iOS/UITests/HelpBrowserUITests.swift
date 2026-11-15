// HelpBrowserUITests.swift — UIX-014-T08, T09 (UIX-014-S3, R7): Settings › Help on the simulator. Opens the list,
// searches "midi" and "flash", opens two articles and checks their title headings (header trait); a second launch at an
// accessibility text size opens one article. Help needs no network at all; Airplane Mode on D1 is UIX-014-T12
// ({device}). Simulator results are never device evidence.
import XCTest

@MainActor
final class HelpBrowserUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openHelp(extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "help"] + extra + Self.noStore   // Settings opens at Help (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let link = app.buttons["helpLink"]
        XCTAssertTrue(app.reveal(link))
        link.tap()
        XCTAssertTrue(app.navigationBars["Help"].appears(within: 5))
    }

    private func search(_ text: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.appears(within: 5), "the search field")
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != "Search help" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    private func assertHeading(_ title: String) {
        let heading = app.staticTexts.matching(identifier: "helpHeading").matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(heading.appears(within: 5), "heading \(title)")   // helpHeading: the element with the header trait
    }

    func testSearchAndOpenTwoArticles() {
        openHelp()
        XCTAssertTrue(app.buttons["help.getting-started"].appears(within: 5), "the list starts with Getting started")

        search("midi")
        let midi = app.buttons["help.midi-osc"]
        XCTAssertTrue(midi.appears(within: 5))
        XCTAssertTrue(poll(5) { !self.app.buttons["help.getting-started"].exists }, "only matching articles are listed")
        midi.tap()
        assertHeading("MIDI and OSC")
        XCTAssertTrue(app.otherElements["helpArticle.midi-osc"].exists || app.scrollViews["helpArticle.midi-osc"].exists)
        app.navigationBars.buttons.firstMatch.tap()   // back to Help

        search("flash")
        let safety = app.buttons["help.accessibility-safety"]
        XCTAssertTrue(safety.appears(within: 5))
        safety.tap()
        assertHeading("Accessibility and sensory safety")
        app.navigationBars.buttons.firstMatch.tap()

        search("zzzz")
        XCTAssertTrue(app.staticTexts["helpNoMatch"].appears(within: 5), "No help articles match")
    }

    func testArticleOpensAtAnAccessibilityTextSize() {
        openHelp(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        let privacy = app.buttons["help.privacy"]
        XCTAssertTrue(app.reveal(privacy))
        privacy.tap()
        assertHeading("Privacy")
    }
}
