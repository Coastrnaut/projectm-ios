// VideoReverseUITests.swift — MED-005-T14 on the iOS Simulator (MED-005-R1, R11; S5): with the DEBUG seed
// `-uitestSeedVideo counter` (64 × 48, 30 fps, 2 s), Reverse is turned on in Settings → Video; the `videoReverse` probe
// then reports `playing` and the cached picture index it shows goes down (wrapping from 0 to the end). The app's own
// display-link clock drives it, so no wall-clock assertion; waits are ceilings. Simulator results are never device
// evidence (Constitution X).
import XCTest

@MainActor
final class VideoReverseUITests: XCTestCase {
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

    /// The cached index of "<state> <index>" (nil: none).
    private func reverseIndex() -> Int? {
        let parts = probe("videoReverse").split(separator: " ")
        guard parts.count == 2, parts[0] == "playing" else { return nil }
        return Int(parts[1])
    }

    func testReverseSwitchPlaysTheSeededClipBackwards() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestResetNotice", "-uitestUnlocked", "NO",
                               "-uitestSeedVideo", "counter", "-uitestSettingsSection", "video"]
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()
        let row = app.visualRow("Video")
        XCTAssertTrue(app.reveal(row))
        row.tap()
        closeSettings()
        XCTAssertTrue(videoVisual.appears(within: 10))
        XCTAssertTrue(poll(10) { (self.videoVisual.value as? String) == "Video 64 × 48" }, "the seeded video plays")
        XCTAssertTrue(probe("videoReverse").hasPrefix("off "), probe("videoReverse"))

        openSettings()
        let toggle = app.switches["videoReverseToggle"]
        XCTAssertTrue(app.reveal(toggle), "the Reverse switch is offered while a video is stored")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(3) { (toggle.value as? String) == "1" }, "switched on")
        closeSettings()

        XCTAssertTrue(poll(5) { self.reverseIndex() != nil }, "the cache plays: \(probe("videoReverse"))")
        // Read a few changes: each goes back by less than half the clip (60 pictures), modulo a wrap from 0 to 59.
        var readings: [Int] = []
        for _ in 0..<4 {
            let previous = reverseIndex() ?? -1
            XCTAssertTrue(poll(3) { (self.reverseIndex() ?? previous) != previous }, "the picture changes")
            readings.append(reverseIndex() ?? -1)
        }
        var downs = 0
        for (a, b) in zip(readings, readings.dropFirst()) {
            let back: Int = (a - b + 60) % 60
            if back > 0, back < 30 { downs += 1 }
        }
        XCTAssertGreaterThanOrEqual(downs, 2, "the picture index goes down: \(readings)")
        let attachment = XCTAttachment(string: "MED-005 reverse UI: \(readings)")
        attachment.lifetime = .keepAlways
        add(attachment)
        print("MED-005 reverse UI: \(readings)")
    }
}
