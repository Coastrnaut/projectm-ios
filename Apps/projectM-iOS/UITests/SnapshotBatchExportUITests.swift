// SnapshotBatchExportUITests.swift — REC-002-T10 (US1; REC-002-R1, R5, S5) on the iOS Simulator: Circular Spectrum
// (`-settings.visual circularSpectrum`, argument domain), five Save Snapshot taps, Export Images…, Export; the DEBUG
// probe lists five PNGs named 01-Snapshot 1.png … 05-Snapshot 5.png at 1920 × 1080; Done closes the sheet. The
// no-write and tricky-name proofs are SnapshotBatchExportAcceptanceTests. Simulator results are never device evidence
// (Constitution X).
import XCTest

@MainActor
final class SnapshotBatchExportUITests: XCTestCase {
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

    func testExportFiveSnapshots() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXS"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 15), "the Circular Spectrum is shown")
        openSettings()

        let save = app.buttons["snapshotSave"]
        XCTAssertTrue(save.isHittable || app.reveal(save), "the Snapshots rows")
        for _ in 0..<5 { save.tap() }
        let open = app.buttons["snapshotBatchOpen"]
        XCTAssertTrue(open.isHittable || app.reveal(open), "the Export Images row")
        open.tap()

        let export = app.buttons["snapshotBatchExport"]
        XCTAssertTrue(export.appears(within: 5), "the export sheet")
        XCTAssertEqual(export.label, "Export 5 Images")
        export.tap()

        let probe = app.staticTexts["snapshotBatchProbe"]
        let expected = (1...5).map { (i: Int) -> String in "0\(i)-Snapshot \(i).png 1920x1080" }.joined(separator: "|")
        XCTAssertTrue(poll(15) { probe.exists && probe.label == expected }, "files: \(probe.exists ? probe.label : "none")")
        XCTAssertTrue(app.buttons["snapshotBatchSave"].exists)
        XCTAssertTrue(app.staticTexts["snapshotBatchStatus"].label == "Exported 5 images")
        app.buttons["snapshotBatchDone"].tap()
        XCTAssertTrue(poll(5) { !export.exists && !probe.exists }, "the sheet closed")
    }
}
