// VideoSpeedUITests.swift — MED-004-T13 on the iOS Simulator (MED-004-S6, R8, R11): with the DEBUG
// seed `-uitestSeedVideo counter` (64 × 48, 30 fps, 2 s), Speed is set to 0.5× in Settings → Video,
// then the `videoSpeed` probe reports percent 50 and a measured ratio of video time to presentation
// time of 0.5 (the app's own display-link clock, so no wall-clock assertion), while `videoFrameIndex`
// keeps advancing. A second case picks a speed at an accessibility text size. The system pickers are
// device tasks. Simulator results are never device evidence (Constitution X); waits are ceilings.
import XCTest

@MainActor
final class VideoSpeedUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var videoVisual: XCUIElement { app.descendants(matching: .any)["videoVisual"].firstMatch }
    private func probe(_ id: String) -> String { app.staticTexts[id].value as? String ?? "" }

    /// See CameraUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    /// Up to three tries: the controls can hide between finding Settings and tapping it.
    private func openSettings() {
        for _ in 0..<3 {
            showControls()
            let button = app.buttons["settings"]
            if button.exists, button.isHittable { button.tap() }
            if app.navigationBars["Settings"].appears(within: 5) { return }
        }
        XCTFail("Settings did not open")
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    /// Launches with the seeded video, chooses the Video visual and waits until it plays.
    private func launchPlayingVideo(_ extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestResetNotice",
                               "-uitestSeedVideo", "counter",
                               // Settings opens at the Video section once it is shown (the Speed picker); before
                               // Video is chosen the ID is absent and Settings opens at its top (owner rule 7).
                               "-uitestSettingsSection", "video"] + Self.noStore + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()
        let row = app.visualRow("Video")
        XCTAssertTrue(app.reveal(row))
        row.tap()
        closeSettings()
        XCTAssertTrue(videoVisual.appears(within: 10))
        XCTAssertTrue(poll(10) { (self.videoVisual.value as? String) == "Video 64 × 48" }, "the seeded video plays")
    }

    /// Opens Settings, picks the speed whose spoken label is `label` from the Speed menu, closes Settings.
    private func pickSpeed(_ label: String) {
        openSettings()
        let picker = app.buttons["videoSpeedPicker"]
        XCTAssertTrue(app.reveal(picker), "the Speed picker is offered while a video is stored")
        picker.tap()
        let option = app.buttons[label].firstMatch
        XCTAssertTrue(option.appears(within: 3), "the menu offers \(label)")
        option.tap()
        XCTAssertTrue(poll(3) { (picker.value as? String) == label }, "VoiceOver value: \(String(describing: picker.value))")
        closeSettings()
    }

    private func ratio(_ text: String) -> Double? {
        guard let range = text.range(of: "ratio=") else { return nil }
        return Double(text[range.upperBound...])
    }

    func testHalfSpeedAdvancesTheVideoAtHalfThePresentationRate() {
        launchPlayingVideo()
        XCTAssertTrue(probe("videoSpeed").hasPrefix("100 "), probe("videoSpeed"))
        pickSpeed("Half speed")
        XCTAssertTrue(poll(5) { self.probe("videoSpeed").hasPrefix("50 ratio=0") }, "the speed reached the player: \(probe("videoSpeed"))")
        let firstIndex = Int(probe("videoFrameIndex")) ?? -1
        XCTAssertTrue(poll(5) { (Int(self.probe("videoFrameIndex")) ?? -1) > firstIndex + 3 }, "the pictures keep advancing")
        let text = probe("videoSpeed")
        let measured = ratio(text) ?? -1
        XCTAssertEqual(measured, 0.5, accuracy: 0.05, "video time over presentation time: \(text)")
        let attachment = XCTAttachment(string: "MED-004 speed UI: \(text), frame index \(firstIndex) → \(probe("videoFrameIndex"))")
        attachment.lifetime = .keepAlways
        add(attachment)
        print("MED-004 speed UI: \(text), frame index \(firstIndex) -> \(probe("videoFrameIndex"))")
    }

    func testSpeedCanBePickedAtAnAccessibilityTextSize() {
        launchPlayingVideo(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        pickSpeed("Double speed")
        XCTAssertTrue(poll(5) { self.probe("videoSpeed").hasPrefix("200 ratio=") }, probe("videoSpeed"))
    }
}
