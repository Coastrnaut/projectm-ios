// OfflineExportUITests.swift — REC-013-T12 (US1; REC-013-R1, R6, R10, R11; contract C4) on the iOS Simulator: Circular
// Spectrum (`-settings.visual circularSpectrum`, argument domain), Export Video Offline…, Export with the fixture
// shortened to 1 s (`-uitestOfflineExportSeconds 1`, DEBUG); "Exported 30 frames" and the Save…/Share…/Save to Photos
// rows appear; Done closes the sheet. Repeatability is proved by OfflineExportAcceptanceTests. Simulator results are
// never device evidence (Constitution X).
import XCTest

@MainActor
final class OfflineExportUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openSettings() {
        let area = app.otherElements["visualizerTapArea"].firstMatch
        if !app.buttons["settings"].appears(within: 1) { area.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    func testExportOneSecondOfTheFixture() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum", "-uitestOfflineExportSeconds", "1",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXS"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 15), "the Circular Spectrum is shown")
        openSettings()

        let open = app.buttons["offlineExportOpen"]
        XCTAssertTrue(open.isHittable || app.reveal(open), "the Export Video Offline row")
        open.tap()

        let start = app.buttons["offlineExportStart"]
        XCTAssertTrue(start.appears(within: 5), "the export sheet")
        XCTAssertFalse(app.staticTexts["offlineExportUnsupported"].exists)
        start.tap()

        let status = app.staticTexts["offlineExportStatus"]
        XCTAssertTrue(poll(20) { status.exists && status.label == "Exported 30 frames" }, "status: \(status.exists ? status.label : "none")")
        XCTAssertTrue(app.buttons["offlineExportSave"].exists)
        XCTAssertTrue(app.buttons["offlineExportShare"].exists)
        XCTAssertTrue(app.buttons["offlineExportPhotos"].exists)
        app.buttons["offlineExportDone"].tap()
        XCTAssertTrue(poll(5) { !start.exists && !status.exists }, "the sheet closed")
    }
}
