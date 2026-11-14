// SafeMediaUITests.swift — MED-014-T17 on the iOS Simulator: the roadmap acceptance "Corrupt fixture
// fails gracefully and leaves compositor running" in the app (MED-014-S4, R12). The DEBUG seeds
// `-uitestSeedPhoto corrupt` and `-uitestSeedVideo corrupt` import a valid photo and video and then
// damage the stored copies on disk. Choosing each visual must show its "couldn't be loaded" notice
// without blocking anything ("The photo couldn't be loaded." / "The video couldn't be played."), and the app must stay usable. Simulator results are never device
// evidence (Constitution X). Waits are ceilings for a slow shared Mac, never frame budgets.
import XCTest

@MainActor
final class SafeMediaUITests: XCTestCase {
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

    private func openSettings() {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5), "Settings opens")
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5), "Settings closes")
    }

    /// The visualizer notice's text (`photoNoticeText` / `videoNoticeText`).
    private func noticeText(_ identifier: String) -> String { app.staticTexts[identifier].firstMatch.label }

    /// Both damaged stored copies fail with their typed notice when their visual loads them; the
    /// app keeps responding (Settings opens and closes, the other visual is chosen).
    func testDamagedStoredPhotoAndVideoShowNoticesAndTheAppStaysUsable() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestResetNotice",
                               "-uitestSeedPhoto", "corrupt", "-uitestSeedVideo", "corrupt"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))

        openSettings()
        let photoRow = app.visualRow("Photo")
        XCTAssertTrue(app.reveal(photoRow))
        photoRow.tap()
        closeSettings()
        let photoNotice = app.descendants(matching: .any)["photoNotice"].firstMatch
        XCTAssertTrue(photoNotice.appears(within: 10), "the damaged photo shows its notice")
        XCTAssertTrue(noticeText("photoNoticeText") == "The photo couldn't be loaded.", "notice: \(noticeText("photoNoticeText"))")
        XCTAssertEqual(app.staticTexts["photoFramesShown"].value as? String ?? "0", "0", "the photo layer draws nothing")

        openSettings()
        let videoRow = app.visualRow("Video")
        XCTAssertTrue(app.reveal(videoRow))
        videoRow.tap()
        XCTAssertTrue(app.reveal(app.buttons["removeVideo"]), "the seeded video was imported (its copy is damaged afterwards)")
        closeSettings()
        let videoNotice = app.descendants(matching: .any)["videoNotice"].firstMatch
        XCTAssertTrue(videoNotice.appears(within: 10), "the damaged video shows its notice")
        XCTAssertTrue(noticeText("videoNoticeText") == "The video couldn't be played.", "notice: \(noticeText("videoNoticeText"))")

        // Still usable: the controls and Settings respond, and the audio source never restarted.
        openSettings()
        closeSettings()
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the audio source kept running")
    }
}
