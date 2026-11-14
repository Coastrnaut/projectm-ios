// StorageLocationsTests.swift — FILE-009-T06, T10: the Storage categories measure the folders the stores
// really use (FILE-009-R2, S2), and the screen model shows only the newest measurement (R5).
import CaptureKit
import Foundation
import LibraryBackup
import LocalPortability
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class StorageLocationsTests: XCTestCase {
    private func path(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    func testStandardLocationsAreTheStoresOwnDirectories() throws {
        let locations = StorageLocations.standard()
        func roots(_ category: StorageCategory) -> [String] { (locations.roots[category] ?? []).map(path) }
        XCTAssertEqual(roots(.photos), [path(try PhotoStore.defaultDirectory())])
        XCTAssertEqual(roots(.videos), [path(try VideoStore.defaultDirectory())])
        XCTAssertEqual(roots(.scenes), [path(try SceneAutosaveStore.defaultDirectory())])
        XCTAssertEqual(roots(.presets), [path(UserPresetStore.defaultDirectory()), path(PresetCollectionStore.defaultDirectory())])
        XCTAssertEqual(roots(.importedAudio), [path(try AudioLibrary.defaultDirectory())])
        XCTAssertEqual(roots(.recordings), [path(VideoRecordingCoordinator.defaultDirectory)])
        XCTAssertEqual(roots(.savedRecordings), [path(RecordingLibraryStore.defaultDirectory)])   // REC-010
        XCTAssertEqual(RecordingLibraryStore.folderName, LibraryErasePolicy.recordingLibraryFolderName)
        let temporary = FileManager.default.temporaryDirectory
        XCTAssertEqual(roots(.sharesAndExports), [path(ShareFileStore.defaultDirectory),
                                                  path(temporary.appendingPathComponent(SceneArchiveService.exportFolderName)),
                                                  path(UserPresetsCoordinator.defaultExportDirectory)])
        XCTAssertEqual(roots(.caches), [path(try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first))])
        XCTAssertNil(locations.roots[.otherAppData])
        // Every folder lies inside the container.
        let container = path(locations.container) + "/"
        for (_, urls) in locations.roots {
            for url in urls { XCTAssertTrue(path(url).hasPrefix(container), path(url)) }
        }
    }

    func testEachBaselineFolderIsCountedInExactlyItsCategory() throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("StorageLocationsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let locations = StorageLocations.make(
            applicationSupport: container.appendingPathComponent("Library/Application Support", isDirectory: true),
            temporary: container.appendingPathComponent("tmp", isDirectory: true),
            caches: container.appendingPathComponent("Library/Caches", isDirectory: true),
            container: container)
        // A distinct size per folder: 1,000 × (index + 1) bytes.
        var expected: [StorageCategory: Int64] = [:]
        var index = 0
        for category in StorageCategory.allCases where category != .otherAppData {
            for folder in locations.roots[category] ?? [] {
                index += 1
                let size = 1_000 * index
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data(repeating: 1, count: size).write(to: folder.appendingPathComponent("file.bin"))
                expected[category, default: 0] += Int64(size)
            }
        }
        let other = container.appendingPathComponent("Library/Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 777).write(to: other.appendingPathComponent("settings.plist"))
        expected[.otherAppData] = 777

        let report = try StorageUsageCalculator().measure(locations.request)
        for category in StorageCategory.allCases {
            XCTAssertEqual(report.usage(category).contentBytes, expected[category] ?? 0, category.title)
        }
        XCTAssertEqual(report.usage(.presets).fileCount, 2)
        XCTAssertEqual(report.usage(.sharesAndExports).fileCount, 3)
        XCTAssertEqual(report.total.fileCount, 13)   // REC-010: one more folder (Saved recordings)
        XCTAssertEqual(report.total.contentBytes, StorageCategory.allCases.reduce(Int64(0)) { (sum: Int64, c: StorageCategory) -> Int64 in
            sum + (expected[c] ?? 0)
        })
        XCTAssertTrue(report.isComplete)
    }

    // MARK: Model (FILE-009-T10)

    /// Every folder holds 50 files and one sub-folder, without end: only cancellation ends a walk.
    private struct EndlessTree: StorageDirectoryReading {
        func kind(atPath path: String) -> StorageEntry.Kind? { .directory }
        func entries(inDirectory path: String) throws -> [StorageEntry] {
            (0..<50).map { (i: Int) -> StorageEntry in StorageEntry(name: "f\(i)", kind: .file, contentBytes: 1) }
                + [StorageEntry(name: "d", kind: .directory)]
        }
        func resolvedPath(_ path: String) -> String { path }
    }

    private func endlessModel() -> StorageUsageModel {
        let locations = StorageLocations(container: URL(fileURLWithPath: "/c"), roots: [.photos: [URL(fileURLWithPath: "/c/P")]])
        return StorageUsageModel(locations: locations,
                                 calculator: StorageUsageCalculator(reader: EndlessTree(),
                                                                    limits: StorageWalkLimits(maxDepth: Int.max, maxEntriesPerWalk: Int.max)))
    }

    func testLeavingTheScreenCancelsTheMeasurement() async throws {
        let model = endlessModel()
        model.refresh()
        XCTAssertTrue(model.isMeasuring)
        let work = try XCTUnwrap(model.work)
        model.cancel()
        XCTAssertFalse(model.isMeasuring)
        do {
            _ = try await work.value
            XCTFail("an endless walk only ends by cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNil(model.report)
    }

    func testRefreshCancelsTheEarlierMeasurementAndOnlyTheNewestResultIsShown() async throws {
        let model = endlessModel()
        model.refresh()
        let first = try XCTUnwrap(model.work)
        let firstGeneration = model.currentGeneration
        model.refresh()
        XCTAssertTrue(first.isCancelled, "a newer request cancels the older one")
        // A late result from the first request is dropped; the newest is shown.
        let stale = StorageReport(usages: [.photos: StorageUsage(contentBytes: 1, spaceUsed: 1, fileCount: 1)], isComplete: true, skippedRoots: [])
        model.finish(stale, generation: firstGeneration)
        XCTAssertNil(model.report)
        XCTAssertTrue(model.isMeasuring)
        let newest = StorageReport(usages: [.photos: StorageUsage(contentBytes: 2, spaceUsed: 2, fileCount: 1)], isComplete: true, skippedRoots: [])
        model.finish(newest, generation: model.currentGeneration)
        XCTAssertEqual(model.report, newest)
        XCTAssertFalse(model.isMeasuring)
        model.cancel()
        _ = try? await first.value
    }
}
