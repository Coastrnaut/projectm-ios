// VideoRecordingUITests.swift — REC-003-T18 on the iOS Simulator: Record on the Photo visual (a seeded
// 64 × 48 photo through the DEBUG `-uitestSeedPhoto` import), the indicator, Stop recording, and the
// file read back through the DEBUG `-uitestRecordingDirectory` folder (the system file mover cannot be
// automated) by `videoRecordingProbe`. projectM refuses with its reason. Asserted by content (the
// probe), never by time; the waits are ceilings for a slow shared Mac. Simulator results are never
// device evidence (Constitution X). Owner rule 7: under 30 s each.
import XCTest

@MainActor
final class VideoRecordingUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestRecordingDirectory", "VideoRecordingUITests"] + extra + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
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

    /// REC-003-S5: Record → the indicator → Stop recording → a readable video with frames, a video codec
    /// and no audio track.
    func testRecordPhotoVisualWritesAVideo() {
        launch(["-settings.visual", "photo", "-uitestSeedPhoto", "solid"])
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))
        showControls()
        let record = app.buttons["record"]
        XCTAssertTrue(record.exists)
        XCTAssertEqual(record.label, "Record")
        record.tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(indicator.appears(within: 5), "the recording indicator")
        XCTAssertTrue(indicator.label.hasPrefix("Recording, 0:0"), indicator.label)
        // About 2 s of recorded video (the indicator shows media time).
        XCTAssertTrue(poll(10) { indicator.label == "Recording, 0:02" || indicator.label == "Recording, 0:03" }, indicator.label)
        showControls()
        XCTAssertEqual(app.buttons["record"].label, "Stop recording")
        app.buttons["record"].tap()
        XCTAssertTrue(poll(10) { self.probe.hasPrefix("video ") }, "probe: \(probe)")
        // "video <codec> <w>x<h> frames=<n> duration=<s> audio=0"
        print("REC-003 UI probe: \(probe)")   // the codec the simulator wrote, for the test report
        let parts = probe.split(separator: " ").map(String.init)
        XCTAssertEqual(parts.count, 6, probe)
        XCTAssertTrue(["hvc1", "avc1"].contains(parts[1]), probe)
        let frames = Int(parts[3].replacingOccurrences(of: "frames=", with: "")) ?? 0
        XCTAssertGreaterThanOrEqual(frames, 2, probe)
        XCTAssertEqual(parts.last, "audio=0")
        XCTAssertFalse(indicator.exists, "the indicator is gone")
    }

    /// REC-003-R12: projectM is not recordable in this row; Record says why and nothing starts.
    func testProjectMRefusesWithItsReason() {
        launch(["-settings.visual", "projectM"])
        XCTAssertTrue(app.descendants(matching: .any)["visualizer"].firstMatch.appears(within: 10))
        showControls()
        let record = app.buttons["record"]
        XCTAssertEqual(record.value as? String, "Unavailable for projectM")
        record.tap()
        XCTAssertTrue(poll(5) { self.probe == "refused: notRecordable" }, "probe: \(probe)")
        XCTAssertEqual(app.staticTexts["videoRecordingNoticeText"].label,
                       "Recording is available for the Camera, Photo, Video, Text and spectrum visuals.")
        XCTAssertFalse(app.descendants(matching: .any)["recordingIndicator"].firstMatch.exists)
    }
}
