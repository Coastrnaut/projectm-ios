// QueuePipelineTests.swift — the roadmap acceptance for AUD-003, through the whole pipeline:
// "Reordering three tracks changes next-track order and persists across relaunch."
// (AUD-003-T05; AUD-003-R1, R7, R8, R13; S1.)
//
// Production code end to end, rendered offline, as in TransportPipelineTests (AUD-006):
// PlayQueue (stored in a temporary library folder) → PlaybackTransport → InAppPlaybackSource →
// AVInAppPlaybackBackend → InAppPlaybackGraph → PCMSink → analysis → the renderer's ring. Each
// track's frames carry their own index plus a per-track offset, so the stream the renderer would
// read shows which track played, from which frame, and whether anything was cut or repeated.
// "Relaunch" is a new PlayQueue over the same folder. Not shown here: real-time rendering, the
// audio session, routes and interruptions on hardware (AUD-003-T22, device phase).
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
@testable import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class QueuePipelineTests: XCTestCase {
    private struct Rig {
        let backend: AVInAppPlaybackBackend
        let manager: CaptureManager
        let transport: PlaybackTransport
        let clock: ManualClock
    }

    private var root: URL!
    private static let trackFrames = 22_050                   // 0.5 s at 44.1 kHz

    override func setUp() async throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud003-pipeline")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A counter track whose frames carry `offset + index`; its id is a fixed UUID.
    private func track(_ n: Int, offset: Int) throws -> PlaybackItem {
        let url = try AudioFixtures.writeCounter(to: root.appendingPathComponent("\(n).caf"), frames: Self.trackFrames,
                                                 offset: offset)
        return PlaybackItem(id: String(format: "00000000-0000-0000-0000-%012d", n), title: "Track \(n)",
                            durationSeconds: Double(Self.trackFrames) / 44_100, track: .file(url))
    }

    private func queue(_ library: [PlaybackItem]) -> PlayQueue {
        let queue = PlayQueue(store: PlayQueueStore(directory: root))
        queue.setLibrary(library)
        return queue
    }

    private func playing(_ order: PlayQueue, current: PlaybackItem) async -> Rig {
        let backend = AVInAppPlaybackBackend(offlineSampleRate: 44_100)
        let source = InAppPlaybackSource(backend: backend)
        let clock = ManualClock()
        let manager = CaptureManager(sources: [source], runsAnalysisTimer: false, clock: { clock.now })
        let transport = PlaybackTransport(manager: manager, source: source)
        transport.prepare(order: order, current: current)
        await manager.select(.inAppPlayback)
        XCTAssertEqual(manager.state, .waiting)
        return Rig(backend: backend, manager: manager, transport: transport, clock: clock)
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

    /// Renders `renders` × 1,024 frames with an analysis pass after each, then lets the tap hand
    /// over what it holds; returns what reached the renderer's reader.
    private func pump(_ rig: Rig, renders: Int) async throws -> [Int] {
        var indices: [Int] = []
        for _ in 0..<renders {
            _ = try rig.backend.renderOffline(frames: 1024)
            try await Task.sleep(nanoseconds: 500_000)
            rig.clock.advance(1024.0 / 44_100)
            rig.manager.stepAnalysisForTesting()
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

    /// Splits a stream at the first frame of the track with `offset`.
    private func split(_ indices: [Int], at offset: Int) throws -> (before: [Int], after: [Int]) {
        let index = try XCTUnwrap(indices.firstIndex { $0 >= offset && $0 < offset + Self.trackFrames }, "track at \(offset) never played")
        return (Array(indices[..<index]), Array(indices[index...]))
    }

    // MARK: - The acceptance (AUD-003-S1)

    func testReorderingThreeTracksWhilePlayingChangesTheNextTrackAndPersistsAcrossRelaunch() async throws {
        let a = try track(1, offset: 0)
        let b = try track(2, offset: 1_000_000)
        let c = try track(3, offset: 2_000_000)
        let order = queue([a, b, c])
        let rig = await playing(order, current: a)
        XCTAssertEqual(order.item(after: a.id), b, "before the edit B follows A")

        var stream = try await pump(rig, renders: 8)
        let before = rig.transport.position.seconds
        order.moveUp(c.id)                                     // A, C, B while A plays
        XCTAssertEqual(rig.transport.position.seconds, before, "the edit does not move the position")
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.current, a)
        XCTAssertEqual(order.items, [a, c, b])

        stream += try await pump(rig, renders: 24)
        XCTAssertEqual(rig.transport.current, c, "A ended and C, not B, followed")
        let (old, new) = try split(stream, at: 2_000_000)
        XCTAssertEqual(old.first, 0)
        XCTAssertEqual(old.last, Self.trackFrames - 1, "A played to its last frame")
        XCTAssertTrue(CounterDecoder.isConsecutive(old), "no gap, cut or repeat in A across the edit")
        XCTAssertEqual(new.first, 2_000_000)
        XCTAssertTrue(CounterDecoder.isConsecutive(new))
        XCTAssertFalse(stream.contains { $0 >= 1_000_000 && $0 < 2_000_000 }, "B did not play")

        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, b, "after C comes B")
        await rig.manager.stop()

        // Relaunch: a new queue over the same library folder.
        let relaunched = queue([a, b, c])
        XCTAssertEqual(relaunched.items, [a, c, b])
        XCTAssertEqual(relaunched.currentID, b.id)
        XCTAssertEqual(relaunched.item(after: a.id), c)
        XCTAssertEqual(relaunched.startItem, b)
    }

    // MARK: - Repetition follows the edit at once (AUD-003-R8)

    func testALoneLoopingTrackPlaysToItsEndOnceWhenASecondIsQueuedWithoutACut() async throws {
        let a = try track(1, offset: 0)
        let b = try track(2, offset: 1_000_000)
        let order = queue([a, b])
        order.remove(b.id)
        let rig = await playing(order, current: a)
        var stream = try await pump(rig, renders: 8)
        let before = rig.transport.position.seconds
        order.addToEnd(b.id)
        XCTAssertEqual(rig.transport.position.seconds, before, accuracy: 0.5 / 44_100, "the position is kept")
        XCTAssertEqual(rig.transport.state, .playing)

        stream += try await pump(rig, renders: 30)
        XCTAssertEqual(rig.transport.current, b)
        let (old, new) = try split(stream, at: 1_000_000)
        XCTAssertEqual(old.first, 0)
        XCTAssertEqual(old.last, Self.trackFrames - 1)
        XCTAssertTrue(CounterDecoder.isConsecutive(old), "A once, from 0 to its end, nothing cut or repeated")
        XCTAssertEqual(new.first, 1_000_000)
        XCTAssertTrue(CounterDecoder.isConsecutive(new))
        await rig.manager.stop()
    }

    func testATrackLeftAloneRepeatsWithoutAGap() async throws {
        let a = try track(1, offset: 0)
        let b = try track(2, offset: 1_000_000)
        let order = queue([a, b])
        let rig = await playing(order, current: a)
        var stream = try await pump(rig, renders: 8)
        let before = rig.transport.position.seconds
        order.remove(b.id)
        XCTAssertEqual(rig.transport.position.seconds, before, accuracy: 0.5 / 44_100)

        stream += try await pump(rig, renders: 30)
        XCTAssertEqual(rig.transport.current, a)
        XCTAssertFalse(stream.contains { $0 >= 1_000_000 }, "B was removed and never played")
        XCTAssertEqual(stream.first, 0)
        XCTAssertGreaterThan(stream.count, Self.trackFrames + 4096, "it went past the end and wrapped")
        for (previous, next) in zip(stream, stream.dropFirst()) where next != (previous + 1) % Self.trackFrames {
            XCTFail("gap at \(previous) → \(next)")
            break
        }
        await rig.manager.stop()
    }
}
#endif
