// AudioLibraryTests.swift — the imported-audio library on real files in a temporary directory
// (AUD-001-T05, T07, T20, T24, T27). Fixtures are generated tones; nothing is committed.
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
import AVFAudio
import CryptoKit
import Foundation
import XCTest
@testable import CaptureKit

/// Inspector double for results generated media cannot produce (DRM, forced failures).
struct FakeInspector: AudioFileInspecting {
    var result: Result<AudioFileInfo, AudioImportError> = .success(AudioFileInfo(durationSeconds: 1, sampleRate: 44_100, channelCount: 2))
    func inspect(_ url: URL) async throws(AudioImportError) -> AudioFileInfo { try result.get() }
}

final class AVAudioFileInspectorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud001-inspect")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testReportsWAVAndCAF() async throws {
        let wav = try AudioFixtures.writeTone(to: root.appendingPathComponent("a.wav"), seconds: 0.5, sampleRate: 48_000, channels: 2)
        let caf = try AudioFixtures.writeTone(to: root.appendingPathComponent("b.caf"), seconds: 0.25, sampleRate: 44_100, channels: 1,
                                              container: .cafFloat)
        let inspector = AVAudioFileInspector()
        let a = try await inspector.inspect(wav)
        XCTAssertEqual(a.durationSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(a.sampleRate, 48_000)
        XCTAssertEqual(a.channelCount, 2)
        let b = try await inspector.inspect(caf)
        XCTAssertEqual(b.durationSeconds, 0.25, accuracy: 0.001)
        XCTAssertEqual(b.sampleRate, 44_100)
        XCTAssertEqual(b.channelCount, 1)
    }

    func testGarbageAndEmptyFilesAreUnreadable() async throws {
        let garbage = try AudioFixtures.writeGarbage(to: root.appendingPathComponent("garbage.wav"))
        let empty = root.appendingPathComponent("empty.wav")
        try Data().write(to: empty)
        let text = root.appendingPathComponent("text.mp3")
        try Data("this is not an mp3".utf8).write(to: text)
        for url in [garbage, empty, text, root.appendingPathComponent("missing.wav")] {
            do {
                _ = try await AVAudioFileInspector().inspect(url)
                XCTFail("\(url.lastPathComponent) must not pass")
            } catch {
                XCTAssertEqual(error, .unreadable, url.lastPathComponent)
            }
        }
    }

    func testMoreThanTwoChannelsIsRefused() async throws {
        let quad = try AudioFixtures.writeRawWAV(to: root.appendingPathComponent("quad.wav"), channels: 4)
        do {
            _ = try await AVAudioFileInspector().inspect(quad)
            XCTFail("4 channels must not pass")
        } catch {
            XCTAssertEqual(error, .unsupportedChannelCount(4))
        }
    }

    func testRawWAVFixtureIsValidStereo() async throws {
        let stereo = try AudioFixtures.writeRawWAV(to: root.appendingPathComponent("stereo.wav"), channels: 2)
        let info = try await AVAudioFileInspector().inspect(stereo)
        XCTAssertEqual(info.channelCount, 2)
        XCTAssertEqual(info.durationSeconds, 0.1, accuracy: 0.001)
    }
}

final class AudioLibraryTests: XCTestCase {
    private var root: URL!
    private var sources: URL!
    private var libraryURL: URL!
    static let fixedDate = Date(timeIntervalSince1970: 1_794_477_600)

    override func setUpWithError() throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud001-library")
        sources = root.appendingPathComponent("picked", isDirectory: true)
        libraryURL = root.appendingPathComponent("AudioLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    private func makeLibrary(inspector: any AudioFileInspecting = AVAudioFileInspector(), maxFileBytes: Int64 = AudioLibrary.maxFileBytes,
                             indexWriter: (@Sendable (Data, URL) throws -> Void)? = nil) -> AudioLibrary {
        AudioLibrary(directory: libraryURL, inspector: inspector, maxFileBytes: maxFileBytes,
                     now: { Self.fixedDate }, makeID: UUID.init, indexWriter: indexWriter ?? AudioLibrary.atomicWrite)
    }

