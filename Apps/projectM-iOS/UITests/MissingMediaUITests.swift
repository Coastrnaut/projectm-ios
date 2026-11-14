// MissingMediaUITests.swift — MED-013-T14 on the iOS Simulator (MED-013-S5): with the DEBUG seed
// (`-uitestMissingMediaSeed`: scenes "Opening" and "Slides" use photo P, whose file is gone; "Opening" is
// applied), the "Missing media" placeholder shows; its Relink… opens Missing Media, which lists the photo
// "Used by 2 scenes and 2 cues"; Find Missing Media in Folder… (pointed at the seed's backup folder: the
// folder picker cannot be automated) relinks it by checksum, the list empties and, after Done, the
// placeholder is gone. Simulator results are never device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class MissingMediaUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testThePlaceholderLeadsToMissingMediaAndAFolderSearchRelinksThePhoto() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestMissingMediaSeed", "-autostart", "inAppPlayback"]
            + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))

        let tile = app.descendants(matching: .any)["missingMediaPlaceholder"].firstMatch
        XCTAssertTrue(tile.appears(within: 5), "the placeholder is shown")
        XCTAssertEqual(tile.label, "Missing media")
        XCTAssertEqual(tile.value as? String, "Opening: its photo or video is no longer stored")
        app.buttons["missingMediaPlaceholderRelink"].tap()

        XCTAssertTrue(app.navigationBars["Missing Media"].appears(within: 5))
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'missingMedia.'")).firstMatch
        XCTAssertTrue(row.appears(within: 5), "the missing photo is listed")
        XCTAssertEqual(row.label, "Photo")
        XCTAssertEqual(row.value as? String, "Used by 2 scenes and 2 cues")

        app.buttons["missingMediaFind"].tap()
        let result = app.staticTexts["missingMediaResult"]
        XCTAssertTrue(result.appears(within: 10), "the search reports")
        XCTAssertEqual(result.label, "Relinked 1 missing item by checksum.")
        XCTAssertTrue(app.staticTexts["missingMediaEmpty"].appears(within: 5), "nothing is missing any more")

        app.buttons["missingMediaDone"].tap()
        XCTAssertTrue(app.navigationBars["Missing Media"].disappears(within: 5))
        XCTAssertTrue(tile.disappears(within: 5), "the placeholder clears once the photo resolves")
    }
}
