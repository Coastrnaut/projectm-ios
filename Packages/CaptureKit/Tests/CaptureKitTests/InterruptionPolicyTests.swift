// InterruptionPolicyTests.swift — the interruption policy, every combination (AUD-014-T02;
// AUD-014-R1 to R9, S1; specs/009-aud-014-audio-session-interruption-recovery/contracts/
// interruption-policy.md). Pure: runs wherever Swift does.
import AudioCore
import XCTest
@testable import CaptureKit

final class InterruptionPolicyTests: XCTestCase {
    private typealias Policy = InterruptionPolicy

    private var allInputs: [Policy.Input] {
        var inputs: [Policy.Input] = []
        for source in Policy.Source.allCases {
            for before in Policy.Transport.allCases {
                for pausedBy in Policy.PausedBy.allCases {
                    for signal in Policy.SystemSignal.allCases {
                        for presentable in [true, false] {
                            for changed in [true, false] {
                                for usable in [true, false] {
                                    inputs.append(Policy.Input(source: source, before: before, pausedBy: pausedBy, signal: signal,
                                                               isPresentable: presentable, userChangedTransport: changed,
                                                               sourceIsUsable: usable))
                                }
                            }
                        }
                    }
                }
            }
        }
        return inputs
    }

    /// The contract's 14 rules, written out row by row (first match wins).
    private func contract(_ i: Policy.Input) -> Policy.Decision {
        let noResumeIndicated = i.signal == .pending || i.signal == .endedWithoutResume
        if i.source == .systemAppCapture { return .notApplicable }                                         // 1
        if !i.sourceIsUsable {                                                                             // 2
            return .fail(i.source == .inAppPlayback ? .inAppPlaybackFailed : .microphoneUnavailable)
        }
        if i.before == .stopped { return .stayStopped }                                                    // 3
        if i.source == .microphone {
            if i.before == .paused { return .stayStopped }                                                 // 4
            if noResumeIndicated { return .stayPaused(.interrupted) }                                      // 5
            if !i.isPresentable { return .stayPaused(.notPresentable) }                                    // 6
            return .resume                                                                                 // 7
        }
        if i.pausedBy == .user { return .stayPaused(.user) }                                               // 8
        if i.pausedBy == .system { return .stayPaused(.outputDisconnected) }                               // 9
        if i.before == .paused { return .stayPaused(.user) }                                               // 10
        if i.userChangedTransport { return .stayPaused(.interrupted) }                                     // 11
        if noResumeIndicated { return .stayPaused(.interrupted) }                                          // 12
        if !i.isPresentable { return .stayPaused(.notPresentable) }                                        // 13
        return .resume                                                                                     // 14
    }

    func testEveryCombinationHasTheContractsOutcome() {
        let inputs = allInputs
        XCTAssertEqual(inputs.count, 864)
        for input in inputs {
            XCTAssertEqual(Policy.decide(input), contract(input), "\(input)")
        }
    }

    /// AUD-014-R2: In-App Playback resumes exactly when every condition holds.
    func testInAppPlaybackResumesOnlyWhenEveryConditionHolds() {
        var resumes = 0
        for input in allInputs where input.source == .inAppPlayback {
            let all = input.sourceIsUsable && input.before == .playing && input.pausedBy == .nobody
                && !input.userChangedTransport && input.isPresentable
                && (input.signal == .endedShouldResume || input.signal == .notInterrupted)
            XCTAssertEqual(Policy.decide(input) == .resume, all, "\(input)")
            if all { resumes += 1 }
        }
        XCTAssertEqual(resumes, 2, "one input per permitting signal")
    }

    /// AUD-014-R3, R4: a user pause, a stop and a lost output never resume, whatever iOS says.
    func testUserPauseStopAndLostOutputNeverResume() {
        for input in allInputs where input.source == .inAppPlayback {
            if input.pausedBy != .nobody || input.before != .playing || input.userChangedTransport {
                XCTAssertNotEqual(Policy.decide(input), .resume, "\(input)")
            }
        }
    }

    /// AUD-014-R9: System/App Capture is never touched; Microphone follows FR-051.
    func testCaptureIsNotApplicableAndMicrophoneFollowsFeature001() {
        for input in allInputs where input.source == .systemAppCapture {
            XCTAssertEqual(Policy.decide(input), .notApplicable)
        }
        func mic(_ signal: Policy.SystemSignal, presentable: Bool = true, usable: Bool = true) -> Policy.Decision {
            Policy.decide(Policy.Input(source: .microphone, before: .playing, pausedBy: .nobody, signal: signal,
                                       isPresentable: presentable, userChangedTransport: false, sourceIsUsable: usable))
        }
        XCTAssertEqual(mic(.endedShouldResume), .resume)
        XCTAssertEqual(mic(.endedWithoutResume), .stayPaused(.interrupted))
        XCTAssertEqual(mic(.pending), .stayPaused(.interrupted))
        XCTAssertEqual(mic(.endedShouldResume, presentable: false), .stayPaused(.notPresentable))
        XCTAssertEqual(mic(.endedShouldResume, usable: false), .fail(.microphoneUnavailable))
    }

    /// One literal row per outcome, as the contract's prose states them.
    func testLiteralRows() {
        func inApp(_ before: Policy.Transport = .playing, _ pausedBy: Policy.PausedBy = .nobody,
                   _ signal: Policy.SystemSignal = .endedShouldResume, presentable: Bool = true, changed: Bool = false,
                   usable: Bool = true) -> Policy.Decision {
            Policy.decide(Policy.Input(source: .inAppPlayback, before: before, pausedBy: pausedBy, signal: signal,
                                       isPresentable: presentable, userChangedTransport: changed, sourceIsUsable: usable))
        }
        XCTAssertEqual(inApp(), .resume)
        XCTAssertEqual(inApp(.playing, .nobody, .notInterrupted), .resume, "a hardware change or a reset")
        XCTAssertEqual(inApp(.playing, .nobody, .pending), .stayPaused(.interrupted))
        XCTAssertEqual(inApp(.playing, .nobody, .endedWithoutResume), .stayPaused(.interrupted))
        XCTAssertEqual(inApp(presentable: false), .stayPaused(.notPresentable))
        XCTAssertEqual(inApp(changed: true), .stayPaused(.interrupted))
        XCTAssertEqual(inApp(.playing, .user), .stayPaused(.user))
        XCTAssertEqual(inApp(.playing, .system), .stayPaused(.outputDisconnected))
        XCTAssertEqual(inApp(.paused, .user), .stayPaused(.user))
        XCTAssertEqual(inApp(.paused, .nobody), .stayPaused(.user))
        XCTAssertEqual(inApp(.stopped, .user), .stayStopped)
        XCTAssertEqual(inApp(usable: false), .fail(.inAppPlaybackFailed))
    }

    func testSourceKindsMapFromModes() {
        XCTAssertEqual(Policy.Source(.inAppPlayback), .inAppPlayback)
        XCTAssertEqual(Policy.Source(.microphone), .microphone)
        XCTAssertEqual(Policy.Source(.systemAppCapture), .systemAppCapture)
    }
}
