// BulkPresetImportCoordinatorTests.swift — PRE-013-T14 (specs/174-pre-013-bulk-import; R1, R7-R10,
// R14): "Import Folder or Archive…" through the app's coordinators. A real UserPresetLibrary in a
// temporary folder and a passing trial; the folder is written here. No main-actor state is touched in
// setUp or tearDown. The exact-count acceptance is in PresetLibrary's BulkImportAcceptanceTests.
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class BulkPresetImportCoordinatorTests: XCTestCase {
    private struct PassingTrial: PresetTrialRunning {
        func run(_ contents: Data, timeout: Duration) async -> PresetTrialResult { .passed }
    }

    private final class Spoken {
        var general: [String] = []
        var library: [String] = []
    }

    private struct Harness {
        let base: URL
        let coordinator: UserPresetsCoordinator
        let spoken: Spoken
    }

    private func harness() async throws -> Harness {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("BulkPresetImportCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let library = UserPresetLibrary(directory: base.appendingPathComponent("UserPresets"))
        let spoken = Spoken()
        let coordinator = UserPresetsCoordinator(library: library, announce: { (text: String) in spoken.general.append(text) },
                                                 exportDirectory: base.appendingPathComponent("PresetExport"),
                                                 libraryRoots: [base.appendingPathComponent("UserPresets")])
        coordinator.announceLibrary = { (text: String) in spoken.library.append(text) }
        await coordinator.load()
        await coordinator.rendererReady(trial: PassingTrial(), presentedFrames: { () -> Int in 0 })
        return Harness(base: base, coordinator: coordinator, spoken: spoken)
    }

    private func preset(_ tag: Int) -> String {
        ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.96", "zoom=1.0\(tag)",
         "per_frame_1=rot = 0.0\(tag)*sin(time);", ""].joined(separator: "\n")
    }

    /// 8 files: 5 valid, 1 copy, 1 without a header, 1 text file.
    private func writeFolder(_ h: Harness, name: String = "Pack", valid: Int = 5) throws -> URL {
        let folder = h.base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for tag in 0..<valid { try Data(preset(tag + 1).utf8).write(to: folder.appendingPathComponent("P\(tag).milk")) }
        try Data(preset(1).utf8).write(to: folder.appendingPathComponent("Copy.milk"))
        try Data("zoom=1.5\n".utf8).write(to: folder.appendingPathComponent("Broken.milk"))
        try Data("notes\n".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        return folder
    }

    private func files(under url: URL) -> [String] {
        let paths = FileManager.default.enumerator(atPath: url.path)?.compactMap { $0 as? String } ?? []
        return paths.sorted()
    }

    func testImportAnnouncesStartQuartersAndSummaryOnTheLibraryLane() async throws {
        let h = try await harness()
        let folder = try writeFolder(h)
        let started = await h.coordinator.bulk.start(.folder(folder))
        let report = try XCTUnwrap(started)
        let summary = "Added 5. Skipped 3: 1 duplicate, 1 invalid, 1 not a preset. Failed 0."
        XCTAssertEqual(report.summary, summary)
        XCTAssertEqual(h.spoken.library, ["Importing Pack: 8 files.",
                                          "25 percent imported, 2 of 8 files.",
                                          "50 percent imported, 4 of 8 files.",
                                          "75 percent imported, 6 of 8 files.",
                                          summary])
        XCTAssertTrue(h.spoken.general.isEmpty, "nothing outside the library lane")
        XCTAssertEqual(h.coordinator.bulk.report, report, "the summary sheet shows the report")
        XCTAssertFalse(h.coordinator.bulk.isRunning)
        // The waiting presets were tried after the import and are playable.
        XCTAssertEqual(h.coordinator.playable.count, 5)
        XCTAssertTrue(h.coordinator.pending.isEmpty)
        h.coordinator.bulk.dismissReport()
        XCTAssertNil(h.coordinator.bulk.report)
    }

    func testOtherChangesAreExcludedWhileABulkImportRuns() async throws {
        let h = try await harness()
        let folder = try writeFolder(h)
        var exportOfferedDuringRun: [Bool] = []
        var runningDuringRun: [Bool] = []
        let coordinator = h.coordinator
        coordinator.announceLibrary = { (text: String) in
            h.spoken.library.append(text)
            if text.hasPrefix("Importing") {
                exportOfferedDuringRun.append(coordinator.canExport)
                runningDuringRun.append(coordinator.bulk.isRunning)
            }
        }
        _ = await coordinator.bulk.start(.folder(folder))
        XCTAssertEqual(exportOfferedDuringRun, [false])
        XCTAssertEqual(runningDuringRun, [true])
        XCTAssertTrue(coordinator.canExport, "offered again after the run")

        // An archive preview open: a bulk import does not start.
        let archive = h.base.appendingPathComponent("fixture.zip")
        try XCTUnwrap(UserPresetsCoordinator.fixtureArchive()).write(to: archive)
        await coordinator.previewArchive(at: archive)
        XCTAssertNotNil(coordinator.archiveReview)
        let refused = await coordinator.bulk.start(.folder(folder))
        XCTAssertNil(refused)
        coordinator.cancelArchive()
    }

    func testCancelKeepsWhatWasAddedAndWritesNothingElse() async throws {
        let h = try await harness()
        let folder = try writeFolder(h, name: "Big", valid: 60)
        let outside: [String] = files(under: h.base).filter { (path: String) -> Bool in !path.hasPrefix("UserPresets") }
        let defaultsBefore = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.lowercased().contains("bulk") }
        let coordinator = h.coordinator
        coordinator.announceLibrary = { (text: String) in
            h.spoken.library.append(text)
            if text.hasPrefix("25 percent") { coordinator.bulk.cancel() }
        }
        let started = await coordinator.bulk.start(.folder(folder))
        let report = try XCTUnwrap(started)
        // Cancel reaches the importer between files; however far it got, the counts are consistent.
        XCTAssertEqual(report.total, 63)
        XCTAssertEqual(report.counts.handled + report.notHandled, 63)
        XCTAssertEqual(report.items.count, report.counts.handled)
        let stored = Set(coordinator.playable.map(\.id) + coordinator.pending.map(\.id))
        XCTAssertEqual(stored, Set(report.items.compactMap(\.presetID)), "every added file is stored, and no other")
        if report.cancelled {
            XCTAssertTrue(report.summary.hasPrefix("Import cancelled after"), report.summary)
            XCTAssertEqual(h.spoken.library.last, report.summary)
        }
        // R14: nothing about the run is written outside the user preset store.
        XCTAssertEqual(files(under: h.base).filter { (path: String) -> Bool in !path.hasPrefix("UserPresets") }, outside)
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.lowercased().contains("bulk") }, defaultsBefore)
    }

    func testProgressText() {
        let progress = BulkImportProgress(handled: 1_200, total: 2_000,
                                          counts: BulkImportCounts(added: 1_000, duplicate: 150, invalid: 10, tooLarge: 0, unsupported: 2, failed: 3))
        XCTAssertEqual(BulkPresetImportCoordinator.progressText(progress), "1,200 of 2,000 files. Added 1,000, skipped 162, failed 3.")
        XCTAssertEqual(BulkPresetImportCoordinator.pickerTypes.map(\.identifier), ["public.folder", "public.zip-archive"])
    }
}
