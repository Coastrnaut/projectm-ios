// CaptureShareUITests.swift — REC-012-T09 on the iOS Simulator: Save Frame → "Frame ready" → Share… →
// simulated cancel keeps the frame offered and empties the sharing folder; Record → Stop → "Recording
// ready" → Share… → simulated completion empties it too. The DEBUG `-uitestShareSimulation` option makes
// the real temporary copy but replaces the system share sheet (out of process, not drivable) with two
// buttons; `captureShareProbe` reads "copies=<n> frame=<yes|no> recording=<yes|no> last=<outcome>".
// Asserted by content, never by time. Simulator results are never device evidence (Constitution X).
// Owner rule 7: under 30 s.
import XCTest

@MainActor
final class CaptureShareUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// See CameraUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private var probe: String { (app.staticTexts["captureShareProbe"].value as? String) ?? "" }

    func testCancelledShareKeepsTheFrameAndCompletedShareCleansUp() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "photo", "-uitestSeedPhoto", "solid",
                               "-uitestShareSimulation"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))
        XCTAssertTrue(poll(5) { self.probe.hasPrefix("copies=0 frame=no recording=no") }, "probe: \(probe)")

        // A frame: offered, shared, cancelled (the row's acceptance).
        showControls()
        app.buttons["saveFrame"].tap()
        let png = app.buttons["PNG"].firstMatch
        XCTAssertTrue(png.appears(within: 5), "the format choice")
        png.tap()
        let frameShare = app.buttons["frameResultShare"]
        XCTAssertTrue(frameShare.appears(within: 10), "the Frame ready panel")
        XCTAssertTrue(app.buttons["frameResultSave"].exists)
        XCTAssertTrue(app.buttons["frameResultDiscard"].exists)
        frameShare.tap()
        XCTAssertTrue(poll(5) { self.probe.hasPrefix("copies=1 frame=yes") }, "probe: \(probe)")
        app.buttons["simulateShareCancelled"].tap()
        XCTAssertTrue(poll(5) { self.probe == "copies=0 frame=yes recording=no last=cancelled" }, "probe: \(probe)")
        XCTAssertTrue(frameShare.exists, "the frame is still offered after the cancel")
        XCTAssertFalse(app.descendants(matching: .any)["captureShareNotice"].firstMatch.exists, "no notice on cancel")

        // A recording: offered, shared, completed.
        showControls()
        app.buttons["record"].tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(indicator.appears(within: 5), "the recording indicator")
        XCTAssertTrue(poll(10) { indicator.label.hasPrefix("Recording, 0:01") || indicator.label.hasPrefix("Recording, 0:02") },
                      indicator.label)
        showControls()
        app.buttons["record"].tap()
        let recordingShare = app.buttons["recordingResultShare"]
        XCTAssertTrue(recordingShare.appears(within: 10), "the Recording ready panel")
        recordingShare.tap()
        XCTAssertTrue(poll(5) { self.probe.hasPrefix("copies=1 frame=yes recording=yes") }, "probe: \(probe)")
        app.buttons["simulateShareCompleted"].tap()
        XCTAssertTrue(poll(5) { self.probe == "copies=0 frame=yes recording=yes last=completed" }, "probe: \(probe)")
        XCTAssertEqual(app.staticTexts["captureShareNoticeText"].label, "Shared.")

        // Discard ends both offers.
        app.buttons["recordingResultDiscard"].tap()
        app.buttons["frameResultDiscard"].tap()
        XCTAssertTrue(poll(5) { self.probe == "copies=0 frame=no recording=no last=completed" }, "probe: \(probe)")
    }

    /// QA-011 rerun 4 (D3, iPad A16 portrait): with the performance overlay on, the overlay was drawn above "Frame
    /// ready" and covered Save…, which accessibility could not reach (hit point {-1, -1}), so the exporter never
    /// opened. The overlay now sits below the panels: every panel button is hittable with the overlay shown.
    func testFrameReadyButtonsStayReachableWithThePerformanceOverlay() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "photo", "-uitestSeedPhoto", "solid",
                               "-settings.performanceOverlay", "YES", "-uitestShareSimulation"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(overlay.appears(within: 10), "the performance overlay shows")
        showControls()
        app.buttons["saveFrame"].tap()
        let png = app.buttons["PNG"].firstMatch
        XCTAssertTrue(png.appears(within: 5), "the format choice")
        png.tap()
        XCTAssertTrue(app.buttons["frameResultSave"].appears(within: 10), "the Frame ready panel")
        for id in ["frameResultSave", "frameResultShare", "frameResultPhotos", "frameResultDiscard"] {
            XCTAssertTrue(app.buttons[id].isHittable, "\(id) is reachable with the overlay at \(overlay.frame)")
        }
        app.buttons["frameResultDiscard"].tap()
    }

    /// The Files dialog is up: its Save (exporter) or Move (mover) button, in the system's remote view.
    private var filesDialogShown: Bool { app.buttons["Save"].firstMatch.exists || app.buttons["Move"].firstMatch.exists }

    /// Closes the Files dialog and waits until it is gone. Its close button differs by layout: the ✕ "Close" on
    /// iPadOS 26 (a "Cancel" exists there but is not the visible one), "Cancel" on older layouts, and none at all on the
    /// iPhone (iOS 26.5) when the exporter opens inside "On My iPhone" (only "Browse", More and Save; 2026-11-19). Without
    /// a hittable close button the sheet is pulled down from its top, the system's own dismissal. A close that the
    /// remote view drops (iPad 26.5, round 2, once) is retried.
    private func closeFilesDialog() -> Bool {
        let buttons = ["Close", "Cancel"].map { app.buttons[$0].firstMatch }
        for _ in 0..<3 {
            if poll(3, { buttons.contains { $0.exists && $0.isHittable } }) {
                buttons.first { $0.exists && $0.isHittable }?.tap()
            } else {
                let window = app.windows.firstMatch
                let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                from.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
            }
            if poll(5, { !self.filesDialogShown }) { return true }
        }
        return false
    }

    /// QA-011 pass 6 (D3, iPadOS 26.5, 2026-11-19): Save… on "Frame ready" opened no Files exporter at all (three passes
    /// in a row; REC-001-T19 "Files: no Save button"), while the recording's Save… (the file mover) opened. Both file
    /// dialogs were modifiers of one view, and on iPadOS 26 the outer one (the mover) shadowed the exporter; this test
    /// failed on the iPadOS 26.5 simulator before the fix. Save… must open the exporter twice in a row and a close keeps
    /// the frame offered. Split from the mover's check (2026-11-19) to stay under 30 s: the out-of-process Files
    /// dialog takes 4-9 s to appear on the simulator.
    func testSaveOpensTheFilesExporterTwice() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "photo", "-uitestSeedPhoto", "solid"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        app.buttons["saveFrame"].tap()
        let png = app.buttons["saveFramePNG"].firstMatch
        XCTAssertTrue(png.appears(within: 5), "the format choice")
        png.tap()
        let save = app.buttons["frameResultSave"]
        XCTAssertTrue(save.appears(within: 10), "the Frame ready panel")
        for round in 1...2 {
            XCTAssertTrue(poll(5) { save.isHittable }, "round \(round): Save… is reachable")
            save.tap()
            XCTAssertTrue(poll(10) { self.filesDialogShown }, "round \(round): the Files exporter opens")
            XCTAssertTrue(closeFilesDialog(), "round \(round): the exporter can be closed")
            XCTAssertTrue(poll(5) { save.exists }, "round \(round): a close keeps the frame offered")
        }
        app.buttons["frameResultDiscard"].tap()
        XCTAssertTrue(poll(5) { !save.exists }, "discarded")
    }

    /// The recording's Save… (REC-003, the Files mover) still opens beside the frame's exporter (see above).
    func testRecordingSaveOpensTheFilesMover() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "photo", "-uitestSeedPhoto", "solid"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        app.buttons["record"].tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(indicator.appears(within: 5), "the recording indicator")
        XCTAssertTrue(poll(10) { indicator.label.hasPrefix("Recording, 0:01") || indicator.label.hasPrefix("Recording, 0:02") },
                      indicator.label)
        showControls()
        app.buttons["record"].tap()
        let moverSave = app.buttons["recordingResultSave"]
        XCTAssertTrue(moverSave.appears(within: 10), "the Recording ready panel")
        moverSave.tap()
        XCTAssertTrue(poll(10) { self.filesDialogShown }, "the Files mover opens")
        XCTAssertTrue(closeFilesDialog(), "the mover can be closed")
    }
}
