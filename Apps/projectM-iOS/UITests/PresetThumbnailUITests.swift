// PresetThumbnailUITests.swift — PRE-001-T12 (S5): the browser shows a thumbnail picture for its first
// rows, and they come back when the folder is opened again; the row's spoken label is unchanged (R12).
// `-uitestThumbnailFixture YES` draws through the same cache and PNG encoder with an instant fixture
// renderer: real drawings cost seconds each on the simulator and are tested in ANGLERendering
// (PresetThumbnailRunnerTests). Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class PresetThumbnailUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var thumbnails: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'thumbnail:'"))
    }

    private func openIncluded() {
        let included = app.buttons["node:included"]
        XCTAssertTrue(included.appears(within: 10), "library home")
        included.tap()
    }

    func testTheFirstRowsShowThumbnailsAndKeepThemOnTheSecondBrowse() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO",
                               "-autostart", "inAppPlayback", "-uitestThumbnailFixture", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 15))
        app.tapFreshControl("presets")
        openIncluded()

        XCTAssertTrue(poll(10) { self.thumbnails.count >= 3 }, "thumbnails for the first rows (\(thumbnails.count))")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch
        XCTAssertTrue(row.exists)
        XCTAssertFalse(row.label.localizedCaseInsensitiveContains("thumbnail"), "row label unchanged: \(row.label)")
        XCTAssertFalse(row.label.localizedCaseInsensitiveContains("sparkles"), "no symbol name spoken: \(row.label)")
        let firstIDs = Set((0..<3).map { thumbnails.element(boundBy: $0).identifier })

        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to the library home
        openIncluded()
        XCTAssertTrue(poll(5) { self.thumbnails.count >= 3 }, "second browse")
        let secondIDs = Set((0..<3).map { thumbnails.element(boundBy: $0).identifier })
        XCTAssertEqual(firstIDs, secondIDs)
    }
}
