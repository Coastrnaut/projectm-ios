// SeekableGraphTests.swift — the playback graph as a positioned player (AUD-006-T07, T08;
// AUD-006-R4, R8 to R13, R17 to R19, R29; S1 to S5).
//
// The fixture is a track whose every frame carries its own index (`AudioFixtures.writeCounter`),
// played through the production graph (player → mixer → the production tap → PCMSink) in
// AVAudioEngine's offline manual rendering mode at the file's sample rate, so the frames that reach
// the sink can be compared with the position exactly. What this cannot show: real-time rendering,
// the audio session, routes and interruptions (device phase).
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class SeekableGraphTests: XCTestCase {
    private final class Counter: @unchecked Sendable { var value = 0 }

    private var root: URL!
    private let length = 132_300                    // 3 s at 44.1 kHz

    override func setUp() async throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud006-graph")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private struct Rig {
        let graph: InAppPlaybackGraph
        let sink: PCMSink
        let discards: Counter
    }

    private func counterTrack(_ name: String = "counter.caf", frames: Int? = nil, sampleRate: Double = 44_100,
                              channels: Int = 2, offset: Int = 0) throws -> URL {
        try AudioFixtures.writeCounter(to: root.appendingPathComponent(name), frames: frames ?? length,
                                       sampleRate: sampleRate, channels: channels, offset: offset)
    }

    /// A started graph over `url`, rendering offline at 44.1 kHz. The sink counts discards and
    /// drains itself, as it does without an analyzer.
    private func start(_ url: URL, loops: Bool) throws -> Rig {
        let graph = InAppPlaybackGraph(content: try InAppPlaybackGraph.load(.file(url), bundle: .main))
        graph.loops = loops
        try graph.enableOfflineRendering(sampleRate: 44_100, maximumFrameCount: 1024)
        let sink = PCMSink()
        let discards = Counter()
        sink.setDiscardHandler { discards.value += 1; sink.ring.drain() }
        try graph.installTap(into: sink)
        try graph.start()
        return Rig(graph: graph, sink: sink, discards: discards)
    }

    private func collect(_ rig: Rig, renders: Int) async throws -> [Int] {
        try await PlaybackProbe.renderAndCollect({ try rig.graph.renderOffline(frames: $0) }, sink: rig.sink, renders: renders)
    }

    private func assertRun(_ indices: [Int], startsAt first: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(indices.isEmpty, "no audio was delivered", file: file, line: line)
        XCTAssertEqual(indices.first, first, "the first delivered frame", file: file, line: line)
        XCTAssertTrue(CounterDecoder.isConsecutive(indices), "delivered frames are in track order with no gap", file: file, line: line)
    }

    // MARK: (a) play

    func testPlaysFromTheStartInOrderAndReportsThePosition() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        XCTAssertEqual(rig.graph.lengthFrames, 132_300)
        XCTAssertEqual(rig.graph.sampleRate, 44_100)
        XCTAssertEqual(rig.graph.positionFrame, 0)
        let indices = try await collect(rig, renders: 10)
        assertRun(indices, startsAt: 0)
        XCTAssertGreaterThanOrEqual(indices.count, 8_820)
        XCTAssertEqual(rig.graph.positionFrame, 10_240, "position = frames rendered")
    }

    // MARK: (b) seek while playing, with old audio still in transit

    func testSeekWhilePlayingDeliversOnlyTheNewPosition() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        // 10,240 frames rendered: 8,820 are in the sink ring (not read), 1,420 inside the tap.
        for _ in 0..<10 { _ = try rig.graph.renderOffline(frames: 1024) }
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertGreaterThan(rig.sink.ring.availableToRead, 0, "old audio is waiting in the sink")

        rig.graph.seek(toFrame: 88_200)
        XCTAssertEqual(rig.graph.positionFrame, 88_200, "the position is the target at once")
        XCTAssertEqual(rig.sink.ring.availableToRead, 0, "nothing from before the seek is left to deliver")
        XCTAssertEqual(rig.discards.value, 2, "one discard for the start, one for the seek")

        let indices = try await collect(rig, renders: 10)
        assertRun(indices, startsAt: 88_200)
        XCTAssertGreaterThanOrEqual(indices.count, 8_820)
        XCTAssertEqual(rig.graph.positionFrame, 88_200 + 10_240)
    }

    // MARK: (c) the ends

    func testSeekToZeroNegativeEndAndBeyondAreClamped() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        _ = try await collect(rig, renders: 6)

        rig.graph.seek(toFrame: 0)
        XCTAssertEqual(rig.graph.positionFrame, 0)
        assertRun(try await collect(rig, renders: 6), startsAt: 0)

        rig.graph.seek(toFrame: -500)
        XCTAssertEqual(rig.graph.positionFrame, 0)
        assertRun(try await collect(rig, renders: 6), startsAt: 0)

        rig.graph.seek(toFrame: 132_300)
        XCTAssertEqual(rig.graph.positionFrame, 132_300)
        let pastTheEnd = try await collect(rig, renders: 6)
        XCTAssertEqual(pastTheEnd, [], "nothing is played past the end")
        XCTAssertEqual(rig.graph.positionFrame, 132_300)

        rig.graph.seek(toFrame: 9_999_999)
        XCTAssertEqual(rig.graph.positionFrame, 132_300)

        // And back into the track.
        rig.graph.seek(toFrame: 131_000)
        let tail = try await collect(rig, renders: 6)
        assertRun(tail, startsAt: 131_000)
        XCTAssertEqual(tail.last, 132_299, "the track's last frame is delivered")
        XCTAssertEqual(rig.graph.positionFrame, 132_300)
    }

    // MARK: (d) seek while paused

    func testSeekWhilePausedHoldsTheTargetAndResumeStartsThere() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        _ = try await collect(rig, renders: 5)
        rig.graph.pause()
        XCTAssertTrue(rig.graph.isPaused)
        rig.graph.seek(toFrame: 44_100)
        XCTAssertEqual(rig.graph.positionFrame, 44_100)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(PlaybackProbe.drain(rig.sink), [], "nothing is delivered while paused")
        rig.graph.seek(toFrame: 66_150)
        XCTAssertEqual(rig.graph.positionFrame, 66_150)

        try rig.graph.resume()
        XCTAssertFalse(rig.graph.isPaused)
        assertRun(try await collect(rig, renders: 10), startsAt: 66_150)
        XCTAssertEqual(rig.graph.positionFrame, 66_150 + 10_240)
    }

    // MARK: (e) pause and resume

    func testPauseHoldsThePositionExactlyAndResumeContinuesFromIt() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        let before = try await collect(rig, renders: 7)
        assertRun(before, startsAt: 0)
        rig.graph.pause()
        let held = rig.graph.positionFrame
        XCTAssertEqual(held, 7 * 1024)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(rig.graph.positionFrame, held, "the position does not move while paused")
        rig.graph.pause()                                // idempotent
        XCTAssertEqual(rig.graph.positionFrame, held)

        try rig.graph.resume()
        XCTAssertEqual(rig.graph.positionFrame, held)
        let after = try await collect(rig, renders: 10)
        assertRun(after, startsAt: Int(held))
        XCTAssertEqual(rig.graph.positionFrame, held + 10_240)
        try rig.graph.resume()                           // resuming a playing graph changes nothing
        XCTAssertEqual(rig.graph.positionFrame, held + 10_240)
    }

    // MARK: (f) scrubbing

    func testOneHundredRapidSeeksEndAtTheLastTarget() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        _ = try await collect(rig, renders: 5)
        var target: AVAudioFramePosition = 0
        for step in 0..<100 {
            target = AVAudioFramePosition((step * 7_919) % 120_000)
            rig.graph.seek(toFrame: target)
            XCTAssertEqual(rig.graph.positionFrame, target)
            if step % 3 == 0 { _ = try rig.graph.renderOffline(frames: 1024) }   // audio in transit between seeks
        }
        rig.graph.seek(toFrame: 100_000)
        _ = PlaybackProbe.drain(rig.sink)
        let indices = try await collect(rig, renders: 10)
        assertRun(indices, startsAt: 100_000)
        XCTAssertEqual(rig.graph.positionFrame, 100_000 + 10_240)
    }

    // MARK: (g) loop

    func testLoopingTrackWrapsWithoutAGapAndSoDoesThePosition() async throws {
        let rig = try start(try counterTrack(frames: 22_050), loops: true)      // 0.5 s
        defer { rig.graph.stop() }
        let indices = try await collect(rig, renders: 60)                         // 61,440 frames: almost three passes
        XCTAssertEqual(indices.first, 0)
        XCTAssertGreaterThanOrEqual(indices.count, 57_330)
        for (previous, next) in zip(indices, indices.dropFirst()) {
            XCTAssertEqual(next, (previous + 1) % 22_050, "frames continue across the loop point")
            if next != (previous + 1) % 22_050 { break }
        }
        XCTAssertEqual(rig.graph.positionFrame, AVAudioFramePosition(61_440 % 22_050))

        // A seek near the end still wraps; a seek to the end is the start.
        rig.graph.seek(toFrame: 21_000)
        let wrapped = try await collect(rig, renders: 10)
        XCTAssertEqual(wrapped.first, 21_000)
        XCTAssertTrue(wrapped.contains(22_049) && wrapped.contains(0))
        for (previous, next) in zip(wrapped, wrapped.dropFirst()) where next != (previous + 1) % 22_050 {
            XCTFail("gap at the loop point after a seek: \(previous) → \(next)")
            break
        }
        rig.graph.seek(toFrame: 22_050)
        XCTAssertEqual(rig.graph.positionFrame, 0)
        let restarted = try await collect(rig, renders: 6)
        XCTAssertEqual(restarted.first, 0)
    }

    // MARK: (h) end of a track

    func testTrackEndIsReportedOnceAfterTheLastFrame() async throws {
        let rig = try start(try counterTrack(frames: 22_050), loops: false)
        defer { rig.graph.stop() }
        let ended = Counter()
        rig.graph.onTrackEnded = { ended.value += 1 }
        let first = try await collect(rig, renders: 19)                           // 19,456 frames: before the end
        assertRun(first, startsAt: 0)
        XCTAssertEqual(ended.value, 0, "not before the last frame was rendered")
        let rest = try await collect(rig, renders: 8)
        XCTAssertEqual((first + rest).last, 22_049)
        XCTAssertEqual(ended.value, 1)
        XCTAssertEqual(rig.graph.positionFrame, 22_050, "the position stays at the end")
        _ = try await collect(rig, renders: 5)
        XCTAssertEqual(ended.value, 1, "reported once")
    }

    func testASeekCancelsThePendingTrackEnd() async throws {
        let rig = try start(try counterTrack(frames: 22_050), loops: false)
        defer { rig.graph.stop() }
        let ended = Counter()
        rig.graph.onTrackEnded = { ended.value += 1 }
        for _ in 0..<21 { _ = try rig.graph.renderOffline(frames: 1024) }         // 21,504: the end is queued but not reached
        rig.graph.seek(toFrame: 1_000)                                            // stop() fires the old completion
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(ended.value, 0, "the cancelled segment's completion is ignored")
        assertRun(try await collect(rig, renders: 6), startsAt: 1_000)
        XCTAssertEqual(ended.value, 0)
    }

    func testSeekToTheEndWhilePlayingReportsTheEndOnce() async throws {
        let rig = try start(try counterTrack(frames: 22_050), loops: false)
        defer { rig.graph.stop() }
        let ended = Counter()
        rig.graph.onTrackEnded = { ended.value += 1 }
        _ = try await collect(rig, renders: 3)
        rig.graph.seek(toFrame: 22_050)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(ended.value, 1)
        XCTAssertEqual(rig.graph.positionFrame, 22_050)
    }

    func testSeekToTheEndWhilePausedReportsTheEndOnResume() async throws {
        let rig = try start(try counterTrack(frames: 22_050), loops: false)
        defer { rig.graph.stop() }
        let ended = Counter()
        rig.graph.onTrackEnded = { ended.value += 1 }
        rig.graph.pause()
        rig.graph.seek(toFrame: 30_000)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(ended.value, 0)
        XCTAssertEqual(rig.graph.positionFrame, 22_050)
        try rig.graph.resume()
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(ended.value, 1)
    }

    // MARK: (i) stop

    func testStopDuringSeeksIsIdempotentAndFinal() async throws {
        let rig = try start(try counterTrack(frames: 22_050), loops: false)
        let ended = Counter()
        rig.graph.onTrackEnded = { ended.value += 1 }
        _ = try await collect(rig, renders: 3)
        rig.graph.seek(toFrame: 5_000)
        rig.graph.stop()
        rig.graph.stop()
        let schedules = rig.graph.scheduleCount
        let discards = rig.discards.value
        rig.graph.seek(toFrame: 9_000)                   // after stop: ignored
        rig.graph.pause()
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(rig.graph.scheduleCount, schedules, "nothing is scheduled after stop")
        XCTAssertEqual(rig.discards.value, discards)
        XCTAssertEqual(ended.value, 0)
        XCTAssertFalse(rig.graph.isRunning)
        XCTAssertEqual(PlaybackProbe.drain(rig.sink).filter { $0 != 0 }, [], "no audio after stop")
    }

    // MARK: (j) one discard per cut

    func testEveryCutDiscardsDownstreamExactlyOnce() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        XCTAssertEqual(rig.discards.value, 1, "start")
        rig.graph.seek(toFrame: 10)
        XCTAssertEqual(rig.discards.value, 2, "seek while playing")
        rig.graph.pause()
        rig.graph.seek(toFrame: 20)
        try rig.graph.resume()
        XCTAssertEqual(rig.discards.value, 4, "seek while paused, then resume")
        let other = try InAppPlaybackGraph.load(.file(try counterTrack("other.caf", offset: 1_000_000)), bundle: .main)
        try rig.graph.replace(content: other)
        XCTAssertEqual(rig.discards.value, 5, "track change")
    }

    // MARK: Track change (T08)

    func testReplaceStartsTheNewTrackAtZeroAndNothingOfTheOldFollows() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        for _ in 0..<10 { _ = try rig.graph.renderOffline(frames: 1024) }         // old audio in transit
        try await Task.sleep(nanoseconds: 80_000_000)
        let other = try InAppPlaybackGraph.load(.file(try counterTrack("other.caf", frames: 66_150, offset: 1_000_000)), bundle: .main)
        try rig.graph.replace(content: other)
        XCTAssertEqual(rig.graph.positionFrame, 0)
        XCTAssertEqual(rig.graph.lengthFrames, 66_150)
        XCTAssertEqual(rig.sink.ring.availableToRead, 0)
        let indices = try await collect(rig, renders: 10)
        assertRun(indices, startsAt: 1_000_000)          // the new track's frame 0
        XCTAssertEqual(rig.graph.positionFrame, 10_240)

        // A seek right after a change applies to the new track.
        try rig.graph.replace(content: try InAppPlaybackGraph.load(.file(root.appendingPathComponent("counter.caf")), bundle: .main))
        rig.graph.seek(toFrame: 50_000)
        assertRun(try await collect(rig, renders: 10), startsAt: 50_000)
    }

    func testReplaceWithAnotherRateAndChannelCountKeepsPlaying() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        _ = try await collect(rig, renders: 5)
        let mono = try AudioFixtures.writeTone(to: root.appendingPathComponent("mono48.wav"), seconds: 1, sampleRate: 48_000, channels: 1)
        try rig.graph.replace(content: try InAppPlaybackGraph.load(.file(mono), bundle: .main))
        XCTAssertEqual(rig.graph.sampleRate, 48_000)
        XCTAssertEqual(rig.graph.lengthFrames, 48_000)
        XCTAssertEqual(rig.graph.positionFrame, 0)
        var peak: Float = 0
        var samples = 0
        for _ in 0..<30 {
            _ = try rig.graph.renderOffline(frames: 1024)
            try await Task.sleep(nanoseconds: 2_000_000)
            let chunk = PlaybackProbe.drain(rig.sink)
            samples += chunk.count
            peak = max(peak, chunk.map { abs($0) }.max() ?? 0)
        }
        XCTAssertGreaterThan(samples, 0)
        XCTAssertEqual(peak, 0.5, accuracy: 0.06, "the new track is heard at its own level")
        let position = rig.graph.positionFrame
        XCTAssertGreaterThan(position, 20_000, "the position advances in the new track's own rate")
        XCTAssertLessThanOrEqual(position, 33_437)       // 30,720 output frames are at most 33,437 frames at 48 kHz

        // And back to a stereo 44.1 kHz track.
        try rig.graph.replace(content: try InAppPlaybackGraph.load(.file(root.appendingPathComponent("counter.caf")), bundle: .main))
        let back = try await collect(rig, renders: 20)
        assertRun(back, startsAt: 0)
    }

    func testReplaceWhilePausedHoldsZeroUntilResume() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        _ = try await collect(rig, renders: 5)
        rig.graph.pause()
        let other = try InAppPlaybackGraph.load(.file(try counterTrack("other.caf", offset: 1_000_000)), bundle: .main)
        try rig.graph.replace(content: other)
        XCTAssertTrue(rig.graph.isPaused)
        XCTAssertEqual(rig.graph.positionFrame, 0)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(PlaybackProbe.drain(rig.sink), [])
        try rig.graph.resume()
        assertRun(try await collect(rig, renders: 10), startsAt: 1_000_000)
    }

    func testAMissingTrackCannotBeLoadedAndTheOldOneIsNotHeardAgain() async throws {
        let rig = try start(try counterTrack(), loops: false)
        defer { rig.graph.stop() }
        _ = try await collect(rig, renders: 5)
        XCTAssertThrowsError(try InAppPlaybackGraph.load(.file(root.appendingPathComponent("gone.caf")), bundle: .main))
        // The caller (the backend) silences the graph when the next track cannot be loaded.
        rig.graph.silence()
        let afterwards = try await collect(rig, renders: 8)
        XCTAssertEqual(afterwards, [], "no audio of the old track after a failed change")
    }
}
#endif
