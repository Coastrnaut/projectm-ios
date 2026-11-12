// TransportPipelineTests.swift — the roadmap acceptance for AUD-006, through the whole pipeline:
// "Seek within a test track updates playback position and analysis without stale frames."
// (AUD-006-T19, T25; AUD-006-R4, R5, R8 to R13, R17, R20; S1 to S5.)
//
// Production code end to end, rendered offline: PlaybackTransport → InAppPlaybackSource →
// AVInAppPlaybackBackend → InAppPlaybackGraph (player, mixer, tap, gate) → PCMSink →
// AudioAnalyzer → Normalizer → the normalized ring the renderer reads. The track's frames carry
// their own index (`AudioFixtures.writeCounter`), and the output rate equals the file's, so what
// the renderer would read can be compared with the position frame by frame. The test stands in
// for the two clocks only: it calls the engine's render and the analysis step.
// Not shown here: real-time rendering, the audio session, routes, interruptions (device phase).
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
@testable import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class TransportPipelineTests: XCTestCase {
    private struct Rig {
        let backend: AVInAppPlaybackBackend
        let source: InAppPlaybackSource
        let manager: CaptureManager
        let transport: PlaybackTransport
        let clock: ManualClock
    }

    private var root: URL!

    override func setUp() async throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud006-pipeline")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func item(_ name: String, frames: Int, offset: Int = 0) throws -> PlaybackItem {
        let url = try AudioFixtures.writeCounter(to: root.appendingPathComponent("\(name).caf"), frames: frames, offset: offset)
        return PlaybackItem(id: name, title: name, durationSeconds: Double(frames) / 44_100, track: .file(url))
    }

    /// A session playing `current` out of `items`, rendered offline at 44.1 kHz.
    private func playing(_ items: [PlaybackItem], current: PlaybackItem) async -> Rig {
        let backend = AVInAppPlaybackBackend(offlineSampleRate: 44_100)
        let source = InAppPlaybackSource(backend: backend)
        let clock = ManualClock()
        let manager = CaptureManager(sources: [source], runsAnalysisTimer: false, clock: { clock.now })
        let transport = PlaybackTransport(manager: manager, source: source)
        transport.prepare(order: ListPlayOrder(items), current: current)
        await manager.select(.inAppPlayback)
        XCTAssertEqual(manager.state, .waiting)
        return Rig(backend: backend, source: source, manager: manager, transport: transport, clock: clock)
    }

    /// Everything the renderer could read now, as counter indices (silence skipped).
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

    /// One analysis pass, as the analysis timer would run it, `seconds` later.
    private func analyze(_ rig: Rig, after seconds: Double = 1024.0 / 44_100) {
        rig.clock.advance(seconds)
        rig.manager.stepAnalysisForTesting()
    }

    /// Renders `renders` × 1,024 frames with an analysis pass after each, waits for the tap to
    /// hand over what it will, and returns what reached the renderer's reader.
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

    private func assertRun(_ indices: [Int], startsAt first: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(indices.isEmpty, "no audio reached the renderer", file: file, line: line)
        XCTAssertEqual(indices.first, first, "the first frame the renderer gets", file: file, line: line)
        XCTAssertTrue(CounterDecoder.isConsecutive(indices), "frames reach the renderer in track order with no gap", file: file, line: line)
    }

    // MARK: - (a) play

    func testPlayedAudioReachesTheRendererInOrderAndBecomesActive() async throws {
        let track = try item("a", frames: 132_300)
        let rig = await playing([track], current: track)
        let indices = try await pump(rig, renders: 20)
        assertRun(indices, startsAt: 0)
        XCTAssertGreaterThanOrEqual(indices.count, 17_640)
        XCTAssertEqual(rig.manager.state, .active)
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.position.seconds, 20_480.0 / 44_100, accuracy: 1e-9)
        XCTAssertEqual(rig.transport.position.durationSeconds, 3, accuracy: 1e-9)
        await rig.manager.stop()
    }

    // MARK: - (b) the acceptance: seek while playing, old audio in transit at every stage

    func testSeekUpdatesThePositionAndTheAnalysisWithoutStaleFrames() async throws {
        let track = try item("a", frames: 132_300)
        let rig = await playing([track], current: track)
        _ = try await pump(rig, renders: 20)
        XCTAssertEqual(rig.manager.state, .active)
        XCTAssertGreaterThan(rig.manager.levels.peakDBFS, -20)

        // Old audio now waits in every stage: analyzed but unread (normalized ring), delivered
        // but not analyzed (sink ring), and rendered but not delivered (inside the tap).
        for _ in 0..<9 { _ = try rig.backend.renderOffline(frames: 1024) }
        try await Task.sleep(nanoseconds: 80_000_000)
        analyze(rig)
        XCTAssertGreaterThan(rig.manager.analyzer.normalizedOutput.availableFrames, 0)
        for _ in 0..<9 { _ = try rig.backend.renderOffline(frames: 1024) }
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertGreaterThan(rig.manager.sinkForTesting.ring.availableToRead, 0)

        rig.transport.seek(to: 2.0)

        XCTAssertEqual(rig.transport.position.seconds, 2.0, accuracy: 0.5 / 44_100, "the position is the target at once")
        XCTAssertEqual(rig.manager.analyzer.normalizedOutput.availableFrames, 0, "nothing old is left for the renderer")
        XCTAssertEqual(rig.manager.sinkForTesting.ring.availableToRead, 0, "nothing old is left for the analysis")
        analyze(rig)
        XCTAssertEqual(rig.manager.levels, .silent, "levels are not computed from audio from before the seek")
        XCTAssertEqual(readRenderer(rig), [])
        XCTAssertEqual(rig.manager.state, .active, "a seek is not a state change")

        let indices = try await pump(rig, renders: 20)
        assertRun(indices, startsAt: 88_200)
        XCTAssertGreaterThanOrEqual(indices.count, 17_640)
        XCTAssertEqual(rig.transport.position.seconds, Double(88_200 + 20_480) / 44_100, accuracy: 1e-9)
        XCTAssertGreaterThan(rig.manager.levels.peakDBFS, -20, "levels follow the new audio")
        XCTAssertEqual(rig.manager.state, .active)
        XCTAssertEqual(rig.manager.statistics.formatChangeCount, 0)
        await rig.manager.stop()
    }

    // MARK: - (c) other seeks

    func testSeekWhilePausedThenPlayStartsAtTheTarget() async throws {
        let track = try item("a", frames: 132_300)
        let rig = await playing([track], current: track)
        _ = try await pump(rig, renders: 8)
        await rig.transport.pause()
        rig.transport.seek(to: 1.5)
        XCTAssertEqual(rig.transport.position.seconds, 1.5, accuracy: 0.5 / 44_100)
        XCTAssertEqual(rig.transport.state, .paused)
        for _ in 0..<5 { analyze(rig) }
        XCTAssertEqual(readRenderer(rig), [], "nothing reaches the renderer while paused")
        XCTAssertEqual(rig.transport.position.seconds, 1.5, accuracy: 0.5 / 44_100)

        await rig.transport.play()
        assertRun(try await pump(rig, renders: 12), startsAt: 66_150)
        await rig.manager.stop()
    }

    func testSeekToZeroAndBackwards() async throws {
        let track = try item("a", frames: 132_300)
        let rig = await playing([track], current: track)
        _ = try await pump(rig, renders: 12)
        rig.transport.seek(to: 0)
        XCTAssertEqual(rig.transport.position.seconds, 0)
        assertRun(try await pump(rig, renders: 12), startsAt: 0)
        rig.transport.seek(to: 2.5)
        _ = try await pump(rig, renders: 6)
        rig.transport.seek(to: 0.25)                           // backwards
        assertRun(try await pump(rig, renders: 12), startsAt: 11_025)
        await rig.manager.stop()
    }

    func testOneHundredRapidSeeksLeaveOnlyTheLastPosition() async throws {
        let track = try item("a", frames: 132_300)
        let rig = await playing([track], current: track)
        _ = try await pump(rig, renders: 8)
        for step in 0..<100 {
            rig.transport.seek(to: Double((step * 37) % 250) / 100)
            if step % 4 == 0 {
                _ = try rig.backend.renderOffline(frames: 1024)
                analyze(rig)                                   // some of it gets analyzed in between
            }
        }
        rig.transport.seek(to: 1.0)
        XCTAssertEqual(rig.transport.position.seconds, 1.0, accuracy: 0.5 / 44_100)
        XCTAssertEqual(readRenderer(rig), [], "the scrub left nothing for the renderer")
        assertRun(try await pump(rig, renders: 12), startsAt: 44_100)
        await rig.manager.stop()
    }

    // MARK: - (d) truthful pause

    func testPauseIsPausedNeverActiveAndPlayIsActiveOnlyAfterNewAudio() async throws {
        let track = try item("a", frames: 132_300)
        let rig = await playing([track], current: track)
        _ = try await pump(rig, renders: 15)
        XCTAssertEqual(rig.manager.state, .active)
        let before = rig.transport.position.seconds

        await rig.transport.pause()
        for _ in 0..<20 {
            analyze(rig, after: 0.25)                          // five seconds of pause
            XCTAssertEqual(rig.manager.state, .paused)
            XCTAssertNil(rig.manager.stopReason)
            XCTAssertFalse(rig.manager.prolongedSilenceHint)
        }
        XCTAssertEqual(rig.transport.position.seconds, before, "the position does not move during a pause")
        XCTAssertEqual(rig.transport.state, .paused)

        await rig.transport.play()
        XCTAssertEqual(rig.manager.state, .waiting, "not Active before new audio was analyzed")
        analyze(rig)
        XCTAssertEqual(rig.manager.state, .waiting)
        let resumed = try await pump(rig, renders: 20)
        assertRun(resumed, startsAt: 15 * 1024)
        XCTAssertEqual(rig.manager.state, .active)
        XCTAssertEqual(rig.transport.position.seconds, before + 20_480.0 / 44_100, accuracy: 1e-9)
        await rig.manager.stop()
    }

    // MARK: - (e) Stop playback

    func testStopPlaybackReturnsToZeroAndPlayStartsFromTheBeginning() async throws {
        let track = try item("a", frames: 132_300)
        let rig = await playing([track], current: track)
        _ = try await pump(rig, renders: 12)
        await rig.transport.stop()
        XCTAssertEqual(rig.transport.state, .stopped)
        XCTAssertEqual(rig.transport.position.seconds, 0)
        XCTAssertEqual(rig.manager.state, .paused)
        XCTAssertEqual(rig.manager.activeMode, .inAppPlayback)
        for _ in 0..<5 { analyze(rig) }
        XCTAssertEqual(readRenderer(rig), [])
        await rig.transport.play()
        assertRun(try await pump(rig, renders: 12), startsAt: 0)
        await rig.manager.stop()
    }

    // MARK: - (f) the end, one track in the order

    func testSeekToTheEndOfTheOnlyTrackStartsItAgain() async throws {
        let track = try item("a", frames: 44_100)
        let rig = await playing([track], current: track)
        _ = try await pump(rig, renders: 8)
        rig.transport.seek(to: 1.0)                            // the end
        XCTAssertEqual(rig.transport.position.seconds, 0, "the only track wraps to its start")
        assertRun(try await pump(rig, renders: 8), startsAt: 0)
        rig.transport.seek(to: 99)                             // beyond the end
        XCTAssertEqual(rig.transport.position.seconds, 0)
        // Near the end it plays on across the loop point without a gap.
        rig.transport.seek(to: 0.95)
        let wrapped = try await pump(rig, renders: 12)
        XCTAssertEqual(wrapped.first, 41_895)
        XCTAssertTrue(wrapped.contains(44_099) && wrapped.contains(0))
        for (previous, next) in zip(wrapped, wrapped.dropFirst()) where next != (previous + 1) % 44_100 {
            XCTFail("gap at the loop point: \(previous) → \(next)")
            break
        }
        XCTAssertEqual(rig.transport.current, track)
        await rig.manager.stop()
    }

    // MARK: - Two tracks (T25)

    func testTheEndOfATrackStartsTheNextAndNothingOfTheOldFollows() async throws {
        let first = try item("a", frames: 22_050)
        let second = try item("b", frames: 66_150, offset: 1_000_000)
        let rig = await playing([first, second], current: first)
        let indices = try await pump(rig, renders: 45)
        XCTAssertEqual(rig.transport.current, second, "the track ended and the next one started")
        XCTAssertEqual(rig.transport.state, .playing)
        let split = try XCTUnwrap(indices.firstIndex { $0 >= 1_000_000 })
        let old = Array(indices[..<split])
        let new = Array(indices[split...])
        assertRun(old, startsAt: 0)
        XCTAssertEqual(old.last, 22_049, "the first track was delivered to its last frame")
        assertRun(new, startsAt: 1_000_000)
        XCTAssertEqual(old.count + new.count, indices.count)
        XCTAssertEqual(rig.manager.activeMode, .inAppPlayback)
        XCTAssertEqual(rig.source.sessionCount, 1, "a track change is not a new session")

        // Next from the last track wraps to the first; a seek right after lands in the new track.
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, first)
        XCTAssertEqual(rig.transport.position.seconds, 0)
        rig.transport.seek(to: 0.25)
        assertRun(Array(try await pump(rig, renders: 6).prefix(4_000)), startsAt: 11_025)
        await rig.manager.stop()
    }

    func testAMissingNextTrackEndsTheSessionAndIsNeverReplacedByAnother() async throws {
        let first = try item("a", frames: 132_300)
        let gone = PlaybackItem(id: "gone", title: "gone", durationSeconds: 1,
                                track: .file(root.appendingPathComponent("gone.caf")))
        let rig = await playing([first, gone], current: first)
        _ = try await pump(rig, renders: 10)
        await rig.transport.next()
        for _ in 0..<50 { await Task.yield() }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(rig.manager.state, .stopped)
        XCTAssertEqual(rig.manager.stopReason, .inAppPlaybackFailed)
        XCTAssertFalse(rig.transport.isAvailable)
        XCTAssertEqual(readRenderer(rig).filter { $0 > 10 * 1024 }, [], "the old track did not go on playing")
    }
}
#endif
