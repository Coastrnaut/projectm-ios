// RecordingDiskGuardUITests.swift — REC-015-T14 on the iOS Simulator: the DEBUG `-uitestStorage`
// option fakes the free-storage readings (1 s interval). `low`: Record is refused with the notice and
// nothing starts. `dropAfter:3`: the recording starts, the third periodic reading is low, the
// recording stops with the low-storage notice, the "Recording ready" panel offers it, and the DEBUG
// probe reads the offered file back as a video. Asserted by content, never by time; the waits are
// ceilings for a slow shared Mac. Simulator results are never device evidence (Constitution X).
// Owner rule 7: under 30 s each.
import XCTest

@MainActor
final class RecordingDiskGuardUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(storage: String) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "photo", "-uitestSeedPhoto", "solid",
                               "-uitestStorage", storage] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))
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

    /// REC-015-S1: not enough free storage → Record says so and nothing starts.
    func testLowStorageRefusesRecord() {
        launch(storage: "low")
        showControls()
        app.buttons["record"].tap()
        XCTAssertTrue(poll(5) { self.probe == "refused: lowStorage" }, "probe: \(probe)")
        XCTAssertEqual(app.staticTexts["videoRecordingNoticeText"].label,
                       "There isn't enough free storage to record. Free up space and try again.")
        XCTAssertFalse(app.descendants(matching: .any)["recordingIndicator"].firstMatch.exists)
        XCTAssertFalse(app.buttons["recordingResultShare"].exists)
    }

    /// REC-015-S2 in the app: the free storage drops during the recording → it stops by itself with
    /// the low-storage notice and the finished file is offered and plays.
    func testStorageDropStopsAndOffersAPlayableFile() {
        launch(storage: "dropAfter:3")   // the pre-flight reading and the first two periodic ones are ample
        showControls()
        app.buttons["record"].tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(indicator.appears(within: 5), "the recording indicator")
        XCTAssertTrue(app.buttons["recordingResultShare"].appears(within: 15), "the Recording ready panel")
        XCTAssertEqual(app.staticTexts["videoRecordingNoticeText"].label, "Recording stopped because storage is almost full.")
        XCTAssertFalse(indicator.exists, "the indicator is gone")
        XCTAssertTrue(poll(10) { self.probe.hasPrefix("video ") }, "probe: \(probe)")
        let parts = probe.split(separator: " ").map(String.init)   // "video <codec> <w>x<h> frames=<n> …"
        XCTAssertEqual(parts.count, 6, probe)
        let frames = Int(parts[3].replacingOccurrences(of: "frames=", with: "")) ?? 0
        XCTAssertGreaterThanOrEqual(frames, 2, probe)
        XCTAssertEqual(parts.last, "audio=1")   // REC-004: In-App Playback audio is included
        app.buttons["recordingResultDiscard"].tap()
        XCTAssertFalse(app.buttons["recordingResultShare"].appears(within: 2))
    }
}
