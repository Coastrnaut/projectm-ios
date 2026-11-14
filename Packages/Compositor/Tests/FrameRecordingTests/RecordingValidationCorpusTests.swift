// RecordingValidationCorpusTests.swift — QA-008-T05 (QA-008-S1, R11, R14): generated good and deliberately
// bad recordings, validated from the file. Every good file passes; every bad file fails with exactly its
// reason code. No GPU (CPU-filled frames), so CI's macOS host package step runs it on every push, before
// any device testing. Fixtures live in the temporary folder and are deleted after each test.
#if canImport(AVFoundation)
import AVFoundation
@testable import FrameRecording
import Foundation
import XCTest

final class RecordingValidationCorpusTests: XCTestCase {
    private typealias Fixture = RecordingFixtureWriter

    private func url(_ name: String, ext: String = "mp4") -> URL {
        let url = Fixture.temporaryURL(name, ext: ext)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func check(_ file: URL, _ expectation: RecordingExpectation, expect codes: Set<RecordingIssue.Code>,
                       line: UInt = #line) async -> RecordingValidationReport {
        let report = await RecordingValidator.validate(file, expectation: expectation)
        XCTAssertEqual(report.codes, codes, report.summary, line: line)
        return report
    }

    /// One second at 30 fps, video only.
    private func goodVideo(_ name: String) async throws -> URL {
        try await Fixture.writeWithRecorderWriter(.regular(frames: 30), url: url(name))
    }

    /// 1.5 s at 30 fps with audio; the flash at frame 30 (1.0 s), the click at 1.0 s + `clickOffset`.
    private func avFixture(_ name: String, clickOffset: Double = 0, audio: Bool = true) async throws -> URL {
        var spec = Fixture.Spec.regular(frames: 45)
        spec.flashFrame = 30
        spec.audio = audio
        spec.clickSeconds = 1.0 + clickOffset
        return try await Fixture.writeWithRecorderWriter(spec, url: url(name))
    }

    private let videoOnly = RecordingExpectation(durationSeconds: 1.0)
    private let withMarker = RecordingExpectation(durationSeconds: 1.5, expectsAudio: true, checksSyncMarker: true, markerSeconds: 1.0)

    // MARK: - Good

    func testGoodVideoOnlyRecordingPasses() async throws {
        let report = await check(try await goodVideo("good-video"), videoOnly, expect: [])
        let m = try XCTUnwrap(report.measurement)
        XCTAssertEqual(m.frameCount, 30)
        XCTAssertEqual(m.presentationTicks, (0..<30).map { (k: Int) -> Int64 in Int64(k) * 20 })
        XCTAssertEqual([m.width, m.height], [160, 120])
        XCTAssertTrue(RecordingExpectation.recorderCodecs.contains(m.codec))
    }

    func testGoodRecordingWithOwnedAudioAndMarkerPasses() async throws {
        let report = await check(try await avFixture("good-av"), withMarker, expect: [])
        let m = try XCTUnwrap(report.measurement)
        XCTAssertEqual(m.audioSampleRate, 44_100)
        XCTAssertEqual(m.audioChannels, 2)
        XCTAssertGreaterThan(m.audioSampleCount, 44_100)
        XCTAssertEqual(try XCTUnwrap(m.flashSeconds), 1.0, accuracy: 0.001)
    }

    // MARK: - Bad: timestamps, duration, frame count

    func testTimestampGapFails() async throws {
        var spec = Fixture.Spec.regular(frames: 30)
        spec.ticks.removeAll { (t: Int64) -> Bool in (200...240).contains(t) }   // frames 10-12 missing: a 80-tick step
        _ = await check(try await Fixture.writeWithRecorderWriter(spec, url: url("gap")), videoOnly, expect: [.timestampGap])
    }

    func testDuplicateTimestampFails() async throws {
        // Timescale 90,000: frame 15 is 1/90,000 s after frame 14, the same 1/600 s tick (research QA-008-D3).
        var times = (0..<30).map { (k: Int) -> CMTime in CMTime(value: Int64(k) * 3_000, timescale: 90_000) }
        times.insert(CMTime(value: 14 * 3_000 + 1, timescale: 90_000), at: 15)
        let raw = Fixture.RawSpec(times: times, end: CMTime(value: 90_000, timescale: 90_000))
        _ = await check(try await Fixture.writeRaw(raw, url: url("duplicate")), videoOnly, expect: [.duplicateTimestamp])
    }

    func testTooLongDurationFails() async throws {
        var spec = Fixture.Spec.regular(frames: 30)
        spec.endTick = 1_200   // 30 frames in a 2 s file
        let file = try await Fixture.writeWithRecorderWriter(spec, url: url("long"))
        _ = await check(file, RecordingExpectation(), expect: [.durationMismatch])
    }

    func testTooShortRecordingFails() async throws {
        _ = await check(try await goodVideo("short"), RecordingExpectation(durationSeconds: 2.0), expect: [.durationMismatch])
    }

    func testTruncatedFileIsUnreadable() async throws {
        let good = try await goodVideo("truncate-source")
        let data = try Data(contentsOf: good)
        let cut = url("truncated")
        try data.prefix(data.count * 6 / 10).write(to: cut)
        _ = await check(cut, videoOnly, expect: [.unreadable])
    }

    func testWrongFrameRateFails() async throws {
        // 24 frames at 24 fps in 1 s, checked against 30 fps: times and duration are consistent, the count is not.
        let file = try await Fixture.writeWithRecorderWriter(.regular(frames: 24, fps: 24), url: url("24fps"))
        _ = await check(file, videoOnly, expect: [.frameCountMismatch])
        _ = await check(file, RecordingExpectation(frameRate: 24, durationSeconds: 1.0), expect: [])
    }

    // MARK: - Bad: audio

    func testAudio80MillisecondsLateFails() async throws {
        let report = await check(try await avFixture("late", clickOffset: 0.080), withMarker, expect: [.syncOutOfTolerance])
        let m = try XCTUnwrap(report.measurement)
        let offset = try XCTUnwrap(m.clickSeconds) - XCTUnwrap(m.flashSeconds)
        XCTAssertEqual(offset, 0.080, accuracy: 0.010)
    }

    func testMissingAudioFails() async throws {
        _ = await check(try await avFixture("no-audio", audio: false), withMarker, expect: [.audioMissing])
    }

    func testUnexpectedAudioFails() async throws {
        _ = await check(try await avFixture("extra-audio"), RecordingExpectation(durationSeconds: 1.5), expect: [.audioUnexpected])
    }

    // MARK: - Bad: codec and metadata

    func testWrongCodecFails() async throws {
        let times = (0..<30).map { (k: Int) -> CMTime in CMTime(value: Int64(k) * 20, timescale: 600) }
        let raw = Fixture.RawSpec(codec: .jpeg, times: times, end: CMTime(value: 600, timescale: 600))
        let report = await check(try await Fixture.writeRaw(raw, url: url("jpeg")), videoOnly, expect: [.codecNotAllowed])
        XCTAssertEqual(report.measurement?.codec, "jpeg")
    }

    func testLocationMetadataFails() async throws {
        let times = (0..<30).map { (k: Int) -> CMTime in CMTime(value: Int64(k) * 20, timescale: 600) }
        let raw = Fixture.RawSpec(times: times, end: CMTime(value: 600, timescale: 600), metadata: [Fixture.locationItem()])
        _ = await check(try await Fixture.writeRaw(raw, url: url("location")), videoOnly, expect: [.personalMetadata])
    }

    // MARK: - QA-008-R14: a device export, on demand

    /// `QA008_RECORDING=<path> swift test --package-path Packages/Compositor --filter testExternalRecording`
    /// (optional `QA008_EXPECT_AUDIO=1`, `QA008_FPS=<n>`, `QA008_MARKER_SECONDS=<s>`). Skipped without the path.
    func testExternalRecording() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["QA008_RECORDING"], !path.isEmpty else {
            throw XCTSkip("Set QA008_RECORDING=<path> to validate an exported recording (quickstart C).")
        }
        var expectation = RecordingExpectation(frameRate: Int(env["QA008_FPS"] ?? "") ?? 30,
                                               expectsAudio: env["QA008_EXPECT_AUDIO"] == "1")
        if let marker = Double(env["QA008_MARKER_SECONDS"] ?? "") {
            expectation.checksSyncMarker = true
            expectation.markerSeconds = marker
        }
        let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let report = await RecordingValidator.validate(file, expectation: expectation)
        print("QA-008 \(file.lastPathComponent): \(report.summary)")
        XCTAssertTrue(report.passed, report.summary)
    }
}
#endif
