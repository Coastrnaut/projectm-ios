// AUD-015-T02: the background policy table (contracts/background-policy.md), every source ×
// presence × keep-playing × audio-mode case (AUD-015-S1), plus the automatic-resume rule and the
// Info.plist reading. Pure: no manager, no clock.
import XCTest
import AudioCore
@testable import CaptureKit

final class BackgroundPolicyTableTests: XCTestCase {
    /// The four presences: (in the background, locked).
    private static let presences: [(background: Bool, locked: Bool)] = [
        (false, false), (true, false), (false, true), (true, true),
    ]

    /// The contract's table, written out independently of the implementation.
    private static func expected(mode: AudioSourceMode, away: Bool, audioMode: Bool, keep: Bool)
        -> (BackgroundPolicy.Action, BackgroundPolicy.Reason) {
        if !away { return (.run, .foreground) }
        switch mode {
        case .microphone:
            return (.stopCapture, .microphoneStoppedInBackground)
        case .inAppPlayback:
            let continues: Bool = audioMode && keep
            return continues ? (.continuePlayback, .playbackContinuesInBackground)
                             : (.pausePlayback, .playbackPausedInBackground)
        case .systemAppCapture:
            return (.followSystem, .systemCaptureFollowsSystem)
        }
    }

    func testEveryCaseMatchesTheContractTable() {
        var cases: Int = 0
        for mode in AudioSourceMode.allCases {
            for presence in Self.presences {
                for keep in [false, true] {
                    for audioMode in [false, true] {
                        let configuration = BackgroundPolicy.Configuration(declaresAudioBackgroundMode: audioMode,
                                                                           keepPlayingInBackground: keep)
                        let context = BackgroundPolicy.Context(mode: mode, isBackgrounded: presence.background,
                                                               isLocked: presence.locked, configuration: configuration)
                        let away: Bool = presence.background || presence.locked
                        let want = Self.expected(mode: mode, away: away, audioMode: audioMode, keep: keep)
                        let got = BackgroundPolicy.decide(context)
                        let label = "\(mode) background=\(presence.background) locked=\(presence.locked) keep=\(keep) audio=\(audioMode)"
                        XCTAssertEqual(context.isAway, away, label)
                        XCTAssertEqual(got.action, want.0, label)
                        XCTAssertEqual(got.reason, want.1, label)
                        let resumes: Bool = !away && mode != .systemAppCapture
                        XCTAssertEqual(BackgroundPolicy.mayResumeAutomatically(context), resumes, label)
                        cases += 1
                    }
                }
            }
        }
        XCTAssertEqual(cases, 48)
    }

    func testTheMicrophoneStopsWhateverTheConfiguration() {
        let entitled = BackgroundPolicy.Configuration(declaresAudioBackgroundMode: true, keepPlayingInBackground: true)
        let context = BackgroundPolicy.Context(mode: .microphone, isBackgrounded: true, isLocked: false, configuration: entitled)
        XCTAssertEqual(BackgroundPolicy.decide(context).action, .stopCapture, "no covert capture, even with the audio mode")
    }

    func testTheShippedConfigurationNeverContinuesPlayback() {
        XCTAssertEqual(BackgroundPolicy.Configuration.shipped,
                       BackgroundPolicy.Configuration(declaresAudioBackgroundMode: false, keepPlayingInBackground: false))
        let keepOnly = BackgroundPolicy.Configuration(declaresAudioBackgroundMode: false, keepPlayingInBackground: true)
        let context = BackgroundPolicy.Context(mode: .inAppPlayback, isBackgrounded: true, isLocked: false, configuration: keepOnly)
        XCTAssertEqual(BackgroundPolicy.decide(context).action, .pausePlayback, "the wish alone is not an entitlement")
    }

    func testNoticeTexts() {
        XCTAssertEqual(BackgroundPolicy.Reason.playbackPausedInBackground.notice,
                       "Playback paused while projectM-iOS was in the background.")
        XCTAssertEqual(BackgroundPolicy.Reason.microphoneStoppedInBackground.notice,
                       "The microphone was off while projectM-iOS was in the background. It never listens in the background.")
        XCTAssertNil(BackgroundPolicy.Reason.foreground.notice)
        XCTAssertNil(BackgroundPolicy.Reason.playbackContinuesInBackground.notice)
        XCTAssertNil(BackgroundPolicy.Reason.systemCaptureFollowsSystem.notice)
    }

    func testDeclaresAudioModeReadsTheBackgroundModes() {
        XCTAssertFalse(BackgroundPolicy.declaresAudioMode(in: []))
        XCTAssertFalse(BackgroundPolicy.declaresAudioMode(in: ["screen-capture"]))
        XCTAssertTrue(BackgroundPolicy.declaresAudioMode(in: ["screen-capture", "audio"]))
    }
}
