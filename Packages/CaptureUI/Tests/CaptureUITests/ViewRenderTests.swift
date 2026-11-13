// ViewRenderTests.swift — smoke tests for the views shown by the T033 previews, plus a check that
// the preview fixtures cover every StopReason case.
//
// What ImageRenderer can show here: each view body evaluates without trapping, lays out, and
// produces a non-empty bitmap; and adding a message line or an action row makes the layout taller.
// It cannot show that a given string is drawn (the size comes from layout, and ImageRenderer draws
// placeholders for platform-backed controls), so string and action correctness is checked by
// UIStringsTests and scripts/test_scripts.py, not here. The chooser is a List, which ImageRenderer
// cannot draw, so CaptureLabUITests checks it in the running app instead.
#if canImport(SwiftUI)
import AudioCore
import CaptureKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import CaptureUI

@MainActor
final class ViewRenderTests: XCTestCase {
    /// Exhaustiveness witness: one distinct kind per StopReason case, named after the case.
    /// Adding a StopReason case stops `init(_:)` compiling; adding the matching kind (as the
    /// naming requires) then makes `testFixturesCoverEveryStopReason` fail until
    /// `PreviewFixtures.stopReasons` contains the new case. The compiler cannot stop a new case
    /// from being mapped onto an existing kind; the raw-value check below catches that for every
    /// case that has a fixture.
    private enum ReasonKind: String, CaseIterable {
        case cancelled, permissionDenied, microphoneUnavailable, inAppPlaybackFailed, interrupted,
             audioRouteChanged, endedBySystem, unsupportedOS, screenRecordingNotAllowed, error

        init(_ reason: StopReason) {
            switch reason {
            case .cancelled: self = .cancelled
            case .permissionDenied: self = .permissionDenied
            case .microphoneUnavailable: self = .microphoneUnavailable
            case .inAppPlaybackFailed: self = .inAppPlaybackFailed
            case .interrupted: self = .interrupted
            case .audioRouteChanged: self = .audioRouteChanged
            case .endedBySystem: self = .endedBySystem
            case .unsupportedOS: self = .unsupportedOS
            case .screenRecordingNotAllowed: self = .screenRecordingNotAllowed
            case .error: self = .error
            }
        }
    }

    func testFixturesCoverEveryStopReason() {
        let kinds = PreviewFixtures.stopReasons.map(ReasonKind.init)
        XCTAssertEqual(Set(kinds).count, kinds.count, "duplicate StopReason in fixtures")
        let missing = Set(ReasonKind.allCases).subtracting(kinds).map(\.rawValue).sorted()
        XCTAssertEqual(missing, [], "PreviewFixtures.stopReasons is missing these StopReason cases")
        for reason in PreviewFixtures.stopReasons {
            XCTAssertEqual(ReasonKind(reason).rawValue, reason.code, "witness maps \(reason.code) to the wrong kind")
        }
    }

    func testBannerSmokeRendersEveryStopReason() {
        for reason in PreviewFixtures.stopReasons {
            assertSmokeRenders(StatusBanner(mode: .systemAppCapture, state: PreviewFixtures.state(for: reason),
                                            reason: reason, prolongedSilence: false) { _ in },
                               name: "banner \(reason.code)")
        }
    }

    func testBannerSmokeRendersEveryState() {
        for state in AudioState.allCases {
            assertSmokeRenders(StatusBanner(mode: .microphone, state: state, reason: nil,
                                            prolongedSilence: state == .silent) { _ in },
                               name: "banner \(state.rawValue)")
        }
    }

    func testMicrophoneExplainerSmokeRenders() {
        assertSmokeRenders(MicrophoneExplainerView(onContinue: {}, onCancel: {}), name: "explainer")
    }

    /// Layout only: a banner with a StopReason (message line and action row) is taller than the same
    /// banner without one, and each hint (no audio, prolonged silence) adds a line. This shows the
    /// optional rows take part in layout, not which text they draw.
    func testOptionalBannerRowsAddHeight() throws {
        for reason in PreviewFixtures.stopReasons {
            let state = PreviewFixtures.state(for: reason)
            let with = try height(StatusBanner(mode: .systemAppCapture, state: state, reason: reason,
                                               prolongedSilence: false) { _ in })
            let without = try height(StatusBanner(mode: .systemAppCapture, state: state, reason: nil,
                                                  prolongedSilence: false) { _ in })
            XCTAssertGreaterThan(with, without, "banner \(reason.code): message/action rows add no height")
        }
        let noAudio = try height(StatusBanner(mode: .microphone, state: .noAudioReceived, reason: nil,
                                              prolongedSilence: false) { _ in })
        let waiting = try height(StatusBanner(mode: .microphone, state: .waiting, reason: nil,
                                              prolongedSilence: false) { _ in })
        XCTAssertGreaterThan(noAudio, waiting, "no-audio hint adds no height")
        let longSilence = try height(StatusBanner(mode: .microphone, state: .silent, reason: nil,
                                                  prolongedSilence: true) { _ in })
        let silence = try height(StatusBanner(mode: .microphone, state: .silent, reason: nil,
                                              prolongedSilence: false) { _ in })
        XCTAssertGreaterThan(longSilence, silence, "prolonged-silence hint adds no height")
    }

