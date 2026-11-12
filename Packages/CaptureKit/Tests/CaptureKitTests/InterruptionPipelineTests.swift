// InterruptionPipelineTests.swift — the roadmap acceptance for AUD-014, synthetic half, through the
// whole pipeline: "Synthetic interruption ... restore correct transport state."
// (AUD-014-T05, T09; AUD-014-R10 to R13, R15, R16, R20; S2, S3.)
//
// Production code end to end, rendered offline as in TransportPipelineTests: PlaybackTransport →
// InAppPlaybackSource → AVInAppPlaybackBackend → InAppPlaybackGraph → PCMSink → AudioAnalyzer →
// the normalized ring the renderer reads. The track's frames carry their own index, so the held
// position and the first frame after a restart are compared exactly. The test stands in for iOS:
// it stops the engine behind the app's back (as an interruption, a hardware change and a reset
// do) and delivers the signal or posts the notification on a private NotificationCenter.
// Not shown here: the real audio session, a real call, real routes (device phase).
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
@testable import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class InterruptionPipelineTests: XCTestCase {
    private struct Rig {
        let backend: AVInAppPlaybackBackend
        let source: InAppPlaybackSource
        let manager: CaptureManager
        let transport: PlaybackTransport
        let clock: ManualClock
        let center: NotificationCenter
    }

    private var root: URL!
    /// AUD-014-R10: the held position is at most this far behind the audio last rendered.
    private let tolerance = 11_025                   // 0.25 s at 44.1 kHz

    override func setUp() async throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud014-pipeline")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func item(_ name: String, frames: Int = 132_300, offset: Int = 0) throws -> PlaybackItem {
        let url = try AudioFixtures.writeCounter(to: root.appendingPathComponent("\(name).caf"), frames: frames, offset: offset)
        return PlaybackItem(id: name, title: name, durationSeconds: Double(frames) / 44_100, track: .file(url))
    }

    private func playing(_ items: [PlaybackItem], current: PlaybackItem) async -> Rig {
        let center = NotificationCenter()
        let backend = AVInAppPlaybackBackend(offlineSampleRate: 44_100, notificationCenter: center)
        let source = InAppPlaybackSource(backend: backend)
        let clock = ManualClock()
        let manager = CaptureManager(sources: [source], runsAnalysisTimer: false, clock: { clock.now })
        let transport = PlaybackTransport(manager: manager, source: source)
        transport.prepare(order: ListPlayOrder(items), current: current)
        await manager.select(.inAppPlayback)
        XCTAssertEqual(manager.state, .waiting)
        return Rig(backend: backend, source: source, manager: manager, transport: transport, clock: clock, center: center)
    }

    private func readRenderer(_ rig: Rig) -> [Int] {
        var samples: [Float] = []
        var scratch = [Float](repeating: 0, count: 8192)
        while true {
            let frames = scratch.withUnsafeMutableBufferPointer {
                rig.manager.analyzer.normalizedOutput.readAll(into: $0.baseAddress!, maxFrames: 4096)
            }
            if frames == 0 { break }
            samples.append(contentsOf: scratch[0..<(frames * 2)])
        }
        return CounterDecoder.indices(interleaved: samples)
    }

    private func analyze(_ rig: Rig) {
        rig.clock.advance(1024.0 / 44_100)
        rig.manager.stepAnalysisForTesting()
    }

    /// Renders `renders` × 1,024 frames with an analysis pass after each, waits for the tap to hand
    /// over what it will, and returns what reached the renderer's reader.
    private func pump(_ rig: Rig, renders: Int) async throws -> [Int] {
        var indices: [Int] = []
        for _ in 0..<renders {
            _ = try rig.backend.renderOffline(frames: 1024)
            try await Task.sleep(nanoseconds: 500_000)
            analyze(rig)
            indices += readRenderer(rig)
        }
        var quiet = 0
        while quiet < 12 {
            try await Task.sleep(nanoseconds: 5_000_000)
            rig.manager.stepAnalysisForTesting()
            let more = readRenderer(rig)
            if more.isEmpty { quiet += 1 } else { quiet = 0; indices += more }
        }
        return indices
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    private func positionFrame(_ rig: Rig) -> Int {
        Int((rig.transport.position.seconds * 44_100).rounded())
    }

    private func assertRun(_ indices: [Int], startsAt first: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(indices.isEmpty, "no audio reached the renderer", file: file, line: line)
        XCTAssertEqual(indices.first, first, "the first frame the renderer gets", file: file, line: line)
        XCTAssertTrue(CounterDecoder.isConsecutive(indices), "frames reach the renderer in track order with no gap", file: file, line: line)
    }

    /// The held position after the engine was stopped at `rendered` frames, never having been read.
    private func assertHeld(_ rig: Rig, rendered: Int, file: StaticString = #filePath, line: UInt = #line) -> Int {
        let held = positionFrame(rig)
        XCTAssertLessThanOrEqual(held, rendered, "never ahead of the audio that was rendered", file: file, line: line)
        XCTAssertGreaterThanOrEqual(held, rendered - tolerance, "within 0.25 s of it (AUD-014-R10)", file: file, line: line)
        XCTAssertEqual(positionFrame(rig), held, "and it holds", file: file, line: line)
        return held
    }

    private func postConfigurationChange(_ rig: Rig) {
        rig.center.post(name: .AVAudioEngineConfigurationChange, object: rig.backend.engineForTesting)
    }

    // MARK: - User Story 1: the interruption

    func testInterruptionHoldsThePositionAndResumeContinuesFromItWithoutStaleFrames() async throws {
        let a = try item("a")
        let b = try item("b", offset: 1_000_000)
        for order in [[a, b], [a]] {                  // a list, and one track that repeats (the reference track's order)
            let rig = await playing(order, current: a)
            let heard = try await pump(rig, renders: 30)     // the position is never read: the controls are hidden
            assertRun(heard, startsAt: 0)
            XCTAssertEqual(rig.manager.state, .active)

            rig.backend.stopEngineForTesting()               // iOS stops the audio before the app hears of it
            rig.backend.handle(.interruptionBegan(outputDisconnected: false))
            await settle()
            XCTAssertEqual(rig.manager.state, .interrupted)
            XCTAssertEqual(rig.manager.stopReason, .interrupted)
            XCTAssertEqual(rig.transport.state, .paused)
            let held = assertHeld(rig, rendered: 30 * 1024)

            rig.backend.handle(.interruptionEnded(shouldResume: true))
            await settle()
            XCTAssertEqual(rig.manager.state, .waiting, "Active audio must be verified again")
            XCTAssertEqual(rig.transport.state, .playing)
            XCTAssertEqual(rig.transport.current, a)
            XCTAssertEqual(positionFrame(rig), held)
            XCTAssertEqual(rig.manager.analyzer.normalizedOutput.availableFrames, 0, "nothing old is left for the renderer")
            XCTAssertEqual(rig.manager.sinkForTesting.ring.availableToRead, 0, "nothing old is left for the analysis")

            let after = try await pump(rig, renders: 20)
            assertRun(after, startsAt: held)
            XCTAssertEqual(rig.manager.state, .active)
            XCTAssertEqual(positionFrame(rig), held + 20 * 1024)
            await rig.manager.stop()
        }
    }

    func testAnInterruptionThatDisconnectedTheOutputDoesNotResume() async throws {
        let a = try item("a")
        let rig = await playing([a], current: a)
        _ = try await pump(rig, renders: 10)
        rig.backend.stopEngineForTesting()
        rig.backend.handle(.interruptionBegan(outputDisconnected: true))
        await settle()
        let held = assertHeld(rig, rendered: 10 * 1024)
        rig.backend.handle(.interruptionEnded(shouldResume: true))
        await settle()
        XCTAssertEqual(rig.manager.state, .paused)
        XCTAssertEqual(rig.manager.stopReason, .audioRouteChanged)
        XCTAssertEqual(rig.transport.state, .paused)
        XCTAssertEqual(positionFrame(rig), held)

        await rig.transport.play()
        assertRun(try await pump(rig, renders: 6), startsAt: held)
        await rig.manager.stop()
    }

    // MARK: - User Story 4: hardware change

    func testAConfigurationChangeWhilePlayingContinuesFromThePositionWithoutStaleFrames() async throws {
        let a = try item("a")
        let rig = await playing([a], current: a)
        _ = try await pump(rig, renders: 30)
        // Audio from before the change waits in the sink when the engine stops.
        for _ in 0..<9 { _ = try rig.backend.renderOffline(frames: 1024) }
        try await Task.sleep(nanoseconds: 80_000_000)
        rig.backend.stopEngineForTesting()
        postConfigurationChange(rig)
        await settle()

        XCTAssertTrue(rig.manager.state.isRunning)
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.backend.recoveryCount, 1)
        let restart = positionFrame(rig)
        XCTAssertLessThanOrEqual(restart, 39 * 1024)
        XCTAssertGreaterThanOrEqual(restart, 39 * 1024 - tolerance)
        XCTAssertEqual(rig.manager.sinkForTesting.ring.availableToRead, 0, "nothing old is left for the analysis")
        XCTAssertEqual(rig.manager.analyzer.normalizedOutput.availableFrames, 0, "nothing old is left for the renderer")

        assertRun(try await pump(rig, renders: 20), startsAt: restart)
        XCTAssertEqual(rig.manager.state, .active)
        await rig.manager.stop()
    }

    func testAConfigurationChangeWhilePausedOrInterruptedKeepsThePositionAndPlayContinues() async throws {
        let a = try item("a")
        for interrupted in [false, true] {
            let rig = await playing([a], current: a)
            _ = try await pump(rig, renders: 10)
            if interrupted {
                rig.backend.stopEngineForTesting()
                rig.backend.handle(.interruptionBegan(outputDisconnected: false))
                await settle()
            } else {
                await rig.transport.pause()
                rig.backend.stopEngineForTesting()
            }
            let held = positionFrame(rig)
            postConfigurationChange(rig)
            await settle()
            XCTAssertEqual(rig.manager.state, interrupted ? .interrupted : .paused)
            XCTAssertEqual(rig.transport.state, .paused)
            XCTAssertEqual(positionFrame(rig), held)

            await rig.transport.play()
            XCTAssertEqual(rig.transport.state, .playing)
            assertRun(try await pump(rig, renders: 6), startsAt: held)
            await rig.manager.stop()
        }
    }

    // MARK: - User Story 4: media-services reset

    func testAResetWhilePlayingRebuildsAndContinuesAndThePlayOrderStillWorks() async throws {
        let a = try item("a")
        let b = try item("b", offset: 1_000_000)
        let rig = await playing([a, b], current: a)
        _ = try await pump(rig, renders: 30)
        let oldEngine = rig.backend.engineForTesting
        rig.backend.stopEngineForTesting()
        rig.backend.handle(.mediaServicesReset)
        await settle()

        XCTAssertFalse(rig.backend.engineForTesting === oldEngine, "the playback graph was rebuilt")
        XCTAssertTrue(rig.manager.state.isRunning)
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.current, a)
        let restart = positionFrame(rig)
        XCTAssertLessThanOrEqual(restart, 30 * 1024)
        XCTAssertGreaterThanOrEqual(restart, 30 * 1024 - tolerance)
        assertRun(try await pump(rig, renders: 8), startsAt: restart)

        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, b)
        assertRun(Array(try await pump(rig, renders: 6).prefix(4_000)), startsAt: 1_000_000)

        // The rebuilt graph's engine is the one observed now: a change of its configuration is handled once.
        rig.backend.stopEngineForTesting()
        postConfigurationChange(rig)
        await settle()
        XCTAssertEqual(rig.backend.recoveryCount, 2)
        XCTAssertEqual(rig.transport.state, .playing)
        await rig.manager.stop()
    }

    func testAResetWhilePausedOrInterruptedStaysOnHoldAndPlayContinues() async throws {
        let a = try item("a")
        for interrupted in [false, true] {
            let rig = await playing([a], current: a)
            _ = try await pump(rig, renders: 10)
            if interrupted {
                rig.backend.stopEngineForTesting()
                rig.backend.handle(.interruptionBegan(outputDisconnected: false))
                await settle()
            } else {
                await rig.transport.pause()
                rig.backend.stopEngineForTesting()
            }
            let held = positionFrame(rig)
            rig.backend.handle(.mediaServicesReset)
            await settle()
            XCTAssertEqual(rig.manager.state, interrupted ? .interrupted : .paused)
            XCTAssertEqual(rig.transport.state, .paused)
            XCTAssertEqual(positionFrame(rig), held)

            if interrupted {
                rig.backend.handle(.interruptionEnded(shouldResume: true))
                await settle()
            } else {
                await rig.transport.play()
            }
            XCTAssertEqual(rig.transport.state, .playing)
            assertRun(try await pump(rig, renders: 6), startsAt: held)
            await rig.manager.stop()
        }
    }

    func testAResetThatCannotRebuildEndsAsFailedAndPlaysNothingElse() async throws {
        let a = try item("a")
        let b = try item("b", offset: 1_000_000)
        let rig = await playing([a, b], current: a)
        _ = try await pump(rig, renders: 10)
        if case .file(let url) = a.track { try FileManager.default.removeItem(at: url) }
        rig.backend.stopEngineForTesting()
        rig.backend.handle(.mediaServicesReset)
        await settle()
        XCTAssertEqual(rig.manager.state, .stopped)
        XCTAssertEqual(rig.manager.stopReason, .inAppPlaybackFailed)
        XCTAssertFalse(rig.transport.isAvailable)
        XCTAssertNil(rig.backend.engineForTesting, "the backend was stopped")
    }

    // MARK: - Observers across sessions (AUD-014-R20)

    func testAStoppedBackendReactsToNothingAndANewSessionReactsOnce() async throws {
        let a = try item("a")
        let rig = await playing([a], current: a)
        _ = try await pump(rig, renders: 4)
        let firstEngine = rig.backend.engineForTesting
        await rig.manager.stop()
        rig.center.post(name: .AVAudioEngineConfigurationChange, object: firstEngine)
        rig.backend.handle(.interruptionBegan(outputDisconnected: false))
        rig.backend.handle(.mediaServicesReset)
        await settle()
        XCTAssertEqual(rig.backend.recoveryCount, 0)
        XCTAssertEqual(rig.manager.state, .stopped)

        for _ in 0..<3 {
            await rig.manager.select(.inAppPlayback)
            await rig.manager.stop()
        }
        await rig.manager.select(.inAppPlayback)
        _ = try await pump(rig, renders: 4)
        rig.center.post(name: .AVAudioEngineConfigurationChange, object: firstEngine)   // an engine that is gone
        await settle()
        XCTAssertEqual(rig.backend.recoveryCount, 0)
        rig.backend.stopEngineForTesting()
        postConfigurationChange(rig)
        await settle()
        XCTAssertEqual(rig.backend.recoveryCount, 1, "one session, one reaction")
        XCTAssertEqual(rig.transport.state, .playing)
        await rig.manager.stop()
    }

    #if os(iOS)
    /// The notification path itself, with the names and keys iOS uses, on the private center.
    func testPostedSessionNotificationsReachTheManagerOncePerSession() async throws {
        let a = try item("a")
        let rig = await playing([a], current: a)
        for _ in 0..<3 {
            await rig.manager.stop()
            await rig.manager.select(.inAppPlayback)
        }
        _ = try await pump(rig, renders: 10)
        let session = AVAudioSession.sharedInstance()
        rig.backend.stopEngineForTesting()
        rig.center.post(name: AVAudioSession.interruptionNotification, object: session,
                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        await settle()
        XCTAssertEqual(rig.manager.state, .interrupted)
        XCTAssertEqual(rig.manager.lifecycleLog.filter { $0.event == "interruptionBegan" }.count, 1)
        let held = assertHeld(rig, rendered: 10 * 1024)

        rig.center.post(name: AVAudioSession.interruptionNotification, object: session,
                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                   AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        await settle()
        XCTAssertEqual(rig.transport.state, .playing)
        assertRun(try await pump(rig, renders: 6), startsAt: held)

        rig.center.post(name: AVAudioSession.routeChangeNotification, object: session,
                        userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        await settle()
        XCTAssertEqual(rig.manager.state, .paused)
        XCTAssertEqual(rig.manager.stopReason, .audioRouteChanged)
        await rig.manager.stop()
    }
    #endif
}
#endif
