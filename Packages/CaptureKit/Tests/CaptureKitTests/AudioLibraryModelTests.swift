// AudioLibraryModelTests.swift — the library record and its rules (AUD-001-T03; data-model.md).
import Foundation
import XCTest
@testable import CaptureKit

final class AudioLibraryModelTests: XCTestCase {
    static let digest = String(repeating: "ab", count: 32)

    /// Version 1 golden record. Never edit: later versions must keep reading it (migrations).
    static let goldenV1 = """
    {"schemaVersion":1,"tracks":[{"byteCount":44144,"channelCount":2,"durationSeconds":0.25,\
    "fileName":"\(digest).wav","id":"11111111-2222-3333-4444-555555555555",\
    "importedAt":"2026-11-12T10:00:00Z","originalFileName":"Tone.wav","sampleRate":44100,\
    "sha256":"\(digest)","title":"Tone"}]}
    """

    static func track(title: String = "Tone", sha256: String = digest, fileName: String? = nil, byteCount: Int64 = 44_144,
                      duration: Double = 0.25, sampleRate: Double = 44_100, channels: Int = 2) -> ImportedTrack {
        ImportedTrack(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, title: title,
                      originalFileName: "Tone.wav", sha256: sha256, fileName: fileName ?? "\(sha256).wav",
                      byteCount: byteCount, durationSeconds: duration, sampleRate: sampleRate, channelCount: channels,
                      importedAt: Date(timeIntervalSince1970: 1_794_477_600))   // 2026-11-12T10:00:00Z
    }

    func testGoldenVersion1Decodes() throws {
        let decoded = try AudioLibraryIndex.decode(Data(Self.goldenV1.utf8))
        XCTAssertEqual(decoded, .index(AudioLibraryIndex(tracks: [Self.track()])))
    }

    func testEncodingIsVersionedSortedAndRoundTrips() throws {
        let index = AudioLibraryIndex(tracks: [Self.track()])
        let data = try index.encoded()
        XCTAssertEqual(String(decoding: data, as: UTF8.self), Self.goldenV1)   // sorted keys, ISO-8601 date
        XCTAssertEqual(try AudioLibraryIndex.decode(data), .index(index))
        XCTAssertEqual(AudioLibraryIndex.currentSchemaVersion, 1)
    }

    func testUnknownKeysAreIgnored() throws {
        let json = Self.goldenV1.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"queue\":[1,2]")
            .replacingOccurrences(of: "\"title\":\"Tone\"", with: "\"title\":\"Tone\",\"artist\":\"x\"")
        XCTAssertEqual(try AudioLibraryIndex.decode(Data(json.utf8)), .index(AudioLibraryIndex(tracks: [Self.track()])))
    }

    func testNewerSchemaVersionIsReportedNotDecoded() throws {
        // A newer record may have any shape; only the version is read.
        let json = #"{"schemaVersion":2,"tracks":"something else entirely"}"#
        XCTAssertEqual(try AudioLibraryIndex.decode(Data(json.utf8)), .newerFormat(2))
    }

    func testDamagedRecordThrows() {
        XCTAssertThrowsError(try AudioLibraryIndex.decode(Data("{\"schemaVersion\":1,\"tra".utf8)))
        XCTAssertThrowsError(try AudioLibraryIndex.decode(Data()))
        XCTAssertThrowsError(try AudioLibraryIndex.decode(Data(#"{"tracks":[]}"#.utf8)))          // no version
        XCTAssertThrowsError(try AudioLibraryIndex.decode(Data(#"{"schemaVersion":0,"tracks":[]}"#.utf8)))
    }

    func testInvalidEntriesAreDroppedOnDecode() throws {
        let bad = Self.goldenV1.replacingOccurrences(of: "\"channelCount\":2", with: "\"channelCount\":6")
        XCTAssertEqual(try AudioLibraryIndex.decode(Data(bad.utf8)), .index(AudioLibraryIndex(tracks: [])))
    }

    func testTrackValidationRules() {
        XCTAssertTrue(Self.track().isValid)
        XCTAssertFalse(Self.track(sha256: "abc").isValid)
        XCTAssertFalse(Self.track(sha256: String(repeating: "AB", count: 32)).isValid, "lowercase hex only")
        XCTAssertFalse(Self.track(sha256: String(repeating: "zz", count: 32)).isValid)
        XCTAssertFalse(Self.track(fileName: "../\(Self.digest).wav").isValid)
        XCTAssertFalse(Self.track(fileName: "sub/\(Self.digest).wav").isValid)
        XCTAssertFalse(Self.track(fileName: "other.wav").isValid, "the stored name starts with the hash")
        XCTAssertTrue(Self.track(fileName: Self.digest).isValid, "no extension is allowed")
        XCTAssertFalse(Self.track(byteCount: 0).isValid)
        XCTAssertTrue(Self.track(byteCount: 524_288_000).isValid)
        XCTAssertFalse(Self.track(byteCount: 524_288_001).isValid)
        XCTAssertFalse(Self.track(duration: 0).isValid)
        XCTAssertFalse(Self.track(duration: .nan).isValid)
        XCTAssertFalse(Self.track(sampleRate: 0).isValid)
        XCTAssertFalse(Self.track(channels: 0).isValid)
        XCTAssertFalse(Self.track(channels: 3).isValid)
        XCTAssertTrue(Self.track(channels: 1).isValid)
        XCTAssertFalse(Self.track(title: "").isValid)
    }

    func testTitleRule() {
        XCTAssertEqual(ImportedTrack.title(fromFileName: "My Song.mp3"), "My Song")
        XCTAssertEqual(ImportedTrack.title(fromFileName: "  spaced  .wav"), "spaced")
        XCTAssertEqual(ImportedTrack.title(fromFileName: ".wav"), "Untitled")
        XCTAssertEqual(ImportedTrack.title(fromFileName: ""), "Untitled")
        XCTAssertEqual(ImportedTrack.title(fromFileName: "a.b.c.m4a"), "a.b.c")
        XCTAssertEqual(ImportedTrack.title(fromFileName: String(repeating: "x", count: 300) + ".wav").count, 200)
    }

    func testStoredExtensionRule() {
        XCTAssertEqual(ImportedTrack.storedExtension(fromFileName: "Song.MP3"), "mp3")
        XCTAssertEqual(ImportedTrack.storedExtension(fromFileName: "Song"), "")
        XCTAssertEqual(ImportedTrack.storedExtension(fromFileName: "a.w/a v!"), "wav")
        XCTAssertEqual(ImportedTrack.storedExtension(fromFileName: "a.abcdefghijkl"), "abcdefgh")
        XCTAssertEqual(ImportedTrack.storedFileName(sha256: Self.digest, originalFileName: "Song.MP3"), "\(Self.digest).mp3")
        XCTAssertEqual(ImportedTrack.storedFileName(sha256: Self.digest, originalFileName: "Song"), Self.digest)
    }

    func testErrorsAndOutcomesAreValueTypes() {
        XCTAssertEqual(AudioImportError.tooLarge(limitBytes: 5), .tooLarge(limitBytes: 5))
        XCTAssertNotEqual(AudioImportError.unsupportedChannelCount(4), .unsupportedChannelCount(6))
        XCTAssertEqual(AudioImportOutcome.failed(fileName: "a", .notAudio), .failed(fileName: "a", .notAudio))
        XCTAssertEqual(AudioLibraryState.unavailable(.newerFormat), .unavailable(.newerFormat))
    }
}
