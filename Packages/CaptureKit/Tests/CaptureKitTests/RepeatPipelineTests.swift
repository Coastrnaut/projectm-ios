// RepeatPipelineTests.swift — the roadmap acceptance for AUD-004, through the whole pipeline:
// "End-of-track behavior matches each repeat mode under deterministic clock tests."
// (AUD-004-T05; AUD-004-R3 to R9; S1 to S3.)
//
// Production code end to end, rendered offline with an injected manual clock, as in
// QueuePipelineTests (AUD-003): PlayQueue (stored in a temporary folder) → PlaybackTransport →
// InAppPlaybackSource → AVInAppPlaybackBackend → InAppPlaybackGraph → PCMSink → analysis → the
// renderer's ring. Three counter tracks A, B, C carry `track × 1,000,000 + frame`, so the stream the
// renderer would read shows which track played which frames, in which order, and whether anything
// was cut, repeated or added. No assertion depends on elapsed time: renders are counted, and the
// drain at the end waits for a condition under a 30 s ceiling. Not shown here: real-time rendering,
// the audio session, routes and interruptions on hardware (AUD-004-T19, device phase).
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
@testable import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class RepeatPipelineTests: XCTestCase {
    private struct Rig {
        let backend: AVInAppPlaybackBackend
        let manager: CaptureManager
        let transport: PlaybackTransport
        let queue: PlayQueue
        let clock: ManualClock
    }

    /// A stretch of consecutive frames of one track.
    private struct Run: Equatable, CustomStringConvertible {
        let track: Int
        let from: Int
        let to: Int
        var description: String { "\(["A", "B", "C"][track])[\(from)…\(to)]" }
    }

    private var root: URL!
    private static let trackFrames = 11_025                   // 0.25 s at 44.1 kHz
    private static let last = trackFrames - 1
    private static let stride = 1_000_000

    override func setUp() async throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud004-pipeline")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Track `n` (0 = A, 1 = B, 2 = C): frames carry `n × 1,000,000 + index`; a fixed UUID id.
    private func track(_ n: Int) throws -> PlaybackItem {
        let url = try AudioFixtures.writeCounter(to: root.appendingPathComponent("\(n).caf"), frames: Self.trackFrames,
                                                 offset: n * Self.stride)
        return PlaybackItem(id: String(format: "00000000-0000-0000-0000-%012d", n + 1), title: "Track \(n)",
                            durationSeconds: Double(Self.trackFrames) / 44_100, track: .file(url))
    }

    private func threeTracks() throws -> [PlaybackItem] {
        try [track(0), track(1), track(2)]
    }

    /// Plays `current` from the queue A, B, C in `mode`; the queue is stored in `folder`.
    private func playing(_ tracks: [PlaybackItem], current: PlaybackItem, mode: RepeatMode,
                         folder: String = "queue") async throws -> Rig {
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        let queue = PlayQueue(store: PlayQueueStore(directory: directory))
        queue.setLibrary(tracks)
        queue.setRepeatMode(mode)
        let backend = AVInAppPlaybackBackend(offlineSampleRate: 44_100)
        let source = InAppPlaybackSource(backend: backend)
        let clock = ManualClock()
        let manager = CaptureManager(sources: [source], runsAnalysisTimer: false, clock: { clock.now })
        let transport = PlaybackTransport(manager: manager, source: source)
        transport.prepare(order: queue, current: current)
        await manager.select(.inAppPlayback)
        XCTAssertEqual(manager.state, .waiting)
        return Rig(backend: backend, manager: manager, transport: transport, queue: queue, clock: clock)
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

    /// Renders up to `renders` × 1,024 frames (only while the transport plays: a stopped or paused
    /// engine renders nothing) with an analysis pass after each, then drains the tap until
    /// `done(stream)` holds and nothing more arrives, under a 30 s ceiling.
    private func pump(_ rig: Rig, renders: Int, until done: ([Int]) -> Bool = { _ in true },
                      file: StaticString = #filePath, line: UInt = #line) async throws -> [Int] {
        var indices: [Int] = []
        for _ in 0..<renders {
            if rig.transport.state == .playing { _ = try rig.backend.renderOffline(frames: 1024) }
            try await Task.sleep(nanoseconds: 500_000)          // lets the graph's main-actor callbacks run
            rig.clock.advance(1024.0 / 44_100)
            rig.manager.stepAnalysisForTesting()
            indices += readRenderer(rig)
        }
        let deadline = Date().addingTimeInterval(30)
        var quiet = 0
        while (quiet < 20 || !done(indices)), Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
            rig.manager.stepAnalysisForTesting()
            let more = readRenderer(rig)
            if more.isEmpty { quiet += 1 } else { quiet = 0; indices += more }
        }
        XCTAssertTrue(done(indices), "the expected stream arrived within 30 s: \(runs(indices))", file: file, line: line)
        return indices
    }

    /// Waits for a transport condition (the end of queue's stop is a main-actor task), under 30 s.
    private func waitUntil(_ what: String, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(30)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(condition(), what)
    }

    private func runs(_ indices: [Int]) -> [Run] {
        var result: [Run] = []
        for value in indices {
            let track = value / Self.stride, frame = value % Self.stride
            if let previous = result.last, previous.track == track, previous.to + 1 == frame {
                result[result.count - 1] = Run(track: track, from: previous.from, to: frame)
            } else {
                result.append(Run(track: track, from: frame, to: frame))
            }
        }
        return result
    }

    private func whole(_ track: Int) -> Run { Run(track: track, from: 0, to: Self.last) }

    // MARK: - All Tracks (AUD-004-R3): A → B → C → A

    func testAllTracksPlaysEachTrackWholeAndWrapsToTheFirst() async throws {
        let tracks = try threeTracks()
        let rig = try await playing(tracks, current: tracks[0], mode: .all)
        let stream = try await pump(rig, renders: 40) { self.runs($0).count >= 4 }
        let played = runs(stream)
        XCTAssertEqual(Array(played.prefix(3)), [whole(0), whole(1), whole(2)], "\(played)")
        XCTAssertEqual(played[3].track, 0, "after C comes A")
        XCTAssertEqual(played[3].from, 0, "from its first frame")
        XCTAssertEqual(rig.transport.current, tracks[0])
        XCTAssertEqual(rig.transport.state, .playing)
        await rig.manager.stop()
    }

    // MARK: - One Track (AUD-004-R4)

    func testOneTrackRepeatsTheCurrentTrackFrameExactAndNothingElsePlays() async throws {
        let tracks = try threeTracks()
        let rig = try await playing(tracks, current: tracks[0], mode: .one)
        let stream = try await pump(rig, renders: 32) { self.runs($0).count >= 3 }
        let played = runs(stream)
        XCTAssertEqual(Array(played.prefix(2)), [whole(0), whole(0)], "A, then A again from frame 0: \(played)")
        XCTAssertEqual(played[2].track, 0)
        XCTAssertEqual(played[2].from, 0)
        XCTAssertFalse(stream.contains { $0 >= Self.stride }, "B and C never play")
        XCTAssertEqual(rig.transport.current, tracks[0])
        XCTAssertEqual(rig.transport.state, .playing)
        await rig.manager.stop()
    }

    // MARK: - Off (AUD-004-R5, R6): A → B → C, then Stopped at A's 0:00

    /// Plays the queue to its end in Off and returns the stream; leaves the transport stopped.
    private func playToTheEndInOff(folder: String) async throws -> (Rig, [Int], [PlaybackItem]) {
        let tracks = try threeTracks()
        let rig = try await playing(tracks, current: tracks[0], mode: .off, folder: folder)
        var stream = try await pump(rig, renders: 40) { self.runs($0).last == self.whole(2) }
        await waitUntil("stopped at the end of the queue") { rig.transport.state == .stopped }
        stream += try await pump(rig, renders: 10)              // stopped: nothing more is rendered
        return (rig, stream, tracks)
    }

    func testOffStopsAfterTheLastTrackAndPlayStartsTheQueueAgain() async throws {
        let (rig, stream, tracks) = try await playToTheEndInOff(folder: "off")
        XCTAssertEqual(runs(stream), [whole(0), whole(1), whole(2)], "every frame of A, B, C once, then nothing")
        XCTAssertEqual(rig.transport.state, .stopped)
        XCTAssertEqual(rig.manager.state, .paused, "a user stop: the session and the visualizer stay")
        XCTAssertTrue(rig.transport.isAvailable)
        XCTAssertEqual(rig.transport.current, tracks[0], "the first queued track is cued")
        XCTAssertEqual(rig.transport.position.seconds, 0)
        XCTAssertEqual(rig.queue.currentID, tracks[0].id)

        await rig.transport.play()
        XCTAssertEqual(rig.transport.state, .playing)
        let again = try await pump(rig, renders: 6) { !$0.isEmpty }
        XCTAssertEqual(runs(again).first?.track, 0)
        XCTAssertEqual(runs(again).first?.from, 0, "A from its first frame")
        await rig.manager.stop()
    }

    // MARK: - Repeated runs (AUD-004-S3)

    func testTheSameScenarioTwiceDeliversIdenticalFrames() async throws {
        let (first, firstStream, _) = try await playToTheEndInOff(folder: "run1")
        await first.manager.stop()
        let (second, secondStream, _) = try await playToTheEndInOff(folder: "run2")
        await second.manager.stop()
        XCTAssertEqual(firstStream.count, 3 * Self.trackFrames)
        XCTAssertEqual(firstStream, secondStream)
    }

    // MARK: - Switches mid-track (AUD-004-R9, S2)

    func testAllToOneMidTrackKeepsThePositionAndRepeatsTheTrack() async throws {
        let tracks = try threeTracks()
        let rig = try await playing(tracks, current: tracks[0], mode: .all)
        var stream = try await pump(rig, renders: 4)
        let before = rig.transport.position.seconds
        rig.queue.setRepeatMode(.one)
        XCTAssertEqual(rig.transport.position.seconds, before, accuracy: 1.0 / 44_100, "the position is kept")
        XCTAssertEqual(rig.transport.state, .playing)
        stream += try await pump(rig, renders: 20) { self.runs($0).count >= 2 }
        let played = runs(stream)
        XCTAssertEqual(played.first, whole(0), "A consecutive across the switch, to its last frame: \(played)")
        XCTAssertEqual(played[1].track, 0, "then A again")
        XCTAssertEqual(played[1].from, 0)
        XCTAssertFalse(stream.contains { $0 >= Self.stride }, "B did not play")
        await rig.manager.stop()
    }

    func testOneToAllMidTrackPlaysTheTrackOnceToItsEndThenTheNext() async throws {
        let tracks = try threeTracks()
        let rig = try await playing(tracks, current: tracks[0], mode: .one)
        var stream = try await pump(rig, renders: 4)
        let before = rig.transport.position.seconds
        rig.queue.setRepeatMode(.all)
        XCTAssertEqual(rig.transport.position.seconds, before, accuracy: 1.0 / 44_100)
        stream += try await pump(rig, renders: 20) { self.runs($0).count >= 2 }
        let played = runs(stream)
        XCTAssertEqual(played.first, whole(0), "\(played)")
        XCTAssertEqual(played[1].track, 1, "B follows")
        XCTAssertEqual(played[1].from, 0)
        await rig.manager.stop()
    }

    func testAllToOffOnTheLastTrackEndsThePlayback() async throws {
        let tracks = try threeTracks()
        let rig = try await playing(tracks, current: tracks[2], mode: .all)
        var stream = try await pump(rig, renders: 4)
        let before = rig.transport.position.seconds
        rig.queue.setRepeatMode(.off)
        XCTAssertEqual(rig.transport.position.seconds, before, accuracy: 1.0 / 44_100)
        stream += try await pump(rig, renders: 20) { self.runs($0).last == self.whole(2) }
        await waitUntil("stopped") { rig.transport.state == .stopped }
        stream += try await pump(rig, renders: 6)
        XCTAssertEqual(runs(stream), [whole(2)], "C to its end, consecutive across the switch, then nothing")
        XCTAssertEqual(rig.transport.current, tracks[0])
        XCTAssertEqual(rig.transport.position.seconds, 0)
        await rig.manager.stop()
    }
}
#endif
