// MED-002-T12: the import checks and the sanitized copy (MED-002-R4, R5, R16, S5, S7). Fixtures are
// generated into a temporary folder; nothing is checked in.
#if canImport(AVFoundation)
import AVFoundation
import CameraLayer
import VideoLayer
import XCTest

final class VideoImportTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED002-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixture(_ name: String, _ options: VideoFixtures.Options = .init()) async throws -> URL {
        let url = directory.appendingPathComponent(name)
        try await VideoFixtures.write(to: url, options)
        return url
    }

    private func refusal(_ url: URL, limits: VideoImportLimits = .standard) async -> VideoImportError? {
        do {
            _ = try await VideoProbe.check(url, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    func testProbeReadsTheTrackFacts() async throws {
        let info = try await VideoProbe.check(try await fixture("plain.mov"), limits: .standard)
        XCTAssertEqual(info.width, 64)
        XCTAssertEqual(info.height, 48)
        XCTAssertEqual(info.rotation, .none)
        XCTAssertEqual(info.codec, .h264)
        XCTAssertEqual(info.frameRate, 30, accuracy: 0.5)
        XCTAssertEqual(Double(info.durationNanoseconds) / 1e9, 2, accuracy: 0.04)
        let rotated = try await VideoProbe.check(try await fixture("rotated.mov", .init(rotated: true)), limits: .standard)
        XCTAssertEqual(rotated.rotation, .clockwise90, "a portrait phone video is turned upright")
        XCTAssertEqual(rotated.uprightWidth, 48)
    }

    func testRefusalsAreTyped() async throws {
        let notVideo = directory.appendingPathComponent("noise.mov")
        try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }).write(to: notVideo)
        let noiseRefusal = await refusal(notVideo)
        XCTAssertEqual(noiseRefusal, .notAVideo)

        let plain = try await fixture("plain.mov")
        let data = try Data(contentsOf: plain)
        let truncated = directory.appendingPathComponent("truncated.mov")
        try data.prefix(data.count / 2).write(to: truncated)
        let truncatedRefusal = await refusal(truncated)
        // MED-014-R8: the container check sees the cut (mdat runs past the end) before AVFoundation does.
        XCTAssertEqual(truncatedRefusal, .damaged, "a movie cut short is damaged (MED-014; MED-002 read it as .notAVideo)")
        // Pictures overwritten, index intact: the track is there, its pictures do not decode.
        var scrambled = data
        let picturesStart = scrambled.range(of: Data("mdat".utf8))!.upperBound
        for i in picturesStart..<min(picturesStart + 6000, scrambled.count / 2) { scrambled[i] = UInt8(truncatingIfNeeded: i &* 131) }
        let damaged = directory.appendingPathComponent("damaged.mov")
        try scrambled.write(to: damaged)
        let damagedRefusal = await refusal(damaged)
        XCTAssertEqual(damagedRefusal, .damaged)

        let tooLargeRefusal = await refusal(plain, limits: VideoImportLimits(maxFileBytes: 1000, maxLongestSide: 4096, maxFrameRate: 60.5))
        XCTAssertEqual(tooLargeRefusal, .tooLarge)
        let pictureRefusal = await refusal(plain, limits: VideoImportLimits(maxFileBytes: 1 << 30, maxLongestSide: 32, maxFrameRate: 60.5))
        XCTAssertEqual(pictureRefusal, .pictureTooLarge)
        let fast = try await fixture("fast.mov", .init(frames: 24, fps: 120))
        let fastRefusal = await refusal(fast)
        XCTAssertEqual(fastRefusal, .frameRateTooHigh, "120 fps is refused")
        let missing = await refusal(directory.appendingPathComponent("missing.mov"))
        XCTAssertEqual(missing, .unreadable)
    }

    /// S5: the copy has the pictures only: no soundtrack, no metadata, none of the original's strings.
    func testSanitizedCopyDropsSoundtrackAndMetadataAndKeepsRotation() async throws {
        let original = try await fixture("tagged.mov", .init(audio: true, metadata: true, rotated: true))
        let originalBytes = try Data(contentsOf: original)
        let originalAudio = try await AVURLAsset(url: original).loadTracks(withMediaType: .audio)
        XCTAssertEqual(originalAudio.count, 1, "fixture sanity: it has a soundtrack")
        for marker in [VideoFixtures.location, VideoFixtures.creationDate, VideoFixtures.device] {
            XCTAssertNotNil(originalBytes.range(of: Data(marker.utf8)), "fixture sanity: \(marker) is in the original")
        }

        let copy = directory.appendingPathComponent("copy.mov")
        let info = try await VideoSanitizer.copy(original, to: copy, limits: .standard)
        XCTAssertEqual(info.rotation, .clockwise90)
        XCTAssertEqual(info.width, 64)
        XCTAssertEqual(info.frameRate, 30, accuracy: 0.5)
        let asset = AVURLAsset(url: copy)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty, "the soundtrack is not stored (R16)")
        let metadata = try await asset.load(.metadata)
        XCTAssertTrue(metadata.isEmpty, "no asset metadata: \(metadata.map { $0.identifier?.rawValue ?? "?" })")
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let trackMetadata = try await tracks[0].load(.metadata)
        XCTAssertTrue(trackMetadata.isEmpty, "no track metadata")
        let copyBytes = try Data(contentsOf: copy)
        for marker in [VideoFixtures.location, VideoFixtures.creationDate, VideoFixtures.device] {
            XCTAssertNil(copyBytes.range(of: Data(marker.utf8)), "\(marker) is not in the stored bytes")
        }
        XCTAssertLessThan(copyBytes.count, originalBytes.count, "the pictures were copied, not re-encoded larger")
    }

    func testSanitizerRefusesWithTheProbeReasonAndLeavesNoFile() async throws {
        let notVideo = directory.appendingPathComponent("noise.mov")
        try Data(repeating: 7, count: 2048).write(to: notVideo)
        let copy = directory.appendingPathComponent("copy.mov")
        do {
            _ = try await VideoSanitizer.copy(notVideo, to: copy, limits: .standard)
            XCTFail("refused")
        } catch {
            XCTAssertEqual(error, .notAVideo)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }
}
#endif
