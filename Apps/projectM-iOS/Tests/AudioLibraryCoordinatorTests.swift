// AUD-001-T16: AudioLibraryCoordinator on a real AudioLibrary in a temporary directory. Fixtures
// are WAV files written here byte by byte (a quiet ramp); no media is bundled.
import CaptureKit
import CaptureUI
import XCTest
@testable import projectM_iOS

@MainActor
final class AudioLibraryCoordinatorTests: XCTestCase {
    private var root: URL!
    private var picked: URL!
    private var libraryURL: URL!
    private var announcements: [String] = []

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aud001-app-\(UUID().uuidString)", isDirectory: true)
        picked = root.appendingPathComponent("picked", isDirectory: true)
        libraryURL = root.appendingPathComponent("AudioLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        announcements = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeCoordinator() -> AudioLibraryCoordinator {
        AudioLibraryCoordinator(library: AudioLibrary(directory: libraryURL)) { [weak self] in self?.announcements.append($0) }
    }

    /// A 16-bit stereo PCM WAV; `seed` makes the content (and so the content hash) differ.
    private func wav(_ name: String, frames: Int = 4410, seed: Int = 1) throws -> URL {
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        let dataBytes = frames * 4
        var bytes: [UInt8] = Array("RIFF".utf8) + le(UInt32(36 + dataBytes)) + Array("WAVEfmt ".utf8)
        bytes += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(2)) + le(UInt32(44_100))
        bytes += le(UInt32(44_100 * 4)) + le(UInt16(4)) + le(UInt16(16))
        bytes += Array("data".utf8) + le(UInt32(dataBytes))
        for frame in 0..<frames {
            let sample = Int16(truncatingIfNeeded: (frame * seed % 200) * 60)
            bytes += le(sample) + le(sample)
        }
        let url = picked.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    func testImportListsNewestFirstWithoutAnAlert() async throws {
        let coordinator = makeCoordinator()
        await coordinator.load()
        XCTAssertEqual(coordinator.tracks, [])
        await coordinator.importPicked(.success([try wav("First.wav", seed: 1)]))
        await coordinator.importPicked(.success([try wav("Second.wav", seed: 3)]))
        XCTAssertEqual(coordinator.tracks.map(\.title), ["Second", "First"], "AUD-001-R10: newest first")
        XCTAssertFalse(coordinator.isImporting)
        XCTAssertNil(coordinator.resultMessage, "a clean import needs no alert")
        XCTAssertNil(coordinator.unavailableMessage)
        XCTAssertEqual(announcements, ["Imported 1 track.", "Imported 1 track."], "AUD-001-R24: announced to VoiceOver")
    }

    func testImportingFlagIsSetWhileFilesAreCopied() async throws {
        let coordinator = makeCoordinator()
        let url = try wav("Song.wav")
        let work = Task { await coordinator.importPicked(.success([url])) }
        var sawImporting = false
        for _ in 0..<10_000 where !sawImporting {
            sawImporting = coordinator.isImporting
            await Task.yield()
        }
        await work.value
        XCTAssertTrue(sawImporting, "AUD-001-R9: the chooser can show progress")
        XCTAssertFalse(coordinator.isImporting)
    }

