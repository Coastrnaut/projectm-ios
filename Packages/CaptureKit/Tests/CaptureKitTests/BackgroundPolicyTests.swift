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

// MARK: - AUD-015-T04: the microphone never captures while the app is away

/// A microphone backend whose engine writes frames into the sink only while it runs.
@MainActor
final class FrameCountingMicrophoneBackend: MicrophoneBackend {
    var permission: MicrophonePermission = .granted
    var isInputAvailable = true
    private(set) var engineRunning = false
    private(set) var deliveredFrames = 0
    private var sink: PCMSink?

    func requestPermission() async -> Bool { true }

    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {
        self.sink = sink
        engineRunning = true
    }

    func stop() { engineRunning = false; sink = nil }
    func pause() { engineRunning = false }
    func resume() throws { engineRunning = true }

    /// One hardware callback of `frames` stereo frames; nothing reaches the sink while stopped.
    func deliver(frames: Int) {
        guard engineRunning, let sink else { return }
        let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)
        let count: Int = frames * 2
        let samples = [Float](repeating: 0.25, count: count)
        samples.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            sink.writeInterleaved(raw.baseAddress!, frames: frames, format: format)
        }
        deliveredFrames += frames
    }
}

@MainActor
final class BackgroundPolicyManagerTests: XCTestCase {
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<20 { await Task.yield() }
    }

    private func microphoneRig() -> (CaptureManager, FrameCountingMicrophoneBackend) {
        let backend = FrameCountingMicrophoneBackend()
        let manager = CaptureManager(sources: [MicrophoneSource(backend: backend)], runsAnalysisTimer: false)
        return (manager, backend)
    }

    func testNoMicrophoneFramesWhileAwayEvenAfterAnUnlockInTheBackground() async {
        let (manager, backend) = microphoneRig()
        await manager.select(.microphone)
        backend.deliver(frames: 480)
        XCTAssertEqual(backend.deliveredFrames, 480, "captures in the foreground")

        await manager.handle(.background)
        XCTAssertFalse(backend.engineRunning, "the engine stops on background")
        XCTAssertEqual(manager.state, .paused)
        XCTAssertTrue(manager.isAway)
        backend.deliver(frames: 480)
        await manager.handle(.lock)
        backend.deliver(frames: 480)
        await manager.handle(.unlock)   // unlocked onto the Home Screen: still in the background
        backend.deliver(frames: 480)
        XCTAssertFalse(backend.engineRunning, "an unlock in the background resumes nothing")
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(backend.deliveredFrames, 480, "no frame reached the app while away")
        XCTAssertEqual(manager.backgroundNotice, .microphoneStoppedInBackground)

        await manager.handle(.foreground)
        XCTAssertFalse(manager.isAway)
        XCTAssertTrue(backend.engineRunning, "a real return resumes (FR-050)")
        XCTAssertEqual(manager.state, .waiting)
        backend.deliver(frames: 480)
        XCTAssertEqual(backend.deliveredFrames, 960)
        XCTAssertEqual(manager.backgroundNotice, .microphoneStoppedInBackground, "kept for the return notice")
    }

    func testLockInTheForegroundThenUnlockResumes() async {
        let (manager, backend) = microphoneRig()
        await manager.select(.microphone)
        await manager.handle(.lock)
        XCTAssertFalse(backend.engineRunning)
        await manager.handle(.unlock)
        XCTAssertTrue(backend.engineRunning, "unlocked and never backgrounded: a real return")
    }

    func testAStartThatCompletesWhileAwayIsHeld() async {
        let (manager, backend) = microphoneRig()
        await manager.handle(.background)
        await manager.select(.microphone)
        XCTAssertFalse(backend.engineRunning, "held: no capture while away")
        XCTAssertEqual(manager.state, .paused)
        backend.deliver(frames: 480)
        XCTAssertEqual(backend.deliveredFrames, 0)
        XCTAssertEqual(manager.backgroundNotice, .microphoneStoppedInBackground)
        await manager.handle(.foreground)
        XCTAssertTrue(backend.engineRunning)
    }

    func testResumeWhileAwayDoesNotStartTheEngine() async {
        let (manager, backend) = microphoneRig()
        await manager.select(.microphone)
        await manager.handle(.background)
        await manager.resume()
        XCTAssertFalse(backend.engineRunning)
        XCTAssertEqual(manager.state, .paused)
    }

    func testTheNoticeIsClearedByStopAndANewStart() async {
        let (manager, _) = microphoneRig()
        await manager.select(.microphone)
        await manager.handle(.background)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.backgroundNotice, .microphoneStoppedInBackground)
        await manager.stop()
        XCTAssertNil(manager.backgroundNotice)
        await manager.select(.microphone)
        await manager.handle(.background)
        await manager.handle(.foreground)
        manager.dismissBackgroundNotice()
        XCTAssertNil(manager.backgroundNotice)
        await manager.handle(.background)
        await manager.handle(.foreground)
        await manager.select(.microphone)
        XCTAssertNil(manager.backgroundNotice, "a new start clears it")
    }

    // MARK: - AUD-015-T07: In-App Playback

    private func playbackRig(_ configuration: BackgroundPolicy.Configuration = .shipped)
        -> (CaptureManager, FakePlaybackBackend) {
        let backend = FakePlaybackBackend()
        let manager = CaptureManager(sources: [InAppPlaybackSource(backend: backend)], runsAnalysisTimer: false)
        manager.backgroundConfiguration = configuration
        return (manager, backend)
    }

    func testShippedPlaybackPausesAndResumesWithANotice() async {
        let (manager, backend) = playbackRig()
        await manager.select(.inAppPlayback)
        await manager.handle(.background)
        XCTAssertTrue(backend.paused)
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(manager.backgroundNotice, .playbackPausedInBackground)
        await manager.handle(.foreground)
        XCTAssertFalse(backend.paused)
        XCTAssertEqual(manager.state, .waiting)
    }

    func testEntitledAndIntendedPlaybackContinues() async {
        let entitled = BackgroundPolicy.Configuration(declaresAudioBackgroundMode: true, keepPlayingInBackground: true)
        let (manager, backend) = playbackRig(entitled)
        await manager.select(.inAppPlayback)
        await manager.handle(.background)
        await manager.handle(.lock)
        XCTAssertFalse(backend.paused)
        XCTAssertEqual(backend.pauseCount, 0)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertNil(manager.backgroundNotice)
    }

    func testAUserPauseStaysAndSetsNoNotice() async {
        let (manager, backend) = playbackRig()
        await manager.select(.inAppPlayback)
        await manager.pause()
        await manager.handle(.background)
        XCTAssertNil(manager.backgroundNotice)
        await manager.handle(.foreground)
        XCTAssertTrue(backend.paused, "AUD-006-R22: a user pause stays")
        XCTAssertTrue(manager.isPausedByUser)
    }

    func testAnOpenInterruptionStaysOnHoldOnReturn() async {
        let (manager, backend) = playbackRig()
        await manager.select(.inAppPlayback)
        backend.onEvent?(.interruptionBegan)
        await settle()
        await manager.handle(.background)
        await manager.handle(.foreground)
        XCTAssertNotEqual(manager.state, .waiting, "AUD-014-R6: no resume while the interruption is open")
        XCTAssertEqual(backend.resumeCount, 0)
    }

    func testTheNoticeIsClearedByAUserPauseAndByResume() async {
        let (manager, _) = playbackRig()
        await manager.select(.inAppPlayback)
        await manager.handle(.background)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.backgroundNotice, .playbackPausedInBackground)
        await manager.pause()
        XCTAssertNil(manager.backgroundNotice)
        await manager.handle(.background)
        await manager.handle(.foreground)
        XCTAssertNil(manager.backgroundNotice, "already paused by the user: nothing to explain")
        await manager.resume()
        await manager.handle(.background)
        XCTAssertEqual(manager.backgroundNotice, .playbackPausedInBackground)
        await manager.handle(.foreground)
        await manager.resume()
        XCTAssertNil(manager.backgroundNotice)
    }

    // MARK: - AUD-015-T09: System/App Capture follows the system

    func testSystemCaptureIsNeverSuspendedResumedOrRestarted() async {
        let capture = FakeAudioSource(mode: .systemAppCapture)
        let manager = CaptureManager(sources: [capture], runsAnalysisTimer: false)
        await manager.select(.systemAppCapture)
        for event in [AppLifecycleEvent.background, .lock, .unlock, .foreground] {
            await manager.handle(event)
        }
        XCTAssertEqual(capture.suspendCount, 0)
        XCTAssertEqual(capture.resumeCount, 0)
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertNil(manager.backgroundNotice)
    }

    func testSystemCaptureEndedWhileAwayShowsEndedBySystemAndStaysStopped() async {
        let capture = FakeAudioSource(mode: .systemAppCapture)
        let manager = CaptureManager(sources: [capture], runsAnalysisTimer: false)
        await manager.select(.systemAppCapture)
        await manager.handle(.background)
        await manager.handle(.lock)
        capture.emit(.endedBySystem("SCStreamError -3817"))
        await settle()
        await manager.handle(.unlock)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.state, .endedBySystem)
        XCTAssertEqual(manager.stopReason, .endedBySystem)
        XCTAssertEqual(capture.startCount, 1, "never restarted without the picker (FR-055)")
        XCTAssertNil(manager.backgroundNotice)
    }
}
