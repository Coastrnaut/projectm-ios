// AudioFormatMatrixTests.swift — the five formats through the real inspector, the real library and
// the production playback graph rendered offline (AUD-002-T05, T06, T13; AUD-002-S1, S2, S5).
//
// Every fixture is generated here at run time (AudioFixtures, MP3Fixture). Stereo fixtures carry a
// different tone left and right, so a swapped or summed channel shows up as a wrong frequency.
// What this cannot show: files from real-world encoders, the audio session, and devices.
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class AudioFormatMatrixTests: XCTestCase {
    private var root: URL!
    private var sources: URL!
    private var libraryURL: URL!
    private var library: AudioLibrary!

    nonisolated static let leftTone = 440.0
    nonisolated static let rightTone = 660.0
    nonisolated static let allRates: [Double] = [8_000, 11_025, 16_000, 22_050, 32_000, 44_100, 48_000, 96_000]
    nonisolated static let aacRates: [Double] = [8_000, 16_000, 22_050, 32_000, 44_100, 48_000]
    nonisolated static let mp3Rates = [32_000, 44_100, 48_000]
    nonisolated static let mp3Lines = [10, 16]

    override func setUp() async throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud002-matrix")
        sources = root.appendingPathComponent("picked", isDirectory: true)
        libraryURL = root.appendingPathComponent("AudioLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        library = AudioLibrary(directory: libraryURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    struct Expectation: Sendable {
        var container: AudioContainer?
        var sampleRate: Double
        var channels: Int
        var seconds: Double
        var durationTolerance = 0.06
        var left = AudioFormatMatrixTests.leftTone
        var right = AudioFormatMatrixTests.rightTone
        /// The extension the stored copy must carry.
        var storedExtension: String
    }

    private func tone(_ name: String, _ container: AudioFixtures.Container, rate: Double, channels: Int, seconds: Double = 0.5) throws -> URL {
        try AudioFixtures.writeTone(to: sources.appendingPathComponent(name), seconds: seconds, sampleRate: rate, channels: channels,
                                    frequency: Self.leftTone, rightFrequency: Self.rightTone, container: container)
    }

    private func mp3(_ name: String, rate: Int, channels: Int, id3Bytes: Int = 0) throws -> (URL, Expectation) {
        let lines = Array(Self.mp3Lines.prefix(channels))
        let url = try MP3Fixture.write(to: sources.appendingPathComponent(name), sampleRate: rate, lines: lines, frameCount: 40, id3Bytes: id3Bytes)
        let expectation = Expectation(container: .mp3, sampleRate: Double(rate), channels: channels,
                                      seconds: 40 * Double(MP3Fixture.samplesPerFrame) / Double(rate),
                                      left: MP3Fixture.frequency(line: lines[0], sampleRate: rate),
                                      right: MP3Fixture.frequency(line: lines[channels - 1], sampleRate: rate), storedExtension: "mp3")
        return (url, expectation)
    }

    /// Inspect → import → play the stored copy → (optionally) play it again from a reopened library.
    private func check(_ url: URL, _ expected: Expectation, outputRate: Double = 48_000, reopen: Bool = false,
                       file: StaticString = #filePath, line: UInt = #line) async throws {
        let name = url.lastPathComponent
        // The library, exactly as the app uses it.
        let outcome = await library.importFile(at: url)
        guard case .imported(let track) = outcome else {
            return XCTFail("\(name): expected imported, got \(outcome)", file: file, line: line)
        }
        XCTAssertEqual(track.sampleRate, expected.sampleRate, name, file: file, line: line)
        XCTAssertEqual(track.channelCount, expected.channels, name, file: file, line: line)
        XCTAssertEqual(track.durationSeconds, expected.seconds, accuracy: expected.durationTolerance, name, file: file, line: line)
        XCTAssertEqual(track.fileName, "\(track.sha256).\(expected.storedExtension)", name, file: file, line: line)
        XCTAssertEqual(track.originalFileName, name, file: file, line: line)
        let storedURL = await library.fileURL(for: track.id)
        let stored = try XCTUnwrap(storedURL, name, file: file, line: line)

        // The inspector on the stored copy (the name now matches the content).
        let info = try await AVAudioFileInspector().inspect(stored)
        XCTAssertEqual(info.container, expected.container, name, file: file, line: line)
        XCTAssertEqual(info.sampleRate, expected.sampleRate, name, file: file, line: line)
        XCTAssertEqual(info.channelCount, expected.channels, name, file: file, line: line)

        try await assertPlays(stored, expected, outputRate: outputRate, name: name, file: file, line: line)
        if reopen {
            let relaunched = AudioLibrary(directory: libraryURL)
            let state = await relaunched.load()
            XCTAssertEqual(state, .ready, file: file, line: line)
            let again = await relaunched.fileURL(for: track.id)
            try await assertPlays(try XCTUnwrap(again, name, file: file, line: line), expected, outputRate: outputRate,
                                  name: "\(name) after reopening", file: file, line: line)
        }
    }

    private func assertPlays(_ stored: URL, _ expected: Expectation, outputRate: Double, name: String,
                             file: StaticString = #filePath, line: UInt = #line) async throws {
        let seconds = min(0.3, expected.seconds * 0.6)
        let capture = try await PlaybackProbe.play(stored, outputRate: outputRate, seconds: seconds)
        let left = capture.audible(capture.left, seconds: seconds)
        let right = capture.audible(capture.right, seconds: seconds)
        XCTAssertGreaterThanOrEqual(left.count, Int(seconds * outputRate * 0.95), "\(name): left is silent or short", file: file, line: line)
        XCTAssertGreaterThanOrEqual(right.count, Int(seconds * outputRate * 0.95), "\(name): right is silent or short", file: file, line: line)
        XCTAssertGreaterThan(capture.peak(capture.left), 0.2, name, file: file, line: line)
        XCTAssertGreaterThan(capture.peak(capture.right), 0.2, name, file: file, line: line)
        let wantedRight = expected.channels == 1 ? expected.left : expected.right
        XCTAssertEqual(capture.frequency(capture.left, seconds: seconds), expected.left, accuracy: expected.left * 0.03,
                       "\(name): left pitch at \(outputRate) Hz output", file: file, line: line)
        XCTAssertEqual(capture.frequency(capture.right, seconds: seconds), wantedRight, accuracy: wantedRight * 0.03,
                       "\(name): right pitch at \(outputRate) Hz output", file: file, line: line)
    }

    private func label(_ rate: Double, _ channels: Int) -> String { "\(Int(rate))-\(channels)ch" }

    // MARK: The roadmap acceptance: five fixture formats decode

    func testFiveFixtureFormatsDecode() async throws {
        let (mp3URL, mp3Expectation) = try mp3("five.mp3", rate: 44_100, channels: 2)
        try await check(mp3URL, mp3Expectation)
        try await check(try tone("five.aac", .aac, rate: 44_100, channels: 2),
                        Expectation(container: .aac, sampleRate: 44_100, channels: 2, seconds: 0.5, durationTolerance: 3072 / 44_100,
                                    storedExtension: "aac"))
        try await check(try tone("five.m4a", .aac, rate: 44_100, channels: 2),
                        Expectation(container: .mpeg4, sampleRate: 44_100, channels: 2, seconds: 0.5, storedExtension: "m4a"))
        try await check(try tone("five.wav", .wav16, rate: 44_100, channels: 2),
                        Expectation(container: .wav, sampleRate: 44_100, channels: 2, seconds: 0.5, storedExtension: "wav"))
        try await check(try tone("five.aiff", .aiff16, rate: 44_100, channels: 2),
                        Expectation(container: .aiff, sampleRate: 44_100, channels: 2, seconds: 0.5, storedExtension: "aiff"))
        let listed = await library.tracks
        XCTAssertEqual(listed.count, 5)
    }

    // MARK: The matrix, format by format

    func testWAVMatrix() async throws {
        for rate in Self.allRates {
            for channels in 1...2 {
                try await check(try tone("wav-\(label(rate, channels)).wav", .wav16, rate: rate, channels: channels),
                                Expectation(container: .wav, sampleRate: rate, channels: channels, seconds: 0.5, storedExtension: "wav"))
            }
        }
    }

    func testAIFFMatrix() async throws {
        for rate in Self.allRates {
            for channels in 1...2 {
                try await check(try tone("aiff-\(label(rate, channels)).aiff", .aiff16, rate: rate, channels: channels),
                                Expectation(container: .aiff, sampleRate: rate, channels: channels, seconds: 0.5, storedExtension: "aiff"))
            }
        }
    }

    func testM4AMatrix() async throws {
        for rate in Self.aacRates {
            for channels in 1...2 {
                try await check(try tone("m4a-\(label(rate, channels)).m4a", .aac, rate: rate, channels: channels),
                                Expectation(container: .mpeg4, sampleRate: rate, channels: channels, seconds: 0.5, storedExtension: "m4a"))
            }
        }
    }

    func testRawAACMatrix() async throws {
        for rate in Self.aacRates {
            for channels in 1...2 {
                // The decoder counts the stream's padding packets, so the duration is longer than the tone.
                try await check(try tone("adts-\(label(rate, channels)).aac", .aac, rate: rate, channels: channels),
                                Expectation(container: .aac, sampleRate: rate, channels: channels, seconds: 0.5,
                                            durationTolerance: 3072 / rate, storedExtension: "aac"))
            }
        }
    }

    func testMP3Matrix() async throws {
        for rate in Self.mp3Rates {
            for channels in 1...2 {
                let (url, expectation) = try mp3("mp3-\(rate)-\(channels)ch.mp3", rate: rate, channels: channels)
                try await check(url, expectation)
            }
        }
    }

    func testEachFormatAlsoPlaysAt44100HzOutput() async throws {
        let (mp3URL, mp3Expectation) = try mp3("out.mp3", rate: 48_000, channels: 2)
        try await check(mp3URL, mp3Expectation, outputRate: 44_100)
        try await check(try tone("out.aac", .aac, rate: 48_000, channels: 1),
                        Expectation(container: .aac, sampleRate: 48_000, channels: 1, seconds: 0.5, durationTolerance: 3072 / 48_000,
                                    storedExtension: "aac"), outputRate: 44_100)
        try await check(try tone("out.m4a", .aac, rate: 22_050, channels: 2),
                        Expectation(container: .mpeg4, sampleRate: 22_050, channels: 2, seconds: 0.5, storedExtension: "m4a"), outputRate: 44_100)
        try await check(try tone("out.wav", .wav16, rate: 96_000, channels: 2),
                        Expectation(container: .wav, sampleRate: 96_000, channels: 2, seconds: 0.5, storedExtension: "wav"), outputRate: 44_100)
        try await check(try tone("out.aiff", .aiff16, rate: 8_000, channels: 1),
                        Expectation(container: .aiff, sampleRate: 8_000, channels: 1, seconds: 0.5, storedExtension: "aiff"), outputRate: 44_100)
    }

    func testOtherEncodingsTheDeviceDecodes() async throws {
        for (name, container) in [("pcm8.wav", AudioFixtures.Container.wav8), ("pcm24.wav", .wav24), ("float.wav", .wavFloat)] {
            try await check(try tone(name, container, rate: 44_100, channels: 2),
                            Expectation(container: .wav, sampleRate: 44_100, channels: 2, seconds: 0.5, storedExtension: "wav"))
        }
        // Apple Lossless in M4A: decoded by the system, so accepted (research AUD-002-D6).
        try await check(try tone("lossless.m4a", .appleLossless, rate: 44_100, channels: 2),
                        Expectation(container: .mpeg4, sampleRate: 44_100, channels: 2, seconds: 0.5, storedExtension: "m4a"))
        // A classic AIFF (not AIFF-C), written byte by byte.
        let classic = try AudioFixtures.writeHandAIFF(to: sources.appendingPathComponent("classic.aiff"), seconds: 0.5)
        try await check(classic, Expectation(container: .aiff, sampleRate: 44_100, channels: 1, seconds: 0.5, storedExtension: "aiff"))
        // The highest sample rate accepted (ImportedTrack.supportedSampleRates), which is also the
        // highest the system's own file writer produces.
        try await check(try tone("high.wav", .wav24, rate: 192_000, channels: 2),
                        Expectation(container: .wav, sampleRate: 192_000, channels: 2, seconds: 0.5, storedExtension: "wav"))
        XCTAssertEqual(ImportedTrack.supportedSampleRates, 8_000...192_000)
    }

    // MARK: Content decides, not the name (AUD-002-T13)

    func testMisnamedFilesImportAndPlayAlsoAfterReopening() async throws {
        let wav = try tone("true.wav", .wav16, rate: 44_100, channels: 2)
        let aiff = try tone("true.aiff", .aiff16, rate: 48_000, channels: 1)
        let m4a = try tone("true.m4a", .aac, rate: 44_100, channels: 2)
        let adts = try tone("true.aac", .aac, rate: 44_100, channels: 2)
        let (mp3URL, mp3Expectation) = try mp3("true.mp3", rate: 44_100, channels: 2)
        let wavExpectation = Expectation(container: .wav, sampleRate: 44_100, channels: 2, seconds: 0.5, storedExtension: "wav")
        let aiffExpectation = Expectation(container: .aiff, sampleRate: 48_000, channels: 1, seconds: 0.5, storedExtension: "aiff")
        let m4aExpectation = Expectation(container: .mpeg4, sampleRate: 44_100, channels: 2, seconds: 0.5, storedExtension: "m4a")
        let adtsExpectation = Expectation(container: .aac, sampleRate: 44_100, channels: 2, seconds: 0.5, durationTolerance: 3072 / 44_100,
                                          storedExtension: "aac")
        // Each misnamed copy has the same bytes as its original, so each gets its own library:
        // otherwise the second name would be reported as a duplicate.
        let cases: [(URL, String, Expectation)] = [
            (wav, "wav-as.mp3", wavExpectation), (wav, "wav-as.m4a", wavExpectation),
            (aiff, "aiff-as.wav", aiffExpectation), (aiff, "aiff-as.mp3", aiffExpectation),
            (m4a, "m4a-as.wav", m4aExpectation),
            (adts, "adts-as.mp3", adtsExpectation), (adts, "adts-as.m4a", adtsExpectation),
            (mp3URL, "mp3-as.aac", mp3Expectation), (mp3URL, "mp3-as.wav", mp3Expectation),
        ]
        for (index, (original, name, expectation)) in cases.enumerated() {
            libraryURL = root.appendingPathComponent("AudioLibrary-\(index)", isDirectory: true)
            library = AudioLibrary(directory: libraryURL)
            let misnamed = try AudioFixtures.copy(original, to: sources.appendingPathComponent(name))
            try await check(misnamed, expectation, reopen: true)
        }
    }

    func testMP3WithAnID3TagIsRecognizedByTheAudioAfterTheTag() async throws {
        let (short, expectation) = try mp3("tagged.mp3", rate: 44_100, channels: 1, id3Bytes: 2_000)
        try await check(short, expectation)
        // A tag longer than the recognition window, under a misleading name.
        let (long, longExpectation) = try mp3("tagged-long.wav", rate: 48_000, channels: 2, id3Bytes: 40_000)
        try await check(long, longExpectation, reopen: true)
    }

    func testOtherDecodableFormatKeepsItsOwnExtension() async throws {
        // CAF is not one of the five: imported as in AUD-001, under the picked extension.
        let caf = try tone("other.caf", .cafFloat, rate: 44_100, channels: 2)
        try await check(caf, Expectation(container: nil, sampleRate: 44_100, channels: 2, seconds: 0.5, storedExtension: "caf"))
    }

    // MARK: The stored record is unchanged (AUD-002-R13)

    func testIndexStaysVersion1WithTheSameFields() async throws {
        _ = await library.importFile(at: try AudioFixtures.copy(try tone("a.wav", .wav16, rate: 44_100, channels: 2),
                                                                to: sources.appendingPathComponent("a.mp3")))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: libraryURL.appendingPathComponent("index.json")))
                                   as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "tracks"])
        let entry = try XCTUnwrap((object["tracks"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(entry.keys), ["byteCount", "channelCount", "durationSeconds", "fileName", "id", "importedAt",
                                         "originalFileName", "sampleRate", "sha256", "title"])
        XCTAssertEqual(entry["originalFileName"] as? String, "a.mp3")
        XCTAssertEqual(entry["title"] as? String, "a")
    }

    func testLibraryWrittenByAUD001LoadsAndPlays() async throws {
        // AUD-001 named the stored copy after the picked extension; such a library must keep working.
        let legacy = root.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("assets"), withIntermediateDirectories: true)
        let digest = String(repeating: "0123456789abcdef", count: 4)
        let source = try tone("old.caf", .cafFloat, rate: 44_100, channels: 2)
        try FileManager.default.copyItem(at: source, to: legacy.appendingPathComponent("assets/\(digest).caf"))
        let bytes = try Data(contentsOf: source).count
        let record = """
        {"schemaVersion":1,"tracks":[{"byteCount":\(bytes),"channelCount":2,"durationSeconds":0.5,"fileName":"\(digest).caf",\
        "id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","importedAt":"2026-11-12T10:00:00Z","originalFileName":"old.caf",\
        "sampleRate":44100,"sha256":"\(digest)","title":"old"}]}
        """
        try Data(record.utf8).write(to: legacy.appendingPathComponent("index.json"))
        let old = AudioLibrary(directory: legacy)
        let state = await old.load()
        XCTAssertEqual(state, .ready)
        let tracks = await old.tracks
        XCTAssertEqual(tracks.map(\.title), ["old"])
        let url = await old.fileURL(for: try XCTUnwrap(tracks.first).id)
        try await assertPlays(try XCTUnwrap(url), Expectation(container: nil, sampleRate: 44_100, channels: 2, seconds: 0.5,
                                                              storedExtension: "caf"), outputRate: 48_000, name: "legacy")
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("index.json")), Data(record.utf8), "a clean load rewrites nothing")
    }
}
#endif
