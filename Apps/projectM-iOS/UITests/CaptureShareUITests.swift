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
}
