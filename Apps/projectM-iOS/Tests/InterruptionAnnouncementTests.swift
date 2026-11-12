// AUD-014-T20: what VoiceOver hears when In-App Playback goes on hold (AUD-014-R18, R19).
import AudioCore
import CaptureUI
import XCTest
@testable import projectM_iOS

@MainActor
final class InterruptionAnnouncementTests: XCTestCase {
    func testInAppPlaybackOnHoldIsAnnouncedWithItsExplanation() {
        XCTAssertEqual(SourceStatusIndicator.holdAnnouncement(mode: .inAppPlayback, state: .interrupted, reason: .interrupted),
                       "In-App Playback · Interrupted. \(UIStrings.playbackInterruptedDetail)")
        XCTAssertEqual(SourceStatusIndicator.holdAnnouncement(mode: .inAppPlayback, state: .paused, reason: .interrupted),
                       "In-App Playback · Paused. \(UIStrings.playbackInterruptedDetail)")
        XCTAssertEqual(SourceStatusIndicator.holdAnnouncement(mode: .inAppPlayback, state: .paused, reason: .audioRouteChanged),
                       "In-App Playback · Paused. \(UIStrings.playbackOutputDisconnectedDetail)")
    }

    func testNothingExtraIsAnnouncedOtherwise() {
        XCTAssertNil(SourceStatusIndicator.holdAnnouncement(mode: .inAppPlayback, state: .paused, reason: nil), "a user pause")
        XCTAssertNil(SourceStatusIndicator.holdAnnouncement(mode: .inAppPlayback, state: .stopped, reason: .inAppPlaybackFailed))
        XCTAssertNil(SourceStatusIndicator.holdAnnouncement(mode: .microphone, state: .interrupted, reason: .interrupted))
        XCTAssertNil(SourceStatusIndicator.holdAnnouncement(mode: .systemAppCapture, state: .waiting, reason: .interrupted))
        XCTAssertNil(SourceStatusIndicator.holdAnnouncement(mode: nil, state: .notStarted, reason: nil))
    }
}
