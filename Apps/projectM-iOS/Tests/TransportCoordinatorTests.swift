// AUD-006-T29: the play order the app hands to the transport comes from the "Your Audio" list as
// shown (newest first), each item playing the library's own stored copy; the reference track is
// an order of one. Fixtures are WAV files written here byte by byte; no media is bundled.
import CaptureKit
import CaptureUI
import XCTest
@testable import projectM_iOS

@MainActor
final class TransportCoordinatorTests: XCTestCase {
    private var root: URL!
    private var picked: URL!
    private var libraryURL: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aud006-app-\(UUID().uuidString)", isDirectory: true)
        picked = root.appendingPathComponent("picked", isDirectory: true)
        libraryURL = root.appendingPathComponent("AudioLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

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

    func testPlaybackItemsFollowTheListAndPlayTheStoredCopies() async throws {
        let coordinator = AudioLibraryCoordinator(library: AudioLibrary(directory: libraryURL)) { _ in }
        await coordinator.load()
        let empty = await coordinator.playbackItems()
        XCTAssertEqual(empty, [])
        await coordinator.importPicked(.success([try wav("First.wav", seed: 1)]))
        await coordinator.importPicked(.success([try wav("Second.wav", frames: 8820, seed: 3)]))
        await coordinator.importPicked(.success([try wav("Third.wav", seed: 5)]))

        let items = await coordinator.playbackItems()
        XCTAssertEqual(items.map(\.title), ["Third", "Second", "First"], "the order of Your Audio: newest first")
        XCTAssertEqual(items.map(\.id), coordinator.tracks.map(\.id.uuidString))
        XCTAssertEqual(items[1].durationSeconds, 0.2, accuracy: 0.001)
        for item in items {
            guard case .file(let url) = item.track else { return XCTFail("a library item plays a file") }
            XCTAssertTrue(url.path.hasPrefix(libraryURL.path), "the library's own copy, never the picked file")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        // The order the transport walks: Next goes down the list and wraps, Previous goes up.
        let order = ListPlayOrder(items)
        XCTAssertEqual(order.item(after: items[0].id)?.title, "Second")
        XCTAssertEqual(order.item(after: items[2].id)?.title, "Third")
        XCTAssertEqual(order.item(before: items[0].id)?.title, "First")

        // A removed track leaves the order.
        await coordinator.remove(coordinator.tracks[1])
        let remaining = await coordinator.playbackItems()
        XCTAssertEqual(remaining.map(\.title), ["Third", "First"])
    }

    func testAnUnavailableLibraryHasNoItems() async {
        let coordinator = AudioLibraryCoordinator(library: nil) { _ in }
        let items = await coordinator.playbackItems()
        XCTAssertEqual(items, [])
    }

    func testTheReferenceTrackIsAnOrderOfOne() {
        let reference = AudioLibraryCoordinator.referenceItem
        XCTAssertEqual(reference.title, "Reference track")
        XCTAssertEqual(reference.title, UIStrings.referenceTrackTitle)
        XCTAssertEqual(reference.track, .reference)
        XCTAssertEqual(reference.id, PlaybackItem.referenceID)
        let order = ListPlayOrder([reference])
        XCTAssertEqual(order.item(after: reference.id), reference, "it repeats; Next starts it again")
        XCTAssertEqual(order.item(before: reference.id), reference)
    }
}
