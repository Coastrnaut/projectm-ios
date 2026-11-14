// RecordingTimedStopUITests.swift — REC-008-T10 on the iOS Simulator: the length set to 10 s by launch argument
// (`-uitestTimedStop 10`; scrolling Settings to the section would eat the 30 s budget, as REC-007 found), Record on
// the Photo visual, the indicator reads "… / 0:10", the recording stops by itself, and the DEBUG probe reads the
// finished file back at 10 s (within one frame: the simulator's frame loop may leave the last slot empty). One
// short test (owner rule 7: under 30 s, the 10 s recording included); the exact frame count is proven by the
// FrameRecording fixture. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class RecordingTimedStopUITests: XCTestCase {
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

    /// The `duration=` value of a probe ("video hvc1 1178x2556 frames=300 duration=10.00 audio=0").
    private func duration(in probe: String) -> Double? {
        guard let part = probe.split(separator: " ").first(where: { (p: Substring) -> Bool in p.hasPrefix("duration=") }) else { return nil }
        return Double(part.dropFirst("duration=".count))
    }

    func testTenSecondLengthStopsByItselfAndTheFileIsTenSeconds() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestRecordingDirectory", "RecordingTimedStopUITests",
                               "-settings.visual", "photo", "-uitestSeedPhoto", "solid",
                               "-uitestTimedStop", "10"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))

        showControls()
        app.buttons["record"].tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(indicator.appears(within: 3), "recording")
        XCTAssertTrue(indicator.label.hasSuffix(" of 0:10"), indicator.label)
        // No Stop tap: the recording ends by itself after 10 s of media time and the file is read back.
        let probe = app.staticTexts["videoRecordingProbe"]
        XCTAssertTrue(poll(20) { (probe.value as? String)?.hasPrefix("video") == true }, String(describing: probe.value))
        let text = probe.value as? String ?? ""
        let seconds = duration(in: text) ?? 0
        XCTAssertEqual(seconds, 10, accuracy: 1.0 / 24 + 0.005, "the finished file is 10 s: \(text)")
        XCTAssertFalse(indicator.exists, "the recording stopped by itself")
    }
}
