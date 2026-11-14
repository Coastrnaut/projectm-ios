// RecordingLibraryAcceptanceTests.swift — REC-010-T09, T11: the roadmap acceptance "Delete removes file after
// confirmation and updates list immediately" (REC-010-S1) on three recordings generated at test time, plus Cancel,
// thumbnails and their cache (S3), Incomplete rows (S4), order (S2), the header facts, Keep (contract C1), rename
// rules (C5), and the storage and erase integration (S5). Each test uses its own temporary container; no clock.
import Foundation
import LibraryBackup
import LocalPortability
import XCTest
@testable import projectM_iOS

@MainActor
final class RecordingLibraryAcceptanceTests: XCTestCase {
    private struct Fixture {
        let container: URL
        let locations: StorageLocations
        let store: RecordingLibraryStore
        let inspector: RecordingLibraryInspector
        let model: RecordingLibraryModel
        var announced: [String] { box.texts }
        let box: AnnouncedBox
    }

    private final class AnnouncedBox { var texts: [String] = [] }

    private func fixture(_ label: String = "library") throws -> Fixture {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingLibraryTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: container) }
        let support = container.appendingPathComponent("Library/Application Support", isDirectory: true)
        let caches = container.appendingPathComponent("Library/Caches", isDirectory: true)
        let locations = StorageLocations.make(applicationSupport: support, temporary: container.appendingPathComponent("tmp", isDirectory: true),
                                              caches: caches, container: container)
        let folder = try XCTUnwrap(locations.roots[.savedRecordings]?.first)
        let store = RecordingLibraryStore(directory: folder)
        let inspector = RecordingLibraryInspector(thumbnailDirectory: caches.appendingPathComponent(RecordingLibraryInspector.thumbnailFolderName))
        let model = RecordingLibraryModel(store: store, inspector: inspector)
        let box = AnnouncedBox()
        model.announce = { (text: String) in box.texts.append(text) }
        return Fixture(container: container, locations: locations, store: store, inspector: inspector, model: model, box: box)
    }

    private func savedBytes(_ f: Fixture) throws -> Int64 {
        try StorageUsageCalculator().measure(f.locations.request).usage(.savedRecordings).contentBytes
    }

    // MARK: - REC-010-S1: the roadmap acceptance

    func testDeleteAfterConfirmationRemovesTheFileAndUpdatesTheListImmediately() async throws {
        let f = try fixture("delete")
        let urls = try RecordingLibraryFixture.seed(3, into: f.store)
        f.model.refresh()
        await f.model.waitForLoads()
        XCTAssertEqual(f.model.count, 3)
        let middle = f.model.items[1]
        XCTAssertEqual(middle.file.name, urls[1].lastPathComponent, "newest first: the middle row is the middle recording")
        XCTAssertNotNil(middle.thumbnail)
        let inspectorHasThumbnail = await f.inspector.hasCachedThumbnail(for: middle.file)
        XCTAssertTrue(inspectorHasThumbnail)
        let totalBefore = f.model.totalBytes
        let storageBefore = try savedBytes(f)
        XCTAssertEqual(storageBefore, totalBefore, "Storage measures the same folder")

        f.model.requestDelete(middle)
        XCTAssertEqual(f.model.pendingDelete, middle, "Delete asks first")
        XCTAssertEqual(f.model.count, 3, "nothing is removed before the confirmation")
        XCTAssertTrue(FileManager.default.fileExists(atPath: middle.file.url.path))
        XCTAssertTrue(RecordingLibraryModel.deleteMessage(middle).contains(middle.file.name))

        f.model.confirmDelete()
        // Same main-actor turn: no await between the confirmation and these reads.
        XCTAssertFalse(FileManager.default.fileExists(atPath: middle.file.url.path), "the file is gone from disk")
        XCTAssertEqual(f.model.count, 2, "the list shows two immediately")
        XCTAssertEqual(f.model.items.map(\.file.name), [urls[2].lastPathComponent, urls[0].lastPathComponent])
        XCTAssertEqual(f.model.totalBytes, totalBefore - middle.file.bytes)
        XCTAssertEqual(f.model.summaryText, "2 recordings, \(RecordingLibraryModel.format(totalBefore - middle.file.bytes))")
        XCTAssertNil(f.model.pendingDelete)
        XCTAssertEqual(try savedBytes(f), storageBefore - middle.file.bytes, "the storage total drops by its size")
        XCTAssertEqual(f.announced, [RecordingLibraryModel.deletedText])
        await f.model.waitForLoads()
        let stillCached = await f.inspector.hasCachedThumbnail(for: middle.file)
        XCTAssertFalse(stillCached, "the thumbnail cache entry is removed")
        f.model.refresh()
        XCTAssertEqual(f.model.count, 2, "a rescan agrees")
    }

    func testCancellingTheConfirmationKeepsTheFile() async throws {
        let f = try fixture("cancel")
        try RecordingLibraryFixture.seed(3, into: f.store)
        f.model.refresh()
        let middle = f.model.items[1]
        f.model.requestDelete(middle)
        f.model.cancelDelete()
        XCTAssertNil(f.model.pendingDelete)
        f.model.confirmDelete()   // nothing pending: no effect
        XCTAssertTrue(FileManager.default.fileExists(atPath: middle.file.url.path))
        XCTAssertEqual(f.model.count, 3)
        XCTAssertEqual(f.store.scan().count, 3)
        XCTAssertEqual(f.announced, [])
        await f.model.waitForLoads()
    }

    func testDeletingAFileThatIsAlreadyGoneStillRemovesTheRow() async throws {
        let f = try fixture("gone")
        try RecordingLibraryFixture.seed(2, into: f.store)
        f.model.refresh()
        let first = f.model.items[0]
        try FileManager.default.removeItem(at: first.file.url)
        f.model.requestDelete(first)
        f.model.confirmDelete()
        XCTAssertEqual(f.model.count, 1)
        XCTAssertNil(f.model.message)
        await f.model.waitForLoads()
    }

    // MARK: - S2 order, facts, S3 thumbnails, S4 Incomplete

    func testRowsAreNewestFirstThenByName() throws {
        let f = try fixture("order")
        let urls = try RecordingLibraryFixture.seed(3, into: f.store)
        XCTAssertEqual(f.store.scan().map(\.name), urls.reversed().map(\.lastPathComponent))
        let same = Date(timeIntervalSince1970: 1_800_000_000)
        for url in urls { try FileManager.default.setAttributes([.modificationDate: same], ofItemAtPath: url.path) }
        XCTAssertEqual(f.store.scan().map(\.name), ["Visualizer Recording 3.mp4", "Visualizer Recording 2.mp4", "Visualizer Recording 1.mp4"])
        try Data("hidden".utf8).write(to: f.store.directory.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(f.store.scan().count, 3, "hidden files are not listed")
        XCTAssertEqual(RecordingLibraryStore(directory: f.container.appendingPathComponent("missing")).scan(), [], "no folder: empty")
    }

    func testFactsComeFromTheHeader() async throws {
        let f = try fixture("facts")
        let urls = try RecordingLibraryFixture.seed(1, into: f.store)
        let read: RecordingFacts? = await RecordingLibraryInspector.facts(of: urls[0])
        let facts = try XCTUnwrap(read)
        XCTAssertEqual(facts.width, 64)
        XCTAssertEqual(facts.height, 64)
        XCTAssertEqual(facts.codec, "avc1")
        XCTAssertEqual(facts.codecText, "H.264")
        XCTAssertEqual(facts.durationSeconds, 2, accuracy: 0.05)
        XCTAssertEqual(facts.durationText, "0:02")
        XCTAssertEqual(facts.frameRateText, "10 fps")
        f.model.refresh()
        await f.model.waitForLoads()
        let label = RecordingLibraryModel.accessibilityLabel(f.model.items[0])
        XCTAssertTrue(label.hasPrefix("Visualizer Recording 1, 0:02, "), label)
        XCTAssertTrue(label.hasSuffix("64×64, 10 fps, H.264"), label)
    }

    func testThumbnailIsGeneratedOnceAndServedFromTheCache() async throws {
        let f = try fixture("thumb")
        try RecordingLibraryFixture.seed(1, into: f.store)
        let file = try XCTUnwrap(f.store.scan().first)
        XCTAssertEqual(RecordingLibraryInspector.thumbnailTime(durationSeconds: 2), 1)
        XCTAssertEqual(RecordingLibraryInspector.thumbnailTime(durationSeconds: 0.5), 0.25, "shorter than 1 s: half the duration")
        let first = await f.inspector.thumbnail(for: file, durationSeconds: 2)
        let data = try XCTUnwrap(first)
        XCTAssertNotNil(UIImage(data: data))
        _ = await f.inspector.thumbnail(for: file, durationSeconds: 2)
        let generated = await f.inspector.generatedCount
        XCTAssertEqual(generated, 1, "the second request comes from memory")
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.inspector.cacheURL(for: file.cacheKey).path))
        let fresh = RecordingLibraryInspector(thumbnailDirectory: f.inspector.thumbnailDirectory)
        let fromDisk = await fresh.thumbnail(for: file, durationSeconds: 2)
        let freshGenerated = await fresh.generatedCount
        XCTAssertEqual(fromDisk, data)
        XCTAssertEqual(freshGenerated, 0, "a new screen visit reads the cache folder")
    }

    func testAnUnreadableFileIsIncompleteWithDeleteOnly() async throws {
        let f = try fixture("incomplete")
        try RecordingLibraryFixture.seed(1, into: f.store)
        let broken = f.store.directory.appendingPathComponent("Visualizer Recording broken.mp4")
        try Data(repeating: 7, count: 4_096).write(to: broken)
        f.model.refresh()
        await f.model.waitForLoads()
        let row = try XCTUnwrap(f.model.items.first { (item: RecordingLibraryItem) -> Bool in item.file.url.lastPathComponent == broken.lastPathComponent })
        XCTAssertEqual(row.state, .incomplete)
        XCTAssertNil(row.facts, "no Play, Share or Rename")
        XCTAssertNil(row.thumbnail)
        XCTAssertEqual(RecordingLibraryModel.accessibilityLabel(row), "Visualizer Recording broken, Incomplete, \(RecordingLibraryModel.format(4_096))")
        f.model.requestDelete(row)
        f.model.confirmDelete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: broken.path))
        XCTAssertEqual(f.model.count, 1)
        await f.model.waitForLoads()
    }

    // MARK: - Keep (contract C1) and rename (C5)

    func testKeepMovesTheOfferedRecordingIntoTheLibrary() async throws {
        let f = try fixture("keep")
        let temp = f.container.appendingPathComponent("tmp/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let offered = temp.appendingPathComponent("Visualizer Recording 1.mp4")
        let recording = VideoRecordingCoordinator(directory: temp, debugDirectory: nil, checkInterval: nil, storageCheckInterval: nil,
                                                  library: f.store) { () -> VideoRecordingCoordinator.Context in
            VideoRecordingCoordinator.Context(source: nil, visualShown: false, outputLive: false, paused: false)
        }
        try RecordingLibraryFixture.writeVideo(to: offered)   // after the init, which sweeps leftovers (REC-003-R13)
        var kept: [String] = []
        recording.onKept = { (text: String) in kept.append(text) }
        recording.offerForTests(offered)
        let url = try XCTUnwrap(recording.keepOffered())
        XCTAssertNil(recording.offered, "the offer closes")
        XCTAssertEqual(recording.notice, VideoRecordingCoordinator.keptNotice)
        XCTAssertEqual(kept, ["Recording kept in Recordings."])
        XCTAssertFalse(FileManager.default.fileExists(atPath: offered.path), "moved, not copied")
        XCTAssertEqual(url.lastPathComponent, "Visualizer Recording 1.mp4")

        // A second recording of the same name gets " 2".
        try RecordingLibraryFixture.writeVideo(to: offered)
        recording.offerForTests(offered)
        XCTAssertEqual(recording.keepOffered()?.lastPathComponent, "Visualizer Recording 1 2.mp4")
        f.model.refresh()
        XCTAssertEqual(f.model.count, 2)
        await f.model.waitForLoads()
    }

    func testRenameRulesKeepTheExtension() async throws {
        let f = try fixture("rename")
        try RecordingLibraryFixture.seed(2, into: f.store)
        f.model.refresh()
        await f.model.waitForLoads()
        let item = try XCTUnwrap(f.model.items.first { (row: RecordingLibraryItem) -> Bool in row.file.name == "Visualizer Recording 1.mp4" })
        XCTAssertEqual(f.model.rename(item, to: "  "), "Enter a name.")
        XCTAssertEqual(f.model.rename(item, to: "a/b"), "Names can't contain / or :.")
        XCTAssertEqual(f.model.rename(item, to: "a:b"), "Names can't contain / or :.")
        XCTAssertEqual(f.model.rename(item, to: ".hidden"), "Names can't start with a dot.")
        XCTAssertEqual(f.model.rename(item, to: String(repeating: "x", count: 101)), "Use at most 100 characters.")
        XCTAssertEqual(f.model.rename(item, to: "visualizer recording 2"), "A recording with that name exists.")
        XCTAssertEqual(f.announced, [], "a refusal changes nothing")
        XCTAssertNil(f.model.rename(item, to: "Opening set"))
        XCTAssertEqual(Set(f.store.scan().map(\.name)), ["Opening set.mp4", "Visualizer Recording 2.mp4"])
        XCTAssertEqual(f.announced, [RecordingLibraryModel.renamedText])
        await f.model.waitForLoads()
        let oldCached = await f.inspector.hasCachedThumbnail(for: item.file)
        XCTAssertFalse(oldCached, "the old cache entry is removed")
        XCTAssertEqual(f.model.items.first { (row: RecordingLibraryItem) -> Bool in row.file.name == "Opening set.mp4" }?.facts?.codec, "avc1")
    }

    // MARK: - S5 storage and erase

    func testClearCachesNeverPlansTheLibraryAndEraseRemovesIt() throws {
        let f = try fixture("erase")
        try RecordingLibraryFixture.seed(2, into: f.store)
        XCTAssertFalse(StorageCategory.savedRecordings.isCleanable)
        XCTAssertTrue(f.locations.protectedRoots.contains(f.store.directory))
        let plan = try CacheCleaner().plan(f.locations.cleanupRequest(inUse: []))
        let library = f.store.directory.standardizedFileURL.resolvingSymlinksInPath().path
        XCTAssertFalse(plan.items.contains { (item: CacheCleanupItem) -> Bool in item.path.hasPrefix(library) }, "Clear Caches keeps saved recordings")

        let support = f.store.directory.deletingLastPathComponent()
        let inventory = LibraryEraseInventory.measure(root: support, settings: [:])
        XCTAssertEqual(inventory.item(.recordings).count, 2)
        XCTAssertGreaterThan(inventory.item(.recordings).bytes ?? 0, 0)
        let erasePlan = LibraryErasePlanner.plan([.recordings], root: support, settings: [:])
        XCTAssertEqual(erasePlan.folders, [RecordingLibraryStore.folderName])
        XCTAssertEqual(erasePlan.settingKeys, [])
        XCTAssertEqual(LibraryEraseCategory.recordings.title, "Saved recordings")
    }
}