    /// AUD-014-T17: the explanation line takes part in layout for In-App Playback only.
    func testBannerShowsThePlaybackHoldExplanationForInAppPlaybackOnly() throws {
        for (reason, state) in [(StopReason.interrupted, AudioState.interrupted), (.audioRouteChanged, .paused)] {
            let inApp = try height(StatusBanner(mode: .inAppPlayback, state: state, reason: reason, prolongedSilence: false) { _ in })
            let microphone = try height(StatusBanner(mode: .microphone, state: state, reason: reason, prolongedSilence: false) { _ in })
            XCTAssertGreaterThan(inApp, microphone, "\(reason.code): the explanation adds no height")
            assertSmokeRenders(StatusBanner(mode: .inAppPlayback, state: state, reason: reason, prolongedSilence: false) { _ in },
                               name: "banner on hold \(reason.code)")
        }
    }

    // MARK: Transport bar (AUD-006-T26)

    private func transportBar(title: String = "Track", isPlaying: Bool, seconds: Double = 65, duration: Double = 180) -> TransportBar {
        TransportBar(title: title, isPlaying: isPlaying,
                     position: { PlaybackPosition(seconds: seconds, durationSeconds: duration) },
                     onPlayPause: {}, onStop: {}, onPrevious: {}, onNext: {}, onSeek: { _ in })
    }

    func testTransportBarSmokeRendersPlayingPausedStoppedAndEmpty() {
        assertSmokeRenders(transportBar(isPlaying: true), name: "transport playing")
        assertSmokeRenders(transportBar(isPlaying: false), name: "transport paused")
        assertSmokeRenders(transportBar(isPlaying: false, seconds: 0), name: "transport stopped")
        assertSmokeRenders(transportBar(isPlaying: false, seconds: 0, duration: 0), name: "transport with nothing loaded")
        assertSmokeRenders(transportBar(title: String(repeating: "A very long title ", count: 20), isPlaying: true,
                                        seconds: 3_700, duration: 7_300), name: "transport long title, hours")
    }

    // MARK: - AUD-003 queue

    func testTransportBarWithTheQueueButtonSmokeRenders() {
        let bar = TransportBar(title: "Track", isPlaying: true, position: { PlaybackPosition(seconds: 5, durationSeconds: 60) },
                               onPlayPause: {}, onStop: {}, onPrevious: {}, onNext: {}, onSeek: { _ in }, onShowQueue: {})
        assertSmokeRenders(bar, name: "transport with Queue")
        assertSmokeRenders(bar.dynamicTypeSize(.accessibility5), name: "transport with Queue, largest text")
    }

    // MARK: - AUD-004 repeat

    func testTransportBarWithTheRepeatButtonSmokeRendersEveryMode() {
        for mode in RepeatMode.allCases {
            let bar = TransportBar(title: "Track", isPlaying: true, position: { PlaybackPosition(seconds: 5, durationSeconds: 60) },
                                   onPlayPause: {}, onStop: {}, onPrevious: {}, onNext: {}, onSeek: { _ in }, onShowQueue: {},
                                   repeatMode: mode, onCycleRepeat: {})
            assertSmokeRenders(bar, name: "transport with Repeat \(mode)")
            assertSmokeRenders(bar.dynamicTypeSize(.accessibility5), name: "transport with Repeat \(mode), largest text")
        }
    }

    // MARK: - AUD-005 shuffle

    func testTransportBarWithTheShuffleButtonSmokeRendersBothValues() {
        for on in [false, true] {
            let bar = TransportBar(title: "Track", isPlaying: true, position: { PlaybackPosition(seconds: 5, durationSeconds: 60) },
                                   onPlayPause: {}, onStop: {}, onPrevious: {}, onNext: {}, onSeek: { _ in }, onShowQueue: {},
                                   repeatMode: .all, onCycleRepeat: {}, isShuffled: on, onToggleShuffle: {})
            assertSmokeRenders(bar, name: "transport with Shuffle \(on)")
            assertSmokeRenders(bar.dynamicTypeSize(.accessibility5), name: "transport with Shuffle \(on), largest text")
        }
    }

    // PlayQueueView is a List, which ImageRenderer cannot draw (see the file header);
    // PlayQueueUITests checks it in the running app (AUD-003-T17).

    func testTransportBarLaysOutAtTheLargestTextSize() throws {
        let regular = try height(transportBar(isPlaying: true))
        let large = try height(transportBar(isPlaying: true).dynamicTypeSize(.accessibility5))
        XCTAssertGreaterThan(regular, 60, "title, scrubber row and button row")
        XCTAssertGreaterThan(large, regular, "the times get their own row and all text grows")
    }

    /// Smoke test: the body evaluates without trapping and ImageRenderer returns a non-empty bitmap.
    private func assertSmokeRenders(_ view: some View, name: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let image = render(view)
        XCTAssertNotNil(image, "\(name): ImageRenderer returned no image", file: file, line: line)
        XCTAssertGreaterThan(image?.width ?? 0, 0, "\(name): empty image", file: file, line: line)
        XCTAssertGreaterThan(image?.height ?? 0, 0, "\(name): empty image", file: file, line: line)
    }

    private func height(_ view: some View, file: StaticString = #filePath, line: UInt = #line) throws -> Int {
        try XCTUnwrap(render(view), "ImageRenderer returned no image", file: file, line: line).height
    }

    private func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: 390))
        renderer.scale = 1
        return renderer.cgImage
    }
}
#endif
