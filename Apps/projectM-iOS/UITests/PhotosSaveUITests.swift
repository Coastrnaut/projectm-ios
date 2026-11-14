// PhotosSaveUITests.swift — REC-011-T12, T13 on the iOS Simulator.
// * Denied (DEBUG `-uitestPhotosAccess denied`): Record → Stop → "Recording ready" → Save to Photos shows the denied
//   notice with Open Settings, and the recording stays offered (the roadmap acceptance, REC-011-S5).
// * Granted (stand-in): Save Frame → "Frame ready" → Save to Photos → "Saved to Photos.", the frame stays offered.
// * Live (only with TEST_RUNNER_REC011_LIVE_PHOTOS=granted|denied, after `simctl privacy grant|revoke photos-add`):
//   the real add-only Photos path on a frame and a recording. Not evidence (Constitution X); never run in CI.
// Asserted by content, never by time. Owner rule 7: each test under 30 s.
import XCTest

@MainActor
final class PhotosSaveUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    private static let deniedText =
        "Photos access is off. To save to Photos, allow adding photos for projectM in Settings. The file is still in the app."

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

    private func launch(photos: String?) {
        XCUIDevice.shared.orientation = .portrait
        var arguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                         "-settings.visual", "photo", "-uitestSeedPhoto", "solid"] + Self.noStore
        if let photos { arguments += ["-uitestPhotosAccess", photos] }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))
    }

    private func offerFrame() -> XCUIElement {
        showControls()
        app.buttons["saveFrame"].tap()
        let png = app.buttons["PNG"].firstMatch
        XCTAssertTrue(png.appears(within: 5), "the format choice")
        png.tap()
        let photos = app.buttons["frameResultPhotos"]
        XCTAssertTrue(photos.appears(within: 10), "the Frame ready panel with Save to Photos")
        return photos
    }

    private var noticeText: String { app.staticTexts["photosSaveNoticeText"].label }

    func testDeniedSaveKeepsTheRecordingOfferedAndShowsTheError() {
        launch(photos: "denied")
        showControls()
        app.buttons["record"].tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(indicator.appears(within: 5), "the recording indicator")
        XCTAssertTrue(poll(10) { indicator.label.hasPrefix("Recording, 0:01") || indicator.label.hasPrefix("Recording, 0:02") },
                      indicator.label)
        showControls()
        app.buttons["record"].tap()
        let toPhotos = app.buttons["recordingResultPhotos"]
        XCTAssertTrue(toPhotos.appears(within: 10), "the Recording ready panel with Save to Photos")
        XCTAssertEqual(toPhotos.label, "Save the recording to Photos")
        toPhotos.tap()
        XCTAssertTrue(app.staticTexts["photosSaveNoticeText"].appears(within: 5), "the error notice")
        XCTAssertEqual(noticeText, Self.deniedText)
        XCTAssertTrue(app.buttons["photosSaveNoticeSettings"].exists, "Open Settings")
        XCTAssertTrue(app.buttons["recordingResultShare"].exists, "the recording is still offered")
        XCTAssertTrue(app.buttons["recordingResultKeep"].isEnabled)
        app.buttons["photosSaveNoticeDismiss"].tap()
        XCTAssertFalse(app.staticTexts["photosSaveNoticeText"].exists)
        app.buttons["recordingResultDiscard"].tap()
    }

    func testGrantedSaveOfAFrameSavesAndKeepsTheOffer() {
        launch(photos: "granted")
        offerFrame().tap()
        XCTAssertTrue(poll(5) { self.app.staticTexts["photosSaveNoticeText"].exists && self.noticeText == "Saved to Photos." }, noticeText)
        XCTAssertFalse(app.buttons["photosSaveNoticeSettings"].exists, "no Open Settings on success")
        XCTAssertTrue(app.buttons["frameResultShare"].exists, "the frame is still offered")
    }

    /// The real Photos path; the runner sets access first with `simctl privacy`.
    func testLiveAddOnlyPhotosPath() throws {
        guard let expected = ProcessInfo.processInfo.environment["REC011_LIVE_PHOTOS"] else {
            throw XCTSkip("set TEST_RUNNER_REC011_LIVE_PHOTOS=granted|denied after simctl privacy grant|revoke photos-add")
        }
        launch(photos: nil)
        offerFrame().tap()
        let text = expected == "granted" ? "Saved to Photos." : Self.deniedText
        XCTAssertTrue(poll(10) { self.app.staticTexts["photosSaveNoticeText"].exists && self.noticeText == text }, noticeText)
        XCTAssertTrue(app.buttons["frameResultShare"].exists, "the frame is still offered")
        app.buttons["photosSaveNoticeDismiss"].tap()

        // A recording: the video file path (shouldMoveFile = false), still offered afterwards.
        showControls()
        app.buttons["record"].tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(indicator.appears(within: 5), "the recording indicator")
        XCTAssertTrue(poll(10) { indicator.label.hasPrefix("Recording, 0:01") || indicator.label.hasPrefix("Recording, 0:02") },
                      indicator.label)
        showControls()
        app.buttons["record"].tap()
        let toPhotos = app.buttons["recordingResultPhotos"]
        XCTAssertTrue(toPhotos.appears(within: 10), "the Recording ready panel")
        toPhotos.tap()
        XCTAssertTrue(poll(10) { self.app.staticTexts["photosSaveNoticeText"].exists && self.noticeText == text }, noticeText)
        XCTAssertTrue(app.buttons["recordingResultShare"].exists, "the recording is still offered")
        app.buttons["recordingResultDiscard"].tap()
    }
}
