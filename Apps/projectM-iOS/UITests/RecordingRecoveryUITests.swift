// RecordingRecoveryUITests.swift — REC-016-T11 on the iOS Simulator: the DEBUG `-uitestWriterFault append:10` option
// makes every append after the tenth fail. The recording stops by itself, the "Recording ready" panel offers the part
// recorded before the failure with the write-error notice, and the DEBUG probe reads it back with 10 frames. Asserted
// by content, never by time; the waits are ceilings for a slow shared Mac. Simulator results are never device
// evidence (Constitution X). Owner rule 7: under 30 s.
import XCTest

@MainActor
final class RecordingRecoveryUITests: XCTestCase {
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

    private var probe: String { (app.staticTexts["videoRecordingProbe"].value as? String) ?? "" }

    func testWriterFailureOffersThePartRecordedBeforeIt() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "photo", "-uitestSeedPhoto", "solid",
                               "-uitestWriterFault", "append:10"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))
        showControls()
        app.buttons["record"].tap()
        XCTAssertTrue(app.buttons["recordingResultShare"].appears(within: 15), "the Recording ready panel")
        XCTAssertEqual(app.staticTexts["videoRecordingNoticeText"].label,
                       "Recording stopped because of a write error. The part recorded before it was kept.")
        XCTAssertFalse(app.descendants(matching: .any)["recordingIndicator"].firstMatch.exists, "the recording ended")
        XCTAssertTrue(poll(10) { self.probe.hasPrefix("video ") }, "probe: \(probe)")
        XCTAssertTrue(probe.contains("frames=10 "), "probe: \(probe)")
        app.buttons["recordingResultDiscard"].tap()
        XCTAssertFalse(app.buttons["recordingResultShare"].appears(within: 2))
    }
}
