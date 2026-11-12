// InterruptionStringsTests.swift — the explanations shown while In-App Playback is on hold
// (AUD-014-T17; AUD-014-R17, R19; specs/009-aud-014-audio-session-interruption-recovery/contracts/
// ui-strings.md).
import AudioCore
import XCTest
@testable import CaptureUI

final class InterruptionStringsTests: XCTestCase {
    private let allReasons: [StopReason] = [.cancelled, .permissionDenied, .microphoneUnavailable, .inAppPlaybackFailed,
                                            .interrupted, .audioRouteChanged, .endedBySystem, .unsupportedOS,
                                            .screenRecordingNotAllowed, .error("x")]

    func testExplanationsForInAppPlayback() {
        XCTAssertEqual(UIStrings.playbackHoldDetail(mode: .inAppPlayback, reason: .interrupted),
                       "Playback is on hold at its position. It continues when iOS allows it, or press Play.")
        XCTAssertEqual(UIStrings.playbackHoldDetail(mode: .inAppPlayback, reason: .audioRouteChanged),
                       "The audio output was disconnected. Press Play to continue.")
    }

    func testNoExplanationForOtherReasonsOrOtherSources() {
        for reason in allReasons where reason != .interrupted && reason != .audioRouteChanged {
            XCTAssertNil(UIStrings.playbackHoldDetail(mode: .inAppPlayback, reason: reason), reason.code)
        }
        XCTAssertNil(UIStrings.playbackHoldDetail(mode: .inAppPlayback, reason: nil))
        XCTAssertNil(UIStrings.playbackHoldDetail(mode: nil, reason: .interrupted))
        for mode in [AudioSourceMode.microphone, .systemAppCapture] {
            for reason in allReasons {
                XCTAssertNil(UIStrings.playbackHoldDetail(mode: mode, reason: reason), "\(mode) \(reason.code): AUD-014-R19")
            }
        }
    }

    /// Feature 001's texts and actions for these reasons are unchanged (FR-051).
    func testFeature001MessagesAndActionsAreUnchanged() {
        XCTAssertEqual(UIStrings.message(.interrupted), "Interrupted")
        XCTAssertEqual(UIStrings.message(.audioRouteChanged), "Paused — audio route changed")
        XCTAssertEqual(UIStrings.state(.interrupted), "Interrupted")
        XCTAssertEqual(UIStrings.state(.paused), "Paused")
        XCTAssertEqual(BannerAction.actions(for: .interrupted), [.restart, .chooseSource])
        XCTAssertEqual(BannerAction.actions(for: .audioRouteChanged), [.resume, .chooseSource])
    }

    /// What VoiceOver hears when playback goes on hold: the status, then the explanation.
    func testAnnouncement() {
        XCTAssertEqual(UIStrings.playbackHoldAnnouncement(status: "In-App Playback · Interrupted", mode: .inAppPlayback, reason: .interrupted),
                       "In-App Playback · Interrupted. Playback is on hold at its position. It continues when iOS allows it, or press Play.")
        XCTAssertEqual(UIStrings.playbackHoldAnnouncement(status: "In-App Playback · Paused", mode: .inAppPlayback, reason: .audioRouteChanged),
                       "In-App Playback · Paused. The audio output was disconnected. Press Play to continue.")
        XCTAssertNil(UIStrings.playbackHoldAnnouncement(status: "Microphone · Interrupted", mode: .microphone, reason: .interrupted))
        XCTAssertNil(UIStrings.playbackHoldAnnouncement(status: "In-App Playback · Paused", mode: .inAppPlayback, reason: nil))
    }
}