    /// A classic AIFF header (mono, 16-bit, 44.1 kHz) stating 44,100 frames, followed by only 100.
    static func truncatedAIFF() -> Data {
        func be<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }
        let sound = [UInt8](repeating: 0, count: 200)
        let common = be(Int16(1)) + be(UInt32(44_100)) + be(Int16(16)) + be(UInt16(0x400E)) + be(UInt64(0xAC44_0000_0000_0000))
        var body: [UInt8] = Array("AIFF".utf8) + Array("COMM".utf8) + be(UInt32(common.count)) + common
        body += Array("SSND".utf8) + be(UInt32(88_200 + 8)) + be(UInt32(0)) + be(UInt32(0)) + sound
        return Data(Array("FORM".utf8) + be(UInt32(4 + 8 + common.count + 8 + 8 + 88_200)) + body)
    }

    func testRefusedAndDuplicateFilesProduceOneMessage() async throws {
        let coordinator = makeCoordinator()
        let song = try wav("Song.wav")
        await coordinator.importPicked(.success([song]))
        let notes = picked.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: notes)
        let fake = picked.appendingPathComponent("fake.wav")
        try Data(repeating: 7, count: 2048).write(to: fake)
        // AUD-002-R7: an AIFF whose header promises one second of audio but which holds 100 frames.
        let cut = picked.appendingPathComponent("cut.aiff")
        try Self.truncatedAIFF().write(to: cut)
        let empty = picked.appendingPathComponent("empty.mp3")
        try Data().write(to: empty)
        await coordinator.importPicked(.success([notes, try wav("New.wav", seed: 5), song, fake, cut, empty]))
        // AUD-002-R8: bytes that are no audio format are "unsupported", no longer "damaged".
        XCTAssertEqual(coordinator.resultMessage, """
        Imported 1 track.
        “notes.txt”: This file isn't a supported audio file.
        “Song” is already in your library.
        “fake.wav”: This file's format isn't supported. Import MP3, AAC, M4A, WAV or AIFF audio.
        “cut.aiff”: This audio file can't be read. It may be damaged.
        “empty.mp3”: This file contains no audio.
        """)
        XCTAssertEqual(coordinator.tracks.map(\.title), ["New", "Song"])
        XCTAssertEqual(announcements.last, coordinator.resultMessage)
    }

    func testCancelledOrEmptyPickerChangesNothing() async {
        let coordinator = makeCoordinator()
        await coordinator.importPicked(.failure(CocoaError(.userCancelled)))
        await coordinator.importPicked(.success([]))
        XCTAssertNil(coordinator.resultMessage)
        XCTAssertEqual(coordinator.tracks, [])
        XCTAssertEqual(announcements, [])
    }

    func testPickerFailureIsReported() async {
        let coordinator = makeCoordinator()
        await coordinator.importPicked(.failure(CocoaError(.fileReadNoPermission)))
        XCTAssertEqual(coordinator.resultMessage, "This file couldn't be opened.")
    }

    func testRelaunchListsAndResolvesTheTrackWithoutTheOriginal() async throws {
        let first = makeCoordinator()
        await first.importPicked(.success([try wav("Keep.wav")]))
        try FileManager.default.removeItem(at: picked)             // the original is gone

        let relaunched = makeCoordinator()
        await relaunched.load()
        XCTAssertEqual(relaunched.tracks.map(\.title), ["Keep"])
        let track = try XCTUnwrap(relaunched.tracks.first)
        let resolved = await relaunched.playbackURL(for: track)
        let url = try XCTUnwrap(resolved)
        XCTAssertTrue(url.path.hasPrefix(libraryURL.path), "AUD-001-R3: playback uses the library's own copy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRemoveDeletesTheTrack() async throws {
        let coordinator = makeCoordinator()
        await coordinator.importPicked(.success([try wav("A.wav", seed: 1), try wav("B.wav", seed: 3)]))
        let a = try XCTUnwrap(coordinator.tracks.first { $0.title == "A" })
        await coordinator.remove(a)
        XCTAssertEqual(coordinator.tracks.map(\.title), ["B"])
        let gone = await coordinator.playbackURL(for: a)
        XCTAssertNil(gone)
        let relaunched = makeCoordinator()
        await relaunched.load()
        XCTAssertEqual(relaunched.tracks.map(\.title), ["B"])
    }

    func testNewerLibraryFormatIsShownAsUnavailable() async throws {
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":2,"tracks":[]}"#.utf8).write(to: libraryURL.appendingPathComponent("index.json"))
        let coordinator = makeCoordinator()
        await coordinator.load()
        XCTAssertEqual(coordinator.unavailableMessage,
                       "Your audio library was saved by a newer version of the app. Update the app to use it.")
        await coordinator.importPicked(.success([try wav("A.wav")]))
        XCTAssertEqual(coordinator.resultMessage, "“A.wav”: Your audio library isn't available.")
        XCTAssertEqual(coordinator.tracks, [])
    }

    func testMissingLibraryFolderIsShownAsUnavailable() async throws {
        let coordinator = AudioLibraryCoordinator(library: nil) { _ in }
        XCTAssertEqual(coordinator.unavailableMessage, "Your audio library couldn't be opened.")
        await coordinator.importPicked(.success([try wav("A.wav")]))
        XCTAssertEqual(coordinator.resultMessage, "Your audio library isn't available.")
    }
}
