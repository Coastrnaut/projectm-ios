// LoopingChangeGraphTests.swift — a change of looping while playing keeps the player running and the
// audio continuous (QA-011 device run 2026-11-19, AUD-004-R9; specs/017-aud-004-loop-track-and-queue).
//
// On device D3 a repeat-mode change during playback left up to 50 ms of silence: `updateLooping`
// stopped the player and started it again. These tests play a counter track (every frame carries its
// own index) through the production graph in offline manual rendering and check, per frame, that a
// change in either direction stops nothing, inserts no silent frame, skips or repeats no frame, lets
// nothing of a muted next pass through, and keeps the position. Offline rendering hides the
// real-time restart latency, so the players' stop count (`playerStopCount`) is what proves the
// restart is gone; the device rerun of B05AudioDeviceTests.testAUD004RepeatModes measures the
// silence itself.
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class LoopingChangeGraphTests: XCTestCase {
    private final class Counter: @unchecked Sendable { var value = 0 }

    private var root: URL!

    override func setUp() async throws {
        root = try AudioFixtures.makeTemporaryDirectory("qa011-looping")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private struct Rig {
        let graph: InAppPlaybackGraph
        let sink: PCMSink
        let ended: Counter
    }

    private func start(frames: Int, loops: Bool) throws -> Rig {
        let url = try AudioFixtures.writeCounter(to: root.appendingPathComponent("counter-\(frames).caf"), frames: frames)
        let graph = InAppPlaybackGraph(content: try InAppPlaybackGraph.load(.file(url), bundle: .main))
        graph.loops = loops
        try graph.enableOfflineRendering(sampleRate: 44_100, maximumFrameCount: 1024)
        let sink = PCMSink()
        sink.setDiscardHandler { sink.ring.drain() }
        try graph.installTap(into: sink)
        let ended = Counter()
        graph.onTrackEnded = { ended.value += 1 }
        try graph.start()
        return Rig(graph: graph, sink: sink, ended: ended)
    }

    /// Renders `renders` × 1,024 frames (main-actor work runs in between), waits for the tap, and
    /// returns one entry per delivered frame: its counter index, or nil for a silent frame.
    private func collect(_ rig: Rig, renders: Int) async throws -> [Int?] {
        var samples: [Float] = []
        for _ in 0..<renders {
            _ = try rig.graph.renderOffline(frames: 1024)
            samples += PlaybackProbe.drain(rig.sink)
            try await Task.sleep(nanoseconds: 500_000)
        }
        var quiet = 0
        while quiet < 12 {
            try await Task.sleep(nanoseconds: 5_000_000)
            let more = PlaybackProbe.drain(rig.sink)
            if more.isEmpty { quiet += 1 } else { quiet = 0; samples += more }
        }
        return stride(from: 0, to: samples.count - 1, by: 2).map {
            CounterDecoder.frameIndex(left: samples[$0], right: samples[$0 + 1])
        }
    }

    /// The audible part of `frames`: from the first to the last non-silent frame.
    private func audible(_ frames: [Int?]) -> ArraySlice<Int?> {
        guard let first = frames.firstIndex(where: { $0 != nil }),
              let last = frames.lastIndex(where: { $0 != nil }) else { return [] }
        return frames[first...last]
    }

    /// Asserts that `frames` (silence included) start at `first`, contain no silent frame and run on
    /// frame by frame, wrapping at `length`. Returns the audible indices.
    @discardableResult
    private func assertContinuous(_ frames: [Int?], from first: Int, length: Int, _ message: String,
                                  file: StaticString = #filePath, line: UInt = #line) -> [Int] {
        let run = audible(frames)
        XCTAssertFalse(run.isEmpty, "\(message): nothing was delivered", file: file, line: line)
        let silent = run.filter { $0 == nil }.count
        XCTAssertEqual(silent, 0, "\(message): \(silent) silent frames inside the audio", file: file, line: line)
        let indices = run.compactMap { $0 }
        XCTAssertEqual(indices.first, first, "\(message): the first frame", file: file, line: line)
        for (previous, next) in zip(indices, indices.dropFirst()) where next != (previous + 1) % length {
            XCTFail("\(message): \(previous) → \(next)", file: file, line: line)
            break
        }
        return indices
    }

    // MARK: - Looping off (One Track → All Tracks or Off)

    func testLoopingOffInALaterPassStopsNothingAndPlaysThatPassToItsEndOnce() async throws {
        let length = 22_050                                                        // 0.5 s
        let rig = try start(frames: length, loops: true)
        defer { rig.graph.stop() }
        var stream = try await collect(rig, renders: 30)                           // 30,720 frames: into the second pass
        let stops = rig.graph.playerStopCount
        let schedules = rig.graph.scheduleCount
        let before = rig.graph.positionFrame
        rig.graph.updateLooping(false)
        XCTAssertEqual(rig.graph.playerStopCount, stops, "the change stops no player")
        XCTAssertEqual(rig.graph.scheduleCount, schedules, "nothing is re-queued")
        XCTAssertEqual(rig.graph.positionFrame, before, "the position is kept")

        stream += try await collect(rig, renders: 45)                              // past the end of the muted next pass
        let indices = assertContinuous(stream, from: 0, length: length, "across the change")
        XCTAssertEqual(indices.count, 2 * length, "two whole passes; the queued third is never heard")
        XCTAssertEqual(indices.last, length - 1, "the second pass plays to its last frame")
        XCTAssertEqual(rig.ended.value, 1, "the end is reported once")
        XCTAssertEqual(rig.graph.positionFrame, AVAudioFramePosition(length), "the position stays at the end")
        XCTAssertEqual(rig.graph.playerStopCount, stops, "nothing stopped a player at the end either")
    }

    func testLoopingOffInTheFirstPassPlaysTheTrackOnce() async throws {
        let length = 22_050
        let rig = try start(frames: length, loops: true)
        defer { rig.graph.stop() }
        var stream = try await collect(rig, renders: 10)
        let stops = rig.graph.playerStopCount
        rig.graph.updateLooping(false)
        stream += try await collect(rig, renders: 45)
        let indices = assertContinuous(stream, from: 0, length: length, "across the change")
        XCTAssertEqual(indices.count, length, "the track once, to its last frame")
        XCTAssertEqual(rig.ended.value, 1)
        XCTAssertEqual(rig.graph.playerStopCount, stops)
    }

    func testLoopingOffThenOnAgainBeforeTheEndKeepsRepeating() async throws {
        let length = 22_050
        let rig = try start(frames: length, loops: true)
        defer { rig.graph.stop() }
        var stream = try await collect(rig, renders: 8)
        let stops = rig.graph.playerStopCount
        rig.graph.updateLooping(false)
        stream += try await collect(rig, renders: 6)                               // 14,336: before the end
        rig.graph.updateLooping(true)
        stream += try await collect(rig, renders: 40)                              // 55,296 frames in all
        let indices = assertContinuous(stream, from: 0, length: length, "off, then on")
        XCTAssertGreaterThan(indices.count, 2 * length, "the muted next pass is heard again")
        XCTAssertEqual(rig.ended.value, 0)
        XCTAssertEqual(rig.graph.playerStopCount, stops)
        XCTAssertEqual(rig.graph.positionFrame, AVAudioFramePosition(54 * 1024 % length))
    }

    /// QA-011 pass 4 (D2, 2026-11-19), AUD-003-T22: a track is added while a lone track loops. The
    /// change of looping lands in an odd pass (played by the partner node, a next pass queued and
    /// muted on the player); at the end the transport replaces the track. The next track starts
    /// right after the last frame of that pass, from its own first frame, with nothing of the muted
    /// pass in between and at most the rest of one render cycle of silence (the track change waits
    /// for the end's completion on the main actor, as it did before the two-node schedule).
    func testAddingATrackWhileALoneTrackLoopsEndsThePassAndTheNextTrackFollows() async throws {
        let length = 22_050, nextLength = 11_025
        let rig = try start(frames: length, loops: true)
        defer { rig.graph.stop() }
        let nextURL = try AudioFixtures.writeCounter(to: root.appendingPathComponent("next-\(nextLength).caf"), frames: nextLength)
        let next = try InAppPlaybackGraph.load(.file(nextURL), bundle: .main)
        let graph = rig.graph, ended = rig.ended
        graph.onTrackEnded = {
            ended.value += 1
            guard ended.value == 1 else { return }                                  // the next track is the last
            graph.loops = false
            try? graph.replace(content: next)                                       // as the transport does at a track end
        }
        var stream = try await collect(rig, renders: 30)                           // 30,720 frames: in the second (odd) pass
        let stops = rig.graph.playerStopCount
        rig.graph.updateLooping(false)
        XCTAssertEqual(rig.graph.playerStopCount, stops, "the change stops no player")
        stream += try await collect(rig, renders: 45)                              // past both ends
        let run = audible(stream)
        XCTAssertLessThan(run.filter { $0 == nil }.count, 1024, "at most one render cycle of silence between the tracks")
        let indices = run.compactMap { $0 }
        XCTAssertEqual(indices.count, 2 * length + nextLength, "two passes, then the next track once; the muted pass is never heard")
        XCTAssertEqual(Array(indices[(2 * length - 2)..<(2 * length + 2)]), [length - 2, length - 1, 0, 1],
                       "the next track's first frame follows the pass's last frame")
        XCTAssertEqual(indices.last, nextLength - 1)
        XCTAssertEqual(ended.value, 2, "each track's end is reported once")
    }

    // MARK: - Looping on (All Tracks or Off → One Track)

    func testLoopingOnMidTrackAppendsTheNextPassWithoutAStop() async throws {
        let length = 22_050
        let rig = try start(frames: length, loops: false)
        defer { rig.graph.stop() }
        var stream = try await collect(rig, renders: 10)                           // 10,240 frames
        let stops = rig.graph.playerStopCount
        let before = rig.graph.positionFrame
        rig.graph.updateLooping(true)
        XCTAssertEqual(rig.graph.playerStopCount, stops, "the change stops no player")
        XCTAssertEqual(rig.graph.positionFrame, before, "the position is kept")

        stream += try await collect(rig, renders: 40)                              // 51,200 frames: into the third pass
        let indices = assertContinuous(stream, from: 0, length: length, "across the change and the loop points")
        XCTAssertGreaterThan(indices.count, 2 * length)
        XCTAssertEqual(rig.ended.value, 0, "a looping track never ends")
        XCTAssertEqual(rig.graph.playerStopCount, stops)
        XCTAssertEqual(rig.graph.positionFrame, AVAudioFramePosition(51_200 % length), "the position wraps")
    }

    func testLoopingOnThenOffAgainPlaysTheTrackToItsEndOnce() async throws {
        let length = 22_050
        let rig = try start(frames: length, loops: false)
        defer { rig.graph.stop() }
        var stream = try await collect(rig, renders: 5)
        let stops = rig.graph.playerStopCount
        rig.graph.updateLooping(true)
        stream += try await collect(rig, renders: 5)
        rig.graph.updateLooping(false)
        stream += try await collect(rig, renders: 45)
        let indices = assertContinuous(stream, from: 0, length: length, "on, then off")
        XCTAssertEqual(indices.count, length, "the track once; the queued next pass is never heard")
        XCTAssertEqual(rig.ended.value, 1)
        XCTAssertEqual(rig.graph.playerStopCount, stops)
        XCTAssertEqual(rig.graph.positionFrame, AVAudioFramePosition(length))
    }

    func testLoopingFromASeekWrapsAtTheTrackEndAndOffEndsThere() async throws {
        let length = 22_050
        let rig = try start(frames: length, loops: true)
        defer { rig.graph.stop() }
        _ = try await collect(rig, renders: 2)
        rig.graph.seek(toFrame: 15_000)                                            // a cut: later passes are offset
        var stream = try await collect(rig, renders: 12)                           // 12,288: into the second pass
        let stops = rig.graph.playerStopCount
        rig.graph.updateLooping(false)
        stream += try await collect(rig, renders: 45)
        let indices = assertContinuous(stream, from: 15_000, length: length, "from the seek, across the loop point")
        XCTAssertEqual(indices.count, (length - 15_000) + length, "the rest of the first pass, then one whole pass")
        XCTAssertEqual(rig.ended.value, 1)
        XCTAssertEqual(rig.graph.playerStopCount, stops)
    }

    // MARK: - Position math

    func testTimelinePositionMath() {
        XCTAssertEqual(PlaybackPositionMath.frame(timeline: 10, end: 100, length: 100), 10)
        XCTAssertEqual(PlaybackPositionMath.frame(timeline: 100, end: 100, length: 100), 100, "the end")
        XCTAssertEqual(PlaybackPositionMath.frame(timeline: 150, end: 200, length: 100), 50, "a later pass that ends")
        XCTAssertEqual(PlaybackPositionMath.frame(timeline: 260, end: 200, length: 100), 100, "past the end")
        XCTAssertEqual(PlaybackPositionMath.frame(timeline: 260, end: nil, length: 100), 60, "looping wraps")
        XCTAssertEqual(PlaybackPositionMath.frame(timeline: 5, end: nil, length: 0), 0)
        XCTAssertEqual(PlaybackPositionMath.passEnd(after: 0, length: 100), 100)
        XCTAssertEqual(PlaybackPositionMath.passEnd(after: 99, length: 100), 100)
        XCTAssertEqual(PlaybackPositionMath.passEnd(after: 100, length: 100), 200, "strictly after")
    }
}
#endif
