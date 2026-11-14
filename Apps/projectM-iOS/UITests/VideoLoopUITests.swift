// VideoLoopUITests.swift — MED-003-T13 on the iOS Simulator (MED-003-S6): with the DEBUG seed
// `-uitestSeedVideo counter` (64 × 48, 30 fps, 2 s; picture i at i/30 s), Loop in and Loop out are
// set in Settings → Video and every sampled `videoMediaFrameIndex` (the shown picture's index in the
// file) lies inside the applied region (`videoLoopRegion`, "<in ms>-<out ms>"). The system pickers
// are device tasks. Simulator results are never device evidence (Constitution X); waits are
// ceilings for a slow shared Mac, never frame budgets.
import XCTest

@MainActor
final class VideoLoopUITests: XCTestCase {
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

    /// The controls hide again after a few seconds; on a busy simulator (the seed's import right after
    /// launch) they can hide between finding Settings and tapping it, so this tries up to three times.
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

    /// Held drags, not swipes (see SettingsUITests.scrollTo).
    @discardableResult
    private func scrollTo(_ element: XCUIElement) -> Bool {
        let window = app.windows.firstMatch
        let top = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            bottom.press(forDuration: 0.05, thenDragTo: top, withVelocity: .default, thenHoldForDuration: 0.1)
        }
        return element.exists
    }

    /// "500-1000" → the picture indices a 30 fps file shows inside [500 ms, 1000 ms).
    private func indices(ofRegion text: String) -> ClosedRange<Int>? {
        let parts = text.split(separator: "-").compactMap { (s: Substring) -> Int? in Int(s) }
        guard parts.count == 2, parts[1] > parts[0] else { return nil }
        let first: Int = (parts[0] * 30 + 999) / 1000      // the first picture starting at or after in
        let last: Int = (parts[1] * 30 - 1) / 1000          // the last picture starting before out
        return first...max(first, last)
    }

    func testIndicesStayInsideTheLoopRegion() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestResetNotice",
                               "-uitestSeedVideo", "counter"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()
        let row = app.visualRow("Video")
        XCTAssertTrue(scrollTo(row))
        row.tap()
        closeSettings()
        XCTAssertTrue(videoVisual.appears(within: 10))
        XCTAssertTrue(poll(10) { (self.videoVisual.value as? String) == "Video 64 × 48" }, "the seeded video plays")
        XCTAssertEqual(probe("videoLoopRegion"), "whole")

        openSettings()
        let loopIn = app.sliders["videoLoopIn"], loopOut = app.sliders["videoLoopOut"]
        XCTAssertTrue(scrollTo(loopOut), "the loop sliders are offered once the video plays")
        loopIn.adjust(toNormalizedSliderPosition: 0.25)    // ≈ 0.5 s
        loopOut.adjust(toNormalizedSliderPosition: 0.55)   // ≈ 1.1 s
        XCTAssertTrue((loopIn.value as? String ?? "").hasSuffix("seconds"), "VoiceOver value: \(String(describing: loopIn.value))")
        XCTAssertTrue(app.buttons["videoLoopReset"].exists, "Reset Loop is offered")
        closeSettings()

        XCTAssertTrue(poll(5) { self.probe("videoLoopRegion") != "whole" }, "the region reached the player")
        let regionText = probe("videoLoopRegion")
        guard let allowed = indices(ofRegion: regionText) else { return XCTFail("region probe \(regionText)") }
        XCTAssertLessThan(allowed.count, 40, "a real region, not the whole file: \(regionText)")
        // Let the restart settle, then sample for about 4 s (several passes of a < 1 s region).
        XCTAssertTrue(poll(5) { Int(self.probe("videoMediaFrameIndex")).map(allowed.contains) ?? false })
        var seen = Set<Int>()
        for _ in 0..<40 {
            if let index = Int(probe("videoMediaFrameIndex")) {
                XCTAssertTrue(allowed.contains(index), "index \(index) inside \(regionText) (\(allowed))")
                seen.insert(index)
            }
            usleep(100_000)
        }
        XCTAssertGreaterThanOrEqual(seen.count, 3, "the pictures advance: \(seen.sorted())")
        let stats = probe("videoLoopStats")
        XCTAssertTrue(stats.hasPrefix("wraps="), stats)
        let attachment = XCTAttachment(string: "region \(regionText) seen \(seen.sorted()) \(stats)")
        attachment.lifetime = .keepAlways
        add(attachment)
        print("MED-003 loop UI: region \(regionText) seen \(seen.sorted()) \(stats)")
    }
}
