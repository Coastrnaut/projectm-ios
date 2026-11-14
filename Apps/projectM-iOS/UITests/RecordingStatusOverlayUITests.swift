// RecordingStatusOverlayUITests.swift — REC-009-T07 on the iOS Simulator: Record on the Photo visual, the indicator
// (duration), the dropped-frames line and the storage line ("… free, about … min left") show while recording and
// are gone after Stop. One short test (owner rule 7: under 30 s). Simulator results are never device evidence
// (Constitution X); the exclusion from the file is proven by RecordingStatusOverlayAppTests.
import XCTest

@MainActor
final class RecordingStatusOverlayUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testRecordingShowsDurationDroppedFramesAndStorage() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestRecordingDirectory", "RecordingStatusOverlayUITests",
                               "-settings.visual", "photo", "-uitestSeedPhoto", "solid"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))

        showControls()
        app.buttons["record"].tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(indicator.appears(within: 3), "recording")
        XCTAssertTrue(indicator.label.hasPrefix("Recording, 0:"), indicator.label)
        let dropped = app.descendants(matching: .any)["recordingDroppedFrames"].firstMatch
        let storage = app.descendants(matching: .any)["recordingStorageStatus"].firstMatch
        XCTAssertTrue(dropped.appears(within: 3), "the dropped-frames line")
        XCTAssertTrue(dropped.label.contains("frames: "), dropped.label)
        XCTAssertTrue(storage.appears(within: 3), "the storage line")
        XCTAssertTrue(storage.label.contains(" free, ") && storage.label.hasSuffix(" min left"), storage.label)

        app.buttons["record"].tap()   // "Stop recording" keeps the identifier
        XCTAssertTrue(dropped.disappears(within: 5), "only while recording")
        XCTAssertFalse(storage.exists)
        let probe = app.staticTexts["videoRecordingProbe"]
        XCTAssertTrue(poll(15) { (probe.value as? String)?.hasPrefix("video") == true }, String(describing: probe.value))
    }
}