    private func tone(_ name: String, seconds: Double = 0.25, frequency: Double = 440) throws -> URL {
        try AudioFixtures.writeTone(to: sources.appendingPathComponent(name), seconds: seconds, frequency: frequency)
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func libraryTree() -> [String] { AudioFixtures.tree(libraryURL) }
    private var indexURL: URL { libraryURL.appendingPathComponent("index.json") }
    private func indexBytes() -> Data? { try? Data(contentsOf: indexURL) }

    private func imported(_ outcome: AudioImportOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> ImportedTrack {
        guard case .imported(let track) = outcome else {
            XCTFail("expected imported, got \(outcome)", file: file, line: line)
            throw CocoaError(.featureUnsupported)
        }
        return track
    }

    /// Imports `url`, expecting `error`, and checks the library is byte-for-byte what it was.
    private func assertRefused(_ url: URL, _ error: AudioImportError, by library: AudioLibrary,
                               file: StaticString = #filePath, line: UInt = #line) async {
        _ = await library.load()
        let treeBefore = libraryTree()
        let indexBefore = indexBytes()
        let tracksBefore = await library.tracks
        let outcome = await library.importFile(at: url)
        XCTAssertEqual(outcome, .failed(fileName: url.lastPathComponent, error), file: file, line: line)
        XCTAssertEqual(libraryTree(), treeBefore, "no partial or temporary file may remain", file: file, line: line)
        XCTAssertEqual(indexBytes(), indexBefore, file: file, line: line)
        let tracksAfter = await library.tracks
        XCTAssertEqual(tracksAfter, tracksBefore, file: file, line: line)
    }

    // MARK: US1 — import (AUD-001-T07)

    func testImportCopiesValidFileIntoLibrary() async throws {
        let source = try tone("My Song.wav")
        let digest = try sha256(source)
        let library = makeLibrary()
        let track = try imported(await library.importFile(at: source))

        XCTAssertEqual(track.title, "My Song")
        XCTAssertEqual(track.originalFileName, "My Song.wav")
        XCTAssertEqual(track.sha256, digest)
        XCTAssertEqual(track.fileName, "\(digest).wav")
        XCTAssertEqual(track.byteCount, Int64(try Data(contentsOf: source).count))
        XCTAssertEqual(track.durationSeconds, 0.25, accuracy: 0.001)
        XCTAssertEqual(track.sampleRate, 44_100)
        XCTAssertEqual(track.channelCount, 2)
        XCTAssertEqual(track.importedAt, Self.fixedDate)
        XCTAssertTrue(track.isValid)

        XCTAssertEqual(libraryTree(), ["assets/\(digest).wav", "index.json"], "incoming/ is empty; nothing else is written")
        let asset = libraryURL.appendingPathComponent("assets/\(digest).wav")
        XCTAssertEqual(try Data(contentsOf: asset), try Data(contentsOf: source), "the copy is byte-identical")
        let resolved = await library.fileURL(for: track.id)
        XCTAssertEqual(resolved?.resolvingSymlinksInPath(), asset.resolvingSymlinksInPath())
        let listed = await library.tracks
        XCTAssertEqual(listed, [track])
    }

    func testIndexHoldsNoPathOrPickedLocation() async throws {
        let source = try tone("Private Name.wav")
        let library = makeLibrary()
        let track = try imported(await library.importFile(at: source))
        let text = String(decoding: try XCTUnwrap(indexBytes()), as: UTF8.self)
        XCTAssertEqual(try AudioLibraryIndex.decode(Data(text.utf8)), .index(AudioLibraryIndex(tracks: [track])))
        XCTAssertFalse(text.contains(sources.path), "AUD-001-R3: the picked location is never stored")
        XCTAssertFalse(text.contains(root.lastPathComponent))
        XCTAssertFalse(text.contains("/"), "no path of any kind")
        XCTAssertFalse(text.lowercased().contains("bookmark"))
    }

    func testImportFilesKeepsInputOrderAndListsNewestLast() async throws {
        let a = try tone("A.wav", frequency: 300)
        let bad = sources.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: bad)
        let b = try tone("B.wav", frequency: 600)
        let library = makeLibrary()
        let outcomes = await library.importFiles(at: [a, bad, b])
        XCTAssertEqual(outcomes.count, 3)
        let first = try imported(outcomes[0])
        XCTAssertEqual(outcomes[1], .failed(fileName: "notes.txt", .notAudio))
        let third = try imported(outcomes[2])
        let listed = await library.tracks
        XCTAssertEqual(listed.map(\.title), ["A", "B"])
        XCTAssertEqual(listed, [first, third])
    }

    func testSameNameDifferentContentAreBothKept() async throws {
        let first = try tone("Song.wav", frequency: 300)
        let library = makeLibrary()
        _ = try imported(await library.importFile(at: first))
        let other = sources.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let second = try AudioFixtures.writeTone(to: other.appendingPathComponent("Song.wav"), frequency: 900)
        _ = try imported(await library.importFile(at: second))
        let listed = await library.tracks
        XCTAssertEqual(listed.map(\.title), ["Song", "Song"])
        XCTAssertEqual(Set(listed.map(\.sha256)).count, 2)
    }

    func testUnknownIDHasNoFileURL() async {
        let library = makeLibrary()
        _ = await library.load()
        let url = await library.fileURL(for: UUID())
        XCTAssertNil(url)
    }

    // MARK: US2 — relaunch and recovery (AUD-001-T20)

    func testRelaunchFindsAndOpensTrackWithoutTheOriginal() async throws {
        let source = try tone("Keep.wav")
        let track = try imported(await makeLibrary().importFile(at: source))
        try FileManager.default.removeItem(at: sources)          // the original is gone for good

        let relaunched = makeLibrary()
        let state = await relaunched.load()
        XCTAssertEqual(state, .ready)
        let listed = await relaunched.tracks
        XCTAssertEqual(listed, [track])
        let stored = await relaunched.fileURL(for: track.id)
        let url = try XCTUnwrap(stored)
        let file = try AVAudioFile(forReading: url)               // opens with no access to the picked URL
        XCTAssertEqual(file.length, 11_025)
    }

    func testLoadSweepsLeftoversFromInterruptedImports() async throws {
        let track = try imported(await makeLibrary().importFile(at: try tone("Good.wav")))
        let incoming = libraryURL.appendingPathComponent("incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: incoming.appendingPathComponent("\(UUID().uuidString).wav"))
        let orphan = String(repeating: "cd", count: 32) + ".wav"
        try AudioFixtures.writeTone(to: libraryURL.appendingPathComponent("assets/\(orphan)"))

        let relaunched = makeLibrary()
        _ = await relaunched.load()
        XCTAssertEqual(libraryTree(), ["assets/\(track.fileName)", "index.json"])
        let listed = await relaunched.tracks
        XCTAssertEqual(listed, [track])
    }

    func testEntryWithMissingAssetIsDroppedAndIndexRewritten() async throws {
        let library = makeLibrary()
        let gone = try imported(await library.importFile(at: try tone("Gone.wav", frequency: 300)))
        let kept = try imported(await library.importFile(at: try tone("Kept.wav", frequency: 600)))
        try FileManager.default.removeItem(at: libraryURL.appendingPathComponent("assets/\(gone.fileName)"))

        let relaunched = makeLibrary()
        _ = await relaunched.load()
        let listed = await relaunched.tracks
        XCTAssertEqual(listed, [kept])
        XCTAssertEqual(try AudioLibraryIndex.decode(try XCTUnwrap(indexBytes())), .index(AudioLibraryIndex(tracks: [kept])))
    }

    func testDamagedIndexIsKeptAsideAndRebuiltFromAssets() async throws {
        let library = makeLibrary()
        let a = try imported(await library.importFile(at: try tone("A.wav", frequency: 300)))
        let b = try imported(await library.importFile(at: try tone("B.wav", seconds: 0.5, frequency: 600)))
        let good = try XCTUnwrap(indexBytes())
        let damaged = good.prefix(good.count / 2)
        try damaged.write(to: indexURL)
        // An asset that no longer decodes is not recovered.
        let broken = String(repeating: "ef", count: 32) + ".wav"
        try AudioFixtures.writeGarbage(to: libraryURL.appendingPathComponent("assets/\(broken)"))

        let relaunched = makeLibrary()
        let state = await relaunched.load()
        XCTAssertEqual(state, .ready)
        XCTAssertEqual(try Data(contentsOf: libraryURL.appendingPathComponent("index.damaged.json")), damaged,
                       "AUD-001-R14: the damaged record is kept, not deleted")
        let listed = await relaunched.tracks
        XCTAssertEqual(Set(listed.map(\.sha256)), [a.sha256, b.sha256])
        XCTAssertEqual(listed.map(\.title), ["Recovered track 1", "Recovered track 2"])
        XCTAssertTrue(listed.allSatisfy(\.isValid))
        let recoveredB = try XCTUnwrap(listed.first { $0.sha256 == b.sha256 })
        XCTAssertEqual(recoveredB.durationSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(recoveredB.byteCount, b.byteCount)
        XCTAssertEqual(libraryTree(), ["assets/\(a.fileName)", "assets/\(b.fileName)", "index.damaged.json", "index.json"].sorted())
        XCTAssertEqual(try AudioLibraryIndex.decode(try XCTUnwrap(indexBytes())), .index(AudioLibraryIndex(tracks: listed)))
        // The recovered library works: a third launch reads the rebuilt record unchanged.
        let third = makeLibrary()
        _ = await third.load()
        let again = await third.tracks
        XCTAssertEqual(again, listed)
    }

    func testNewerFormatIsLeftUntouchedAndLibraryIsUnavailable() async throws {
        let library = makeLibrary()
        let track = try imported(await library.importFile(at: try tone("Old.wav")))
        try Data(#"{"schemaVersion":2,"tracks":{"shape":"unknown"}}"#.utf8).write(to: indexURL)
        try Data("x".utf8).write(to: libraryURL.appendingPathComponent("assets/unknown-new-file.bin"))
        let treeBefore = libraryTree()
        let indexBefore = indexBytes()

        let downgraded = makeLibrary()
        let state = await downgraded.load()
        XCTAssertEqual(state, .unavailable(.newerFormat))
        let listed = await downgraded.tracks
        XCTAssertEqual(listed, [])
        let outcome = await downgraded.importFile(at: try tone("New.wav", frequency: 900))
        XCTAssertEqual(outcome, .failed(fileName: "New.wav", .libraryUnavailable))
        do {
            try await downgraded.remove(track.id)
            XCTFail("removal must be refused")
        } catch {
            XCTAssertEqual(error, .libraryUnavailable)
        }
        XCTAssertEqual(libraryTree(), treeBefore, "AUD-001-R15: nothing is deleted or added")
        XCTAssertEqual(indexBytes(), indexBefore)
    }

    func testUnusableDirectoryMakesLibraryUnavailable() async throws {
        // A regular file where the library folder should be.
        try Data("x".utf8).write(to: libraryURL)
        let library = makeLibrary()
        let state = await library.load()
        XCTAssertEqual(state, .unavailable(.storage))
        let outcome = await library.importFile(at: try tone("A.wav"))
        XCTAssertEqual(outcome, .failed(fileName: "A.wav", .libraryUnavailable))
        XCTAssertEqual(try Data(contentsOf: libraryURL), Data("x".utf8))
    }

    // MARK: US3 — refusals leave nothing behind (AUD-001-T24)

    func testNonAudioTypeIsRefused() async throws {
        let text = sources.appendingPathComponent("notes.txt")
        try Data("not audio".utf8).write(to: text)
        let noExtension = sources.appendingPathComponent("README")
        try Data("not audio".utf8).write(to: noExtension)
        let library = makeLibrary()
        _ = try imported(await library.importFile(at: try tone("Existing.wav")))
        await assertRefused(text, .notAudio, by: library)
        await assertRefused(noExtension, .notAudio, by: library)
    }

    func testGarbageNamedWAVIsRefusedAsUnreadable() async throws {
        let garbage = try AudioFixtures.writeGarbage(to: sources.appendingPathComponent("fake.wav"))
        let empty = sources.appendingPathComponent("empty.wav")
        try Data().write(to: empty)
        let library = makeLibrary()
        _ = try imported(await library.importFile(at: try tone("Existing.wav")))
        await assertRefused(garbage, .unreadable, by: library)
        await assertRefused(empty, .unreadable, by: library)
    }

    func testOversizedFileIsRefusedAtTheLimit() async throws {
        let big = try tone("Big.wav", seconds: 1)                 // about 176 kB
        let library = makeLibrary(maxFileBytes: 100_000)
        await assertRefused(big, .tooLarge(limitBytes: 100_000), by: library)
        let exact = makeLibrary(maxFileBytes: Int64(try Data(contentsOf: big).count))
        _ = try imported(await exact.importFile(at: big))        // exactly the limit is allowed
    }

    func testMoreThanTwoChannelsIsRefused() async throws {
        let quad = try AudioFixtures.writeRawWAV(to: sources.appendingPathComponent("quad.wav"), channels: 4)
        await assertRefused(quad, .unsupportedChannelCount(4), by: makeLibrary())
    }

    func testProtectedContentIsRefused() async throws {
        // No DRM fixture can be generated, so the inspector seam reports the protection.
        let library = makeLibrary(inspector: FakeInspector(result: .failure(.protectedContent)))
        await assertRefused(try tone("Purchased.wav"), .protectedContent, by: library)
    }

    func testMissingSourceIsRefused() async throws {
        await assertRefused(sources.appendingPathComponent("nowhere.wav"), .sourceUnavailable, by: makeLibrary())
        await assertRefused(sources, .notAudio, by: makeLibrary())   // a folder
    }

    func testFailedIndexWriteRollsBackTheImport() async throws {
        let failing = LockedFlag()
        let library = makeLibrary(indexWriter: { data, url in
            if failing.value { throw CocoaError(.fileWriteUnknown) }
            try AudioLibrary.atomicWrite(data, url)
        })
        let first = try imported(await library.importFile(at: try tone("First.wav", frequency: 300)))
        failing.value = true
        await assertRefused(try tone("Second.wav", frequency: 600), .libraryUnavailable, by: library)
        failing.value = false
        // The library still works and the first track is intact.
        let second = try imported(await library.importFile(at: try tone("Third.wav", frequency: 900)))
        let listed = await library.tracks
        XCTAssertEqual(listed, [first, second])
    }

    func testOutOfSpaceIndexWriteIsReportedAsStorage() async throws {
        let library = makeLibrary(indexWriter: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        await assertRefused(try tone("A.wav"), .insufficientStorage, by: library)
    }

    func testDuplicateContentIsStoredOnce() async throws {
        let original = try tone("Original.wav")
        let renamed = sources.appendingPathComponent("Renamed Copy.wav")
        try FileManager.default.copyItem(at: original, to: renamed)
        let library = makeLibrary()
        let first = try imported(await library.importFile(at: original))
        let treeBefore = libraryTree()
        let indexBefore = indexBytes()
        let outcome = await library.importFile(at: renamed)
        XCTAssertEqual(outcome, .duplicate(first), "AUD-001-R8: the existing track, with its title, is kept")
        let again = await library.importFile(at: original)
        XCTAssertEqual(again, .duplicate(first))
        XCTAssertEqual(libraryTree(), treeBefore)
        XCTAssertEqual(indexBytes(), indexBefore)
    }

    func testConcurrentImportsOfTheSameContentStoreItOnce() async throws {
        let original = try tone("Original.wav")
        let copy = sources.appendingPathComponent("Copy.wav")
        try FileManager.default.copyItem(at: original, to: copy)
        let library = makeLibrary()
        async let one = library.importFile(at: original)
        async let two = library.importFile(at: copy)
        let outcomes = await [one, two]
        let importedCount = outcomes.filter { if case .imported = $0 { return true } else { return false } }.count
        let duplicateCount = outcomes.filter { if case .duplicate = $0 { return true } else { return false } }.count
        XCTAssertEqual(importedCount, 1)
        XCTAssertEqual(duplicateCount, 1)
        XCTAssertEqual(libraryTree().filter { $0.hasPrefix("assets/") }.count, 1)
    }

    // MARK: US4 — removal (AUD-001-T27)

    func testRemoveDeletesAssetAndEntryAndSurvivesReopen() async throws {
        let library = makeLibrary()
        let a = try imported(await library.importFile(at: try tone("A.wav", frequency: 300)))
        let b = try imported(await library.importFile(at: try tone("B.wav", frequency: 600)))
        try await library.remove(a.id)
        let listed = await library.tracks
        XCTAssertEqual(listed, [b])
        XCTAssertEqual(libraryTree(), ["assets/\(b.fileName)", "index.json"])
        let gone = await library.fileURL(for: a.id)
        XCTAssertNil(gone)
        let reopened = makeLibrary()
        _ = await reopened.load()
        let after = await reopened.tracks
        XCTAssertEqual(after, [b])
        // Removed content can be imported again.
        _ = try imported(await reopened.importFile(at: sources.appendingPathComponent("A.wav")))
    }

    func testRemoveUnknownIDIsANoOp() async throws {
        let library = makeLibrary()
        let a = try imported(await library.importFile(at: try tone("A.wav")))
        let before = indexBytes()
        try await library.remove(UUID())
        let listed = await library.tracks
        XCTAssertEqual(listed, [a])
        XCTAssertEqual(indexBytes(), before)
    }

    func testFailedIndexWriteKeepsTrackAndAsset() async throws {
        let failing = LockedFlag()
        let library = makeLibrary(indexWriter: { data, url in
            if failing.value { throw CocoaError(.fileWriteUnknown) }
            try AudioLibrary.atomicWrite(data, url)
        })
        let a = try imported(await library.importFile(at: try tone("A.wav")))
        let tree = libraryTree()
        failing.value = true
        do {
            try await library.remove(a.id)
            XCTFail("must throw")
        } catch {
            XCTAssertEqual(error, .libraryUnavailable)
        }
        let listed = await library.tracks
        XCTAssertEqual(listed, [a])
        XCTAssertEqual(libraryTree(), tree)
    }

    func testDefaultDirectoryIsApplicationSupport() throws {
        let url = try AudioLibrary.defaultDirectory()
        XCTAssertEqual(url.lastPathComponent, "AudioLibrary")
        XCTAssertTrue(url.path.contains("Application Support"), "persistent, not Caches or tmp (AUD-001-R2)")
    }
}

/// A flag tests flip from the test body while a `@Sendable` hook reads it.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
#endif
