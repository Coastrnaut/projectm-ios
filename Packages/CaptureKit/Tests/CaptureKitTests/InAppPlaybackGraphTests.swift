// InAppPlaybackGraphTests.swift — the playback graph on generated fixtures, rendered offline with
// AVAudioEngine's manual rendering mode (AUD-001-T09, T20): no audio hardware, no session.
//
// What this exercises: opening a library file, the player → mixer connection, the mixer tap that
// writes to PCMSink (the production tap closure), and the streaming loop that reschedules the
// file. What it cannot: AVAudioSession, real-time rendering, routes and interruptions (device).
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class InAppPlaybackGraphTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud001-graph")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Renders offline until `wantedFrames` non-silent frames reached the sink, or the budget ends.
    /// Returns (non-silent frames seen by the sink, frames rendered, peak sample).
    private func render(_ graph: InAppPlaybackGraph, sink: PCMSink, wantedFrames: Int, budgetFrames: Int) async throws
        -> (audible: Int, rendered: Int, peak: Float) {
        var audible = 0
        var rendered = 0
        var peak: Float = 0
        var scratch = [Float](repeating: 0, count: 8192)
        while audible < wantedFrames && rendered < budgetFrames {
            rendered += try graph.renderOffline(frames: 1024)
            let channels = max(sink.currentChannelCount, 1)
            var gotAudio = false
            while true {
                let count = scratch.withUnsafeMutableBufferPointer { sink.ring.read(into: $0.baseAddress!, maxCount: $0.count) }
                if count == 0 { break }
                var frame = 0
                while frame < count / channels {
                    let sample = abs(scratch[frame * channels])
                    if sample > 0.01 { audible += 1; gotAudio = true }
                    peak = max(peak, sample)
                    frame += 1
                }
            }
            // The loop is rescheduled by a main-actor task; let it run between render calls.
            if gotAudio { await Task.yield() } else { try await Task.sleep(nanoseconds: 2_000_000) }
        }
        return (audible, rendered, peak)
    }

    func testImportedFileStreamsLoopsAndReachesTheSink() async throws {
        let url = try AudioFixtures.writeTone(to: root.appendingPathComponent("tone.wav"), seconds: 0.25)   // 11,025 frames
        let graph = InAppPlaybackGraph(content: try InAppPlaybackGraph.load(.file(url), bundle: .main))
        try graph.enableOfflineRendering(sampleRate: 44_100, maximumFrameCount: 1024)
        let sink = PCMSink()
        try graph.installTap(into: sink)
        try graph.start()
        defer { graph.stop() }
        // More than three passes of the track: the loop rescheduled the file at least three times.
        let result = try await render(graph, sink: sink, wantedFrames: 35_000, budgetFrames: 44_100 * 20)
        XCTAssertGreaterThanOrEqual(result.audible, 35_000, "rendered \(result.rendered) frames")
        XCTAssertEqual(result.peak, 0.5, accuracy: 0.05, "the tone's amplitude arrives unchanged")
        XCTAssertEqual(sink.statistics().format?.sampleRate, 44_100)
        XCTAssertEqual(sink.currentChannelCount, 2)
    }

    func testImportedLibraryTrackPlaysAfterRelaunchWithoutTheOriginal() async throws {
        // The roadmap acceptance, as far as the host allows: import, drop the original, open a new
        // library over the same folder, and play the stored copy.
        let picked = root.appendingPathComponent("picked", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        let source = try AudioFixtures.writeTone(to: picked.appendingPathComponent("Mine.caf"), seconds: 0.2, channels: 1,
                                                 container: .cafFloat)
        let folder = root.appendingPathComponent("AudioLibrary", isDirectory: true)
        guard case .imported(let track) = await AudioLibrary(directory: folder).importFile(at: source) else {
            return XCTFail("import failed")
        }
        try FileManager.default.removeItem(at: picked)

        let relaunched = AudioLibrary(directory: folder)
        await relaunched.load()
        let stored = await relaunched.fileURL(for: track.id)
        let url = try XCTUnwrap(stored)
        XCTAssertFalse(url.path.contains("picked"))
        let graph = InAppPlaybackGraph(content: try InAppPlaybackGraph.load(.file(url), bundle: .main))
        try graph.enableOfflineRendering(sampleRate: 48_000, maximumFrameCount: 1024)   // output rate differs from the file's
        let sink = PCMSink()
        try graph.installTap(into: sink)
        try graph.start()
        defer { graph.stop() }
        let result = try await render(graph, sink: sink, wantedFrames: 20_000, budgetFrames: 48_000 * 20)
        XCTAssertGreaterThanOrEqual(result.audible, 20_000)
        XCTAssertGreaterThan(result.peak, 0.3)
    }

    func testMissingOrUndecodableFileThrows() throws {
        XCTAssertThrowsError(try InAppPlaybackGraph.load(.file(root.appendingPathComponent("missing.wav")), bundle: .main))
        let garbage = try AudioFixtures.writeGarbage(to: root.appendingPathComponent("garbage.wav"))
        XCTAssertThrowsError(try InAppPlaybackGraph.load(.file(garbage), bundle: .main))
        // The reference track is not in the test bundle: it fails rather than playing something else.
        XCTAssertThrowsError(try InAppPlaybackGraph.load(.reference, bundle: Bundle(for: Self.self)))
    }

    func testStopIsIdempotentAndEndsTheLoop() async throws {
        let url = try AudioFixtures.writeTone(to: root.appendingPathComponent("tone.wav"), seconds: 0.05)
        let graph = InAppPlaybackGraph(content: try InAppPlaybackGraph.load(.file(url), bundle: .main))
        try graph.enableOfflineRendering(sampleRate: 44_100, maximumFrameCount: 1024)
        let sink = PCMSink()
        try graph.installTap(into: sink)
        try graph.start()
        _ = try await render(graph, sink: sink, wantedFrames: 4_000, budgetFrames: 44_100 * 10)
        let schedulesBeforeStop = graph.scheduleCount
        XCTAssertGreaterThan(schedulesBeforeStop, 2, "the file was rescheduled for the loop")
        graph.stop()
        graph.stop()
        try await Task.sleep(nanoseconds: 50_000_000)             // late completion callbacks, if any
        XCTAssertEqual(graph.scheduleCount, schedulesBeforeStop, "nothing is scheduled after stop")
        XCTAssertFalse(graph.isRunning)
    }

    func testReferenceContentLoops() async throws {
        // The reference track's path. Since AUD-006 it is streamed from its file like a library
        // track (seeking needs file segments; plan.md, Complexity Tracking); it still loops.
        let url = try AudioFixtures.writeTone(to: root.appendingPathComponent("reference.wav"), seconds: 0.1)
        let graph = InAppPlaybackGraph(content: try InAppPlaybackGraph.loadReference(url))
        XCTAssertTrue(graph.loops, "one track repeats unless a play order says otherwise")
        try graph.enableOfflineRendering(sampleRate: 44_100, maximumFrameCount: 1024)
        let sink = PCMSink()
        try graph.installTap(into: sink)
        try graph.start()
        defer { graph.stop() }
        let result = try await render(graph, sink: sink, wantedFrames: 20_000, budgetFrames: 44_100 * 10)
        XCTAssertGreaterThanOrEqual(result.audible, 20_000)
    }
}
#endif
