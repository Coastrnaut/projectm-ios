// B05AudioDeviceTests.swift — QA-011 owner session B05 ("Audio routes, headphones, calls and interruptions"), the
// parts that need no headphones, calls or listening, automated on the device with generated stereo fixtures
// (scripts/make_music_fixture.py --variant left|inverted, copied by scripts/install_test_fixtures.py).
// AUD-009-T13 (In-App Playback part): with music in the left channel only, Left and Mix move the bars and Right
// leaves them still. ANL-013-T14: a phase-inverted feed reads a negative r on the overlay and the warning shows.
// AUD-006-T39 (background part): a user pause stays paused across background and return; playing resumes.
import UIKit
import XCTest

@MainActor
final class B05AudioDeviceTests: DeviceAcceptanceCase {
    private var overlay: XCUIElement { app.descendants(matching: .any)["performanceOverlay"].firstMatch }

    /// Mean motion of the whole screen over three pairs of screenshots (the spectrum is most of the moving picture).
    private func motion(_ task: String, _ label: String) -> Double {
        var values: [Double] = []
        for i in 0..<3 {
            let (_, a) = screen(task, "\(label) \(i) a")
            pause(1)
            let (_, b) = screen(task, "\(label) \(i) b")
            values.append(Self.change(a, b))
        }
        let mean = values.reduce(0, +) / Double(values.count)
        report(task, label, ["motionMean": mean, "motionMax": values.max() ?? 0])
        return mean
    }

    /// AUD-009-T13: left-only music; Mix and Left follow it, Right stays still.
    func testAUD009ChannelSelectionFollowsTheChosenChannel() {
        let task = "AUD-009-T13"
        var moved: [String: Double] = [:]
        for mode in ["mix", "left", "right"] {
            launch(visual: "linearSpectrum", settings: ["settings.analysisChannel.mode": mode],
                   fixture: "music-fixture-left.m4a")
            moved[mode] = motion(task, mode)
            app.terminate()
        }
        let left = moved["left"] ?? 0, right = moved["right"] ?? 0, mix = moved["mix"] ?? 0
        XCTAssertGreaterThan(left, 0.004, "Left follows the music (\(left))")
        XCTAssertGreaterThan(mix, 0.004, "Mix follows the music (\(mix))")
        XCTAssertLessThan(right, left / 3, "Right (silent channel) stays far stiller than Left: right \(right), left \(left)")
    }

    /// ANL-013-T14: a phase-inverted feed under Mix: the overlay's r is negative and the warning shows within ~1 s.
    func testANL013PhaseInvertedFeedWarns() {
        let task = "ANL-013-T14"
        launch(visual: "linearSpectrum", fixture: "music-fixture-inverted.m4a")
        let warned = wait(5) { self.overlay.label.contains("phase-inverted") }
        let label = overlay.label
        let r: Double? = label.range(of: #"stereo: r (-?[0-9.]+)"#, options: .regularExpression)
            .flatMap { Double(label[$0].replacingOccurrences(of: "stereo: r ", with: "")) }
        report(task, "inverted", ["r": r ?? 99, "warned": warned ? 1 : 0])
        XCTAssertNotNil(r, "the overlay shows the stereo line: \(label.prefix(200))")
        XCTAssertLessThan(r ?? 1, -0.5, "a negative r for an inverted feed")
        XCTAssertTrue(warned, "the phase-inverted warning shows")
    }

    /// AUD-006-T39 (background part): a user pause stays paused across background and return; playing resumes.
    func testAUD006PauseStaysPausedAcrossBackground() {
        let task = "AUD-006-T39"
        launch(visual: "linearSpectrum")
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        let playPause = app.buttons["transportPlayPause"]
        XCTAssertTrue(wait(5) { playPause.exists }, "the transport")
        playPause.tap()
        XCTAssertTrue(wait(5) { self.overlay.label.contains("Paused") }, "paused: \(overlay.label.prefix(120))")
        XCUIDevice.shared.press(.home)
        _ = wait(10) { self.app.state != .runningForeground }
        pause(3)
        app.activate()
        _ = wait(10) { self.app.state == .runningForeground }
        pause(2)
        XCTAssertTrue(overlay.label.contains("Paused"), "still paused after the return: \(overlay.label.prefix(120))")
        report(task, "paused across background", ["stillPaused": overlay.label.contains("Paused") ? 1 : 0])
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        playPause.tap()
        XCTAssertTrue(wait(10) { self.overlay.label.contains("Active audio") }, "Play resumes: \(overlay.label.prefix(120))")
        XCUIDevice.shared.press(.home)
        _ = wait(10) { self.app.state != .runningForeground }
        pause(3)
        app.activate()
        _ = wait(10) { self.app.state == .runningForeground }
        let resumed = wait(10) { self.overlay.label.contains("Active audio") }
        report(task, "playing across background", ["resumed": resumed ? 1 : 0])
        XCTAssertTrue(resumed, "playing playback resumes after the return: \(overlay.label.prefix(120))")
    }
}
