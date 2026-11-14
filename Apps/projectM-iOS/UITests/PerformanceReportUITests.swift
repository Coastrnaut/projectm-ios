// PerformanceReportUITests.swift — PERF-012-T14 (contract performance-report-export.md C2, C3): Settings opens at
// Performance; "Export performance report" makes one share copy and (with `-uitestShareSimulation`, REC-012-R14) shows
// the simulation buttons instead of the out-of-process sheet; "completed" shows "Shared." and deletes the copy.
// Simulator results are never device evidence; the D1 export is the {device} task PERF-012-T17. Budget: under 30 s.
import XCTest

@MainActor
final class PerformanceReportUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testExportSharesOneCopyAndDeletesIt() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestShareSimulation",
                               "-uitestSettingsSection", "performanceReport"] + Self.noStore   // owner rule 7
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let controls = app.otherElements["controls"]
        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
        app.buttons["settings"].tap()

        let export = app.buttons["performanceReport.export"]
        XCTAssertTrue(app.reveal(export), "Settings → Performance → Export performance report")
        let probe = app.staticTexts["performanceReport.probe"]
        XCTAssertTrue(probe.exists)
        XCTAssertTrue(probe.label.hasPrefix("copies=0"), probe.label)

        export.tap()   // S4: one tap after opening Performance
        let completed = app.buttons["simulateShareCompleted"]
        XCTAssertTrue(completed.appears(within: 5), "the share sheet stand-in")
        XCTAssertTrue(poll(3) { probe.label.hasPrefix("copies=1") }, probe.label)
        completed.tap()
        XCTAssertTrue(app.staticTexts["performanceReport.notice"].appears(within: 3), "Shared.")
        XCTAssertTrue(poll(3) { probe.label == "copies=0 last=completed" }, probe.label)
    }
}
