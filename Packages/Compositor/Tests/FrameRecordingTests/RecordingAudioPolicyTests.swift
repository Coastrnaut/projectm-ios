// RecordingAudioPolicyTests.swift — REC-004-T02: which audio a recording may contain (contract C1).
@testable import FrameRecording
import XCTest

final class RecordingAudioPolicyTests: XCTestCase {
    func testInAppPlaybackIsAlwaysIncluded() {
        for mic in [false, true] {
            for granted in [false, true] {
                XCTAssertEqual(RecordingAudioPolicy.decide(source: .inAppPlayback, includeMicrophone: mic, microphoneGranted: granted),
                               .include(.appAudio))
            }
        }
    }

    func testSystemCaptureIsNeverIncluded() {   // REC-004-R2, S3
        for mic in [false, true] {
            for granted in [false, true] {
                let decision = RecordingAudioPolicy.decide(source: .systemCapture, includeMicrophone: mic, microphoneGranted: granted)
                XCTAssertEqual(decision, .exclude(.otherAppsAudio))
                XCTAssertFalse(decision.includesAudio)
            }
        }
    }

    func testMicrophoneNeedsPermissionAndSetting() {   // REC-004-R1
        XCTAssertEqual(RecordingAudioPolicy.decide(source: .microphone, includeMicrophone: false, microphoneGranted: false),
                       .exclude(.microphonePermissionMissing))
        XCTAssertEqual(RecordingAudioPolicy.decide(source: .microphone, includeMicrophone: true, microphoneGranted: false),
                       .exclude(.microphonePermissionMissing))
        XCTAssertEqual(RecordingAudioPolicy.decide(source: .microphone, includeMicrophone: false, microphoneGranted: true),
                       .exclude(.microphoneSettingOff))
        XCTAssertEqual(RecordingAudioPolicy.decide(source: .microphone, includeMicrophone: true, microphoneGranted: true),
                       .include(.microphone))
    }

    func testNoSourceHasNoAudio() {
        XCTAssertEqual(RecordingAudioPolicy.decide(source: nil, includeMicrophone: true, microphoneGranted: true), .exclude(.noSource))
    }

    func testStatusTextsMatchTheDataModel() {
        XCTAssertEqual(RecordingAudioDecision.include(.appAudio).statusText, "Recording includes app audio.")
        XCTAssertEqual(RecordingAudioDecision.include(.microphone).statusText, "Recording includes microphone audio.")
        XCTAssertEqual(RecordingAudioDecision.exclude(.otherAppsAudio).statusText,
                       "Recording has no audio: other apps' audio is never recorded.")
        XCTAssertEqual(RecordingAudioDecision.exclude(.microphoneSettingOff).statusText,
                       "Recording has no audio: Include microphone audio is off.")
        XCTAssertEqual(RecordingAudioDecision.exclude(.microphonePermissionMissing).statusText,
                       "Recording has no audio: microphone permission is off.")
        XCTAssertEqual(RecordingAudioDecision.exclude(.noSource).statusText, "Recording has no audio.")
        XCTAssertEqual(RecordingAudioDecision.endedText, "Recording audio ended.")
    }
}
