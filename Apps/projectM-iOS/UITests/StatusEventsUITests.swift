// StatusEventsUITests.swift — ACC-011-T14 on the iOS Simulator (ACC-011-S4; contract C1, C3): a few
// transitions driven with the existing fakes, read from ACC-004's `announcementProbe` and the
// `statusCaption` view. Simulator results are never device evidence; the VoiceOver pass on D1 is
// ACC-011-T17. Owner rule 7: each test < 30 s; UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class StatusEventsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: XCUIElement { app.staticTexts["announcementProbe"] }

    private func expectSpoken(_ text: String, prefix: Bool = false, within seconds: TimeInterval = 5,
                              file: StaticString = #filePath, line: UInt = #line) {
        let ok = poll(seconds) {
            guard let value = self.probe.value as? String else { return false }
            return prefix ? value.hasPrefix(text) : value == text
        }
        XCTAssertTrue(ok, "probe \"\(text)\"; it reads \"\(probe.value ?? "nil")\"", file: file, line: line)
    }

    private func tapFake(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.appears(within: 5), id)
        button.tap()
    }

    /// X1 and X3: the source's changes are spoken in the indicator's words, the hold with its detail.
    func testSourceChangesAreSpokenAsShown() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestFake", "inAppPlayback",
                               "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        let indicator = app.staticTexts["sourceIndicator"]
        XCTAssertTrue(indicator.appears(within: 20))
        XCTAssertTrue(probe.appears(within: 5))
        expectSpoken("source|In-App Playback · Waiting")
        XCTAssertEqual(indicator.label, "In-App Playback · Waiting")

        tapFake("fake:loud")
        expectSpoken("source|In-App Playback · Active audio")
        XCTAssertEqual(indicator.label, "In-App Playback · Active audio", "visible text matches the announcement")

        tapFake("fake:interrupt")
        expectSpoken("source|In-App Playback · Interrupted", prefix: true)
        XCTAssertEqual(indicator.label, "In-App Playback · Interrupted")
    }

    /// X21 and X23: Black out and Restore are spoken; the restored output, which has no badge, shows a
    /// 4 s caption.
    func testRestoredOutputIsCaptioned() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestKeepControls", "-uitestDiagnostics",
                               "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        let area = app.otherElements["visualizerTapArea"].firstMatch
        XCTAssertTrue(area.appears(within: 20), "the visualizer is up")
        let blackout = app.buttons["blackout"]
        if !blackout.exists { area.tap() }
        XCTAssertTrue(blackout.appears(within: 5), "the controls are shown")
        blackout.tap()
        expectSpoken("output|Output blacked out")
        XCTAssertTrue(app.staticTexts["blackoutBadgeText"].appears(within: 2), "the badge's visible text")

        let restore = app.buttons["blackoutRestore"]
        XCTAssertTrue(restore.appears(within: 3))
        restore.tap()
        expectSpoken("output|Output restored", within: 6)
        let caption = app.staticTexts["statusCaption"]
        XCTAssertTrue(caption.appears(within: 2), "the restored output is captioned")
        XCTAssertEqual(caption.label, "Output restored")
        XCTAssertTrue(caption.disappears(within: 6), "the caption goes after 4 s")
    }
}
