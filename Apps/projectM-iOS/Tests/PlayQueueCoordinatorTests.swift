// AUD-003-T12: the app's queue on a real AudioLibrary in a temporary folder: new imports join it,
// deleting a track removes it, a second coordinator over the same folder (a relaunch) restores a
// reorder, and the library's own record is never touched by the queue. Fixtures are WAV files
// written here byte by byte; no media is bundled.
import CaptureKit
import CaptureUI
import XCTest
@testable import projectM_iOS

@MainActor
final class PlayQueueCoordinatorTests: XCTestCase {
    private var root: URL!
    private var picked: URL!
    private var libraryURL: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aud003-app-\(UUID().uuidString)", isDirectory: true)
        picked = root.appendingPathComponent("picked", isDirectory: true)
        libraryURL = root.appendingPathComponent("AudioLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeCoordinator() -> AudioLibraryCoordinator {
        AudioLibraryCoordinator(library: AudioLibrary(directory: libraryURL), queueDirectory: libraryURL) { _ in }
    }

    private var queueFile: URL { libraryURL.appendingPathComponent("queue.json") }
    private var indexFile: URL { libraryURL.appendingPathComponent("index.json") }

    private func wav(_ name: String, frames: Int = 4410, seed: Int) throws -> URL {
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

    /// Imports A, B, C one at a time; the list shows C, B, A.
    private func importThree(_ coordinator: AudioLibraryCoordinator) async throws {
        await coordinator.load()
        for (name, seed) in [("A.wav", 1), ("B.wav", 3), ("C.wav", 7)] {
            await coordinator.importPicked(.success([try wav(name, seed: seed)]))
        }
    }

    private func titles(_ coordinator: AudioLibraryCoordinator) -> [String] { coordinator.queue.items.map(\.title) }

    func testImportsJoinTheQueueInListOrder() async throws {
        let coordinator = makeCoordinator()
        try await importThree(coordinator)
        XCTAssertEqual(coordinator.tracks.map(\.title), ["C", "B", "A"])
        XCTAssertEqual(titles(coordinator), ["C", "B", "A"], "AUD-003-R2, R3: unedited, the queue is the list order")
        XCTAssertEqual(coordinator.queue.notQueued, [])
    }

    func testABatchImportJoinsTheQueueLastFirst() async throws {
        let coordinator = makeCoordinator()
        await coordinator.load()
        await coordinator.importPicked(.success([try wav("A.wav", seed: 1), try wav("B.wav", seed: 3)]))
        XCTAssertEqual(coordinator.tracks.map(\.title), ["B", "A"])
        XCTAssertEqual(titles(coordinator), ["B", "A"])
    }

    func testADuplicateImportChangesNothing() async throws {
        let coordinator = makeCoordinator()
        try await importThree(coordinator)
        coordinator.queue.moveDown(coordinator.queue.items[0].id)          // B, C, A
        let before = try Data(contentsOf: queueFile)
        await coordinator.importPicked(.success([try wav("A copy.wav", seed: 1)]))
        XCTAssertEqual(titles(coordinator), ["B", "C", "A"])
        XCTAssertEqual(try Data(contentsOf: queueFile), before)
    }

    func testDeletingFromTheLibraryRemovesFromTheQueueAndRemovingFromTheQueueKeepsTheTrack() async throws {
        let coordinator = makeCoordinator()
        try await importThree(coordinator)
        let b = try XCTUnwrap(coordinator.tracks.first { $0.title == "B" })
        await coordinator.remove(b)
        XCTAssertEqual(titles(coordinator), ["C", "A"])
        let a = try XCTUnwrap(coordinator.tracks.first { $0.title == "A" })
        coordinator.queue.remove(a.id.uuidString)
        XCTAssertEqual(titles(coordinator), ["C"])
        XCTAssertEqual(coordinator.tracks.map(\.title), ["C", "A"], "AUD-003-R6: still in Your Audio")
        XCTAssertEqual(coordinator.queue.notQueued.map(\.title), ["A"])
        coordinator.playNext(a)
        XCTAssertEqual(titles(coordinator), ["A", "C"])
        coordinator.addToQueue(a)
        XCTAssertEqual(titles(coordinator), ["C", "A"])
    }

    func testAReorderSurvivesARelaunchAndTheLibraryRecordIsUntouched() async throws {
        let coordinator = makeCoordinator()
        try await importThree(coordinator)
        let index = try Data(contentsOf: indexFile)
        let a = try XCTUnwrap(coordinator.queue.items.first { $0.title == "A" })
        coordinator.queue.moveUp(a.id)
        coordinator.queue.moveUp(a.id)                                       // A, C, B
        coordinator.queue.playbackDidMove(to: a.id)
        XCTAssertEqual(try Data(contentsOf: indexFile), index, "AUD-003-R16: queue edits never write index.json")

        let relaunched = makeCoordinator()
        await relaunched.load()
        XCTAssertEqual(titles(relaunched), ["A", "C", "B"])
        XCTAssertEqual(relaunched.queue.startItem?.title, "A")
        XCTAssertEqual(relaunched.queue.item(after: a.id)?.title, "C")
    }

    func testAnUnavailableLibraryLeavesTheQueueAlone() async throws {
        let coordinator = makeCoordinator()
        try await importThree(coordinator)
        coordinator.queue.moveDown(coordinator.queue.items[0].id)
        let queue = try Data(contentsOf: queueFile)
        try Data(#"{"schemaVersion":99,"tracks":[]}"#.utf8).write(to: indexFile)   // a newer app's library

        let relaunched = makeCoordinator()
        await relaunched.load()
        XCTAssertNotNil(relaunched.unavailableMessage)
        XCTAssertEqual(relaunched.queue.items, [])
        XCTAssertEqual(try Data(contentsOf: queueFile), queue, "the stored queue is not changed")
    }

    func testWithoutAQueueFolderTheQueueWorksInMemory() async throws {
        let coordinator = AudioLibraryCoordinator(library: AudioLibrary(directory: libraryURL)) { _ in }
        try await importThree(coordinator)
        XCTAssertEqual(titles(coordinator), ["C", "B", "A"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: queueFile.path))
    }
}
