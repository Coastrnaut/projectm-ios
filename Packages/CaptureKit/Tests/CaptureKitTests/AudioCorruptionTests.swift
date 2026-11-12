// AudioCorruptionTests.swift — files that cannot be used: each refusal reason, corruption sweeps
// over every container, and recovery afterwards (AUD-002-T07, T08, T15; AUD-002-S3, S4, S6).
//
// Imported files are untrusted input. Every case must end in an outcome (XCTest's time allowance
// catches a hang), a refusal must leave the library byte-for-byte unchanged, and whatever is
// accepted must go through the playback graph without an error.
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class AudioCorruptionTests: XCTestCase {
    private var root: URL!
    private var sources: URL!
    private var libraryURL: URL!
    private var library: AudioLibrary!

    override func setUp() async throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud002-corrupt")
        sources = root.appendingPathComponent("picked", isDirectory: true)
        libraryURL = root.appendingPathComponent("AudioLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        library = AudioLibrary(directory: libraryURL)
        await library.load()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    private func source(_ name: String) -> URL { sources.appendingPathComponent(name) }

    private func tone(_ name: String, _ container: AudioFixtures.Container, seconds: Double = 0.5, rate: Double = 44_100,
                      channels: Int = 2, frequency: Double = 440) throws -> URL {
        try AudioFixtures.writeTone(to: source(name), seconds: seconds, sampleRate: rate, channels: channels, frequency: frequency,
                                    container: container)
    }

    private func text(_ name: String) throws -> URL {
        let url = source(name)
        try Data("These are notes about a song, not the song itself.\n".utf8).write(to: url)
        return url
    }

    /// One valid file per format, keyed by its extension.
    private func oneOfEach() throws -> [(String, URL)] {
        [("mp3", try MP3Fixture.write(to: source("good.mp3"), sampleRate: 44_100, lines: [10, 16], frameCount: 40)),
         ("aac", try tone("good.aac", .aac)),
         ("m4a", try tone("good.m4a", .aac)),
         ("wav", try tone("good.wav", .wav16)),
         ("aiff", try tone("good.aiff", .aiff16))]
    }

    private struct Snapshot: Equatable {
        var tree: [String]
        var index: Data?
        var tracks: [ImportedTrack]
    }

    private func snapshot() async -> Snapshot {
        Snapshot(tree: AudioFixtures.tree(libraryURL), index: try? Data(contentsOf: libraryURL.appendingPathComponent("index.json")),
                 tracks: await library.tracks)
    }

    /// Imports `url`, expecting `error`, and checks that the library is exactly what it was.
    private func assertRefused(_ url: URL, _ error: AudioImportError, file: StaticString = #filePath, line: UInt = #line) async {
        let before = await snapshot()
        let outcome = await library.importFile(at: url)
        XCTAssertEqual(outcome, .failed(fileName: url.lastPathComponent, error), file: file, line: line)
        let after = await snapshot()
        XCTAssertEqual(after, before, "\(url.lastPathComponent): a refusal must leave nothing behind", file: file, line: line)
    }

    private func imported(_ url: URL, file: StaticString = #filePath, line: UInt = #line) async throws -> ImportedTrack {
        let outcome = await library.importFile(at: url)
        guard case .imported(let track) = outcome else {
            XCTFail("\(url.lastPathComponent): expected imported, got \(outcome)", file: file, line: line)
            throw CocoaError(.featureUnsupported)
        }
        return track
    }

    private func storedURL(_ track: ImportedTrack) async throws -> URL {
        let url = await library.fileURL(for: track.id)
        return try XCTUnwrap(url)
    }

    // MARK: Each reason has its own error (AUD-002-R7)

    func testContentThatIsNotAudioIsAnUnsupportedFormat() async throws {
        for name in ["notes.wav", "notes.mp3", "notes.m4a", "notes.aac", "notes.aiff"] {
            await assertRefused(try text(name), .unsupportedFormat)
        }
        await assertRefused(try AudioFixtures.writeGarbage(to: source("garbage.aiff")), .unsupportedFormat)
        await assertRefused(try AudioFixtures.writeGarbage(to: source("garbage.mp3"), byteCount: 100_000), .unsupportedFormat)
    }

    func testUndecodableEncodingInAKnownContainer() async throws {
        // A WAV whose format tag names no codec.
        await assertRefused(try AudioFixtures.writeWAV(to: source("exotic.wav"), formatTag: 0x7A21), .unsupportedEncoding)
        // The same file under another audio extension: still recognized as WAV, same answer.
        await assertRefused(try AudioFixtures.writeWAV(to: source("exotic.m4a"), formatTag: 0x7A21), .unsupportedEncoding)
    }

    func testSampleRatesThePlayerCannotTakeAreRefused() async throws {
        await assertRefused(try AudioFixtures.writeWAV(to: source("4GHz.wav"), sampleRate: 4_000_000_000), .unsupportedEncoding)
        await assertRefused(try AudioFixtures.writeWAV(to: source("100Hz.wav"), sampleRate: 100), .unsupportedEncoding)
        await assertRefused(try AudioFixtures.writeWAV(to: source("7999Hz.wav"), sampleRate: 7_999), .unsupportedEncoding)
        await assertRefused(try AudioFixtures.writeWAV(to: source("192001Hz.wav"), sampleRate: 192_001), .unsupportedEncoding)
        await assertRefused(try AudioFixtures.writeWAV(to: source("0Hz.wav"), sampleRate: 0), .unsupportedEncoding)
    }

    func testDamagedOrTruncatedFilesAreUnreadable() async throws {
        let m4a = try tone("whole.m4a", .aac)
        let aiff = try tone("whole.aiff", .aiff16)
        let lossless = try tone("whole-lossless.m4a", .appleLossless)
        await assertRefused(try AudioFixtures.truncated(m4a, to: source("cut50.m4a"), fraction: 0.5), .unreadable)
        await assertRefused(try AudioFixtures.truncated(m4a, to: source("cut02.m4a"), fraction: 0.02), .unreadable)
        await assertRefused(try AudioFixtures.truncated(aiff, to: source("cut50.aiff"), fraction: 0.5), .unreadable)
        await assertRefused(try AudioFixtures.truncated(aiff, to: source("cut90.aiff"), fraction: 0.9), .unreadable)
        await assertRefused(try AudioFixtures.truncated(lossless, to: source("cut90-lossless.m4a"), fraction: 0.9), .unreadable)
        // A WAV cut inside its format chunk (30 bytes): recognized, but nothing can be decoded.
        let wav = try tone("whole.wav", .wav16)
        try Data(contentsOf: wav).prefix(30).write(to: source("cut-header.wav"))
        await assertRefused(source("cut-header.wav"), .unreadable)
        // Under a wrong name the answer is the same: the content is recognized first.
        await assertRefused(try AudioFixtures.truncated(aiff, to: source("cut50-aiff.mp3"), fraction: 0.5), .unreadable)
    }

    func testFilesWithoutAudio() async throws {
        let empty = source("empty.wav")
        try Data().write(to: empty)
        await assertRefused(empty, .noAudio)
        await assertRefused(try AudioFixtures.writeWAV(to: source("header-only.wav"), frames: 0), .noAudio)
        let aiff = try tone("whole.aiff", .aiff16)
        // Cut inside the header area, before any sample: the decoder finds no frames to read.
        let outcome = await library.importFile(at: try AudioFixtures.truncated(aiff, to: source("cut-header.wav"), fraction: 0.0005))
        guard case .failed = outcome else { return XCTFail("a 0.05% stub must not import: \(outcome)") }
    }

    func testUnopenableAndUnchangedAUD001Reasons() async throws {
        await assertRefused(source("missing.wav"), .sourceUnavailable)
        await assertRefused(try AudioFixtures.writeRawWAV(to: source("quad.wav"), channels: 4), .unsupportedChannelCount(4))
        await assertRefused(try text("notes.txt"), .notAudio)
    }

    func testTruncatedFilesTheDecoderStillReadsImportWithTheShorterDuration() async throws {
        let cases: [(URL, String)] = [
            (try tone("whole.wav", .wav16, seconds: 1), "cut.wav"),
            (try MP3Fixture.write(to: source("whole.mp3"), frameCount: 40), "cut.mp3"),
            (try tone("whole.aac", .aac, seconds: 1), "cut.aac"),
        ]
        for (whole, name) in cases {
            let full = try await AVAudioFileInspector().inspect(whole).durationSeconds
            let track = try await imported(try AudioFixtures.truncated(whole, to: source(name), fraction: 0.5))
            XCTAssertLessThan(track.durationSeconds, full * 0.7, name)
            XCTAssertGreaterThan(track.durationSeconds, full * 0.3, name)
            let capture = try await PlaybackProbe.play(try await storedURL(track), seconds: 0.2)
            XCTAssertGreaterThan(capture.peak(capture.left), 0.2, name)
        }
    }

    func testAbsurdHeaderClaimsNeedNoLargeAllocation() async throws {
        // The data chunk claims 2 GiB; the file holds 0.1 s. The decoder reports what is there.
        let track = try await imported(try AudioFixtures.writeWAV(to: source("claims-2GiB.wav"), claimedDataBytes: 0x7FFF_FFF0))
        XCTAssertEqual(track.durationSeconds, 0.1, accuracy: 0.01)
        // Validation decodes two small windows whatever the file claims.
        XCTAssertEqual(AVAudioFileInspector.probeFrames, 4096)
        XCTAssertEqual(AVAudioFileInspector.tailFrames, 2048)
    }

    func testMixedSelectionReportsEachFileInOrder() async throws {
        let good = try tone("good.m4a", .aac)
        let cut = try AudioFixtures.truncated(try tone("whole.aiff", .aiff16), to: source("cut.aiff"), fraction: 0.5)
        let outcomes = await library.importFiles(at: [try text("notes.wav"), good, cut, source("missing.mp3"),
                                                      try AudioFixtures.writeWAV(to: source("exotic.wav"), formatTag: 0x7A21)])
        XCTAssertEqual(outcomes.count, 5)
        XCTAssertEqual(outcomes[0], .failed(fileName: "notes.wav", .unsupportedFormat))
        guard case .imported(let track) = outcomes[1] else { return XCTFail("\(outcomes[1])") }
        XCTAssertEqual(outcomes[2], .failed(fileName: "cut.aiff", .unreadable))
        XCTAssertEqual(outcomes[3], .failed(fileName: "missing.mp3", .sourceUnavailable))
        XCTAssertEqual(outcomes[4], .failed(fileName: "exotic.wav", .unsupportedEncoding))
        let listed = await library.tracks
        XCTAssertEqual(listed, [track])
        XCTAssertEqual(AudioFixtures.tree(libraryURL), ["assets/\(track.fileName)", "index.json"])
    }

    // MARK: Sweep: every container, cut and overwritten (AUD-002-S3)

    func testCorruptionSweepNeverCrashesAndAlwaysRecovers() async throws {
        var refused = 0
        var accepted = 0
        for (ext, good) in try oneOfEach() {
            var variants: [URL] = []
            for (index, fraction) in [0.01, 0.10, 0.35, 0.60, 0.85, 0.99].enumerated() {
                variants.append(try AudioFixtures.truncated(good, to: source("cut\(index).\(ext)"), fraction: fraction))
            }
            for (index, fraction) in [0.05, 0.25, 0.50, 0.75, 0.95].enumerated() {
                variants.append(try AudioFixtures.overwritten(good, to: source("noise\(index).\(ext)"), offsetFraction: fraction,
                                                              seed: UInt32(1 + index)))
            }
            variants.append(try AudioFixtures.overwritten(good, to: source("head.\(ext)"), offsetFraction: 0, count: 16, seed: 99))
            for variant in variants {
                let before = await snapshot()
                switch await library.importFile(at: variant) {
                case .failed(_, let error):
                    refused += 1
                    XCTAssertTrue([.unsupportedFormat, .unsupportedEncoding, .unreadable, .noAudio, .unsupportedChannelCount(0)]
                        .contains { Self.sameKind($0, error) }, "\(variant.lastPathComponent): unexpected reason \(error)")
                    let after = await snapshot()
                    XCTAssertEqual(after.tree, before.tree, "\(variant.lastPathComponent): a refusal must leave nothing behind"); XCTAssertEqual(after.index, before.index, variant.lastPathComponent); XCTAssertEqual(after.tracks.map(\.id), before.tracks.map(\.id), "\(variant.lastPathComponent) \(error)")
                case .imported(let track):
                    accepted += 1
                    // Whatever was accepted starts and renders without an error.
                    // (A stub may decode to silence, so the wait for audio is kept short.)
                    let capture = try await PlaybackProbe.play(try await storedURL(track), seconds: 0.1, budgetSeconds: 0.5)
                    XCTAssertFalse(capture.left.isEmpty, variant.lastPathComponent)
                case .duplicate:
                    accepted += 1                          // an overwrite that changed nothing
                }
            }
        }
        XCTAssertGreaterThan(refused, 10, "the sweep must exercise refusals")
        XCTAssertGreaterThan(accepted, 10, "and files the decoder tolerates")
        // The same library is fully usable afterwards.
        let track = try await imported(try tone("after.wav", .wav16, frequency: 523))
        let capture = try await PlaybackProbe.play(try await storedURL(track))
        XCTAssertEqual(capture.frequency(capture.left, seconds: 0.3), 523, accuracy: 523 * 0.03)
        let reopened = AudioLibrary(directory: libraryURL)
        let state = await reopened.load()
        XCTAssertEqual(state, .ready)
        let reopenedTracks = await reopened.tracks
        let tracks = await library.tracks
        XCTAssertEqual(reopenedTracks.map(\.id), tracks.map(\.id))   // dates are stored to the second
        XCTAssertEqual(AudioFixtures.tree(libraryURL).filter { $0.hasPrefix("incoming/") }, [])
    }

    private static func sameKind(_ a: AudioImportError, _ b: AudioImportError) -> Bool {
        switch (a, b) {
        case (.unsupportedChannelCount, .unsupportedChannelCount): return true
        default: return a == b
        }
    }

    func testRunningPlaybackIsNotDisturbedByARefusedImport() async throws {
        let playing = try await imported(try tone("playing.wav", .wav16, seconds: 1))
        let graph = InAppPlaybackGraph(content: try InAppPlaybackGraph.load(.file(try await storedURL(playing)), bundle: .main))
        try graph.enableOfflineRendering(sampleRate: 48_000, maximumFrameCount: 1024)
        let sink = PCMSink()
        try graph.installTap(into: sink)
        try graph.start()
        defer { graph.stop() }
        let first = try await PlaybackProbe.capture(graph, sink: sink, outputRate: 48_000, seconds: 0.1)
        XCTAssertGreaterThan(first.peak(first.left), 0.2)
        await assertRefused(try text("notes.mp3"), .unsupportedFormat)
        await assertRefused(try AudioFixtures.truncated(try tone("whole.m4a", .aac), to: source("cut.m4a"), fraction: 0.5), .unreadable)
        XCTAssertTrue(graph.isRunning)
        let second = try await PlaybackProbe.capture(graph, sink: sink, outputRate: 48_000, seconds: 0.1)
        XCTAssertGreaterThan(second.peak(second.left), 0.2, "the track keeps playing")
        XCTAssertEqual(second.frequency(second.left, seconds: 0.1), 440, accuracy: 440 * 0.05)
    }

    // MARK: A stored copy that goes bad later (AUD-002-R12)

    func testStoredCopyDamagedAfterImportFailsToStartAndOthersStillPlay() async throws {
        let m4a = try tone("song.m4a", .aac)
        let bad = try await imported(m4a)
        let good = try await imported(try tone("other.wav", .wav16, frequency: 587))
        let badURL = try await storedURL(bad)
        // A partial restore: the stored copy is now only its first half. It still opens.
        let half = try Data(contentsOf: m4a)
        try half.prefix(half.count / 2).write(to: badURL)
        XCTAssertNoThrow(try AVAudioFile(forReading: badURL), "the header still opens; only decoding shows the damage")
        XCTAssertThrowsError(try InAppPlaybackGraph.load(.file(badURL), bundle: .main))
        // Replaced by something that is not audio at all.
        try Data("not audio any more".utf8).write(to: badURL)
        XCTAssertThrowsError(try InAppPlaybackGraph.load(.file(badURL), bundle: .main))
        // A sample rate the engine cannot take, swapped in behind the library's back.
        try AudioFixtures.writeWAV(to: try await storedURL(good).deletingLastPathComponent().appendingPathComponent("swapped.wav"),
                                   sampleRate: 4_000_000_000)
        XCTAssertThrowsError(try InAppPlaybackGraph.load(
            .file(libraryURL.appendingPathComponent("assets/swapped.wav")), bundle: .main))
        // The library still lists both tracks, and the intact one plays.
        let listed = await library.tracks
        XCTAssertEqual(listed.map(\.id), [bad.id, good.id])
        let capture = try await PlaybackProbe.play(try await storedURL(good))
        XCTAssertEqual(capture.frequency(capture.left, seconds: 0.3), 587, accuracy: 587 * 0.03)
    }

    func testLoadLeavesTheTrackAtItsStart() async throws {
        let track = try await imported(try tone("short.wav", .wav16, seconds: 0.05))   // 2,205 frames: shorter than the decode check
        let content = try InAppPlaybackGraph.load(.file(try await storedURL(track)), bundle: .main)
        guard case .file(let first, let second) = content else { return XCTFail("a library track streams from its file") }
        XCTAssertEqual(first.framePosition, 0)
        XCTAssertEqual(second.framePosition, 0)
        XCTAssertEqual(first.length, 2205)
    }
}
#endif
