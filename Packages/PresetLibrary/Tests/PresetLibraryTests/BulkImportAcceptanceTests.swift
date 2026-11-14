// BulkImportAcceptanceTests.swift — PRE-013-T08, T12, T13 (specs/174-pre-013-bulk-import; S1-S4):
// the roadmap acceptance "Fixture of 100 files reports exact added/skipped counts" from a folder and
// from a zip, cancel, zip slip, bounds and a failing batch. The fixture is generated in the temporary
// folder (BulkImportFixture).
import Foundation
import LocalPortability
import XCTest
@testable import PresetLibrary

final class BulkImportAcceptanceTests: XCTestCase {
    private let expected = BulkImportCounts(added: 70, duplicate: 15, invalid: 8, tooLarge: 4, unsupported: 3, failed: 0)
    private let expectedSummary = "Added 70. Skipped 30: 15 duplicates, 8 invalid, 4 too large, 3 not presets. Failed 0."

    /// The store's records and every file under its directory.
    private func storeContents(_ library: UserPresetLibrary) async -> [UserPreset] {
        let snapshot = await library.snapshot
        return snapshot.playable + snapshot.pending + snapshot.quarantined + snapshot.needsUnlock
    }

    private func assertAcceptance(_ report: BulkImportReport, library: UserPresetLibrary, before: [UserPreset],
                                  hidden: Int, file: StaticString = #filePath, line: UInt = #line) async {
        XCTAssertNil(report.refusal, file: file, line: line)
        XCTAssertFalse(report.cancelled, file: file, line: line)
        XCTAssertEqual(report.total, 100, file: file, line: line)
        XCTAssertEqual(report.counts, expected, file: file, line: line)
        XCTAssertEqual(report.counts.handled, 100, file: file, line: line)
        XCTAssertEqual(report.notHandled, 0, file: file, line: line)
        XCTAssertEqual(report.hiddenCount, hidden, file: file, line: line)
        XCTAssertEqual(report.items.count, 100, "one item per file", file: file, line: line)
        XCTAssertEqual(Set(report.items.map(\.path)).count, 100, file: file, line: line)
        for kind in BulkImportKind.allCases {
            XCTAssertEqual(report.items.filter { $0.kind == kind }.count, expected[kind], "\(kind)", file: file, line: line)
        }
        XCTAssertTrue(report.summary.hasPrefix(expectedSummary), report.summary, file: file, line: line)
        // The store holds exactly the 5 seeded and the 70 new presets.
        let after = await storeContents(library)
        let beforeIDs = Set(before.map(\.id))
        let newIDs = Set(after.map(\.id)).subtracting(beforeIDs)
        XCTAssertEqual(after.count, 75, file: file, line: line)
        XCTAssertTrue(beforeIDs.isSubset(of: Set(after.map(\.id))), file: file, line: line)
        XCTAssertEqual(newIDs, Set(report.items.compactMap(\.presetID)), file: file, line: line)
        XCTAssertEqual(Set(after.filter { newIDs.contains($0.id) }.map(\.sha256)).count, 70, "70 different texts", file: file, line: line)
        XCTAssertTrue(after.filter { newIDs.contains($0.id) }.allSatisfy { $0.state == .pending }, "waiting for the trial", file: file, line: line)
        // Per-file details.
        let byPath = Dictionary(uniqueKeysWithValues: report.items.map { ($0.path, $0) })
        XCTAssertEqual(byPath["Already 0.MILK"]?.detail, "Already in My Presets as “Seed 0”.", file: file, line: line)
        // "Copies/…" sorts before "Subfolder/…": the copy is added, the original is its duplicate.
        XCTAssertEqual(byPath["Copies/Copy of 3.milk"]?.detail, "Added as “Copy of 3”.", file: file, line: line)
        XCTAssertEqual(byPath["Subfolder/Artist - Valid 3.milk"]?.detail, "Same as “Copies/Copy of 3.milk” in this import.", file: file, line: line)
        XCTAssertEqual(byPath["Artist - Valid 30.milk"]?.detail, "Added as “Valid 30”.", file: file, line: line)
        XCTAssertEqual(byPath["notes.txt"]?.kind, .unsupported, file: file, line: line)
        XCTAssertEqual(byPath["Huge 2.milk"]?.kind, .tooLarge, file: file, line: line)
        XCTAssertEqual(byPath["Broken/Broken 5.milk"]?.kind, .invalid, file: file, line: line)
    }

    // MARK: - S1: folder

    func testFolderOf100FilesReportsExactCounts() async throws {
        let temp = try BulkImportFixture.temporaryFolder(self)
        let library = try await BulkImportFixture.seededLibrary(in: temp)
        let before = await storeContents(library)
        XCTAssertEqual(before.count, 5)
        let folder = try BulkImportFixture.writeFolder(BulkImportFixture.files() + [BulkImportFixture.hidden], in: temp)
        let report = await BulkPresetImporter.run(.folder(folder), library: library)
        await assertAcceptance(report, library: library, before: before, hidden: 1)
        XCTAssertEqual(report.sourceName, "Preset Pack")
        XCTAssertEqual(report.summary, expectedSummary + " 1 hidden item was not opened.")
        // Path order is byte-wise ("Already" < "Artist" < "Broken/…" < "Copies/…" < "Huge" < "Subfolder/…" < "cover.jpg").
        XCTAssertEqual(report.items.first?.path, "Already 0.MILK")
        XCTAssertEqual(report.items.last?.path, "notes.txt")
        // The picked folder is untouched.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 65)
    }

    // MARK: - S2: zip

    func testStoredZipReportsTheSameCounts() async throws {
        try await zipRun(method: 0)
    }

    func testDeflatedZipReportsTheSameCounts() async throws {
        guard RawZip.canDeflate, LooseZipReader.readsDeflate else { throw XCTSkip("no Compression framework on this platform") }
        try await zipRun(method: 8)
    }

    private func zipRun(method: Int) async throws {
        let temp = try BulkImportFixture.temporaryFolder(self)
        let library = try await BulkImportFixture.seededLibrary(in: temp)
        let before = await storeContents(library)
        let archive = temp.appendingPathComponent("Preset Pack.zip")
        try BulkImportFixture.writeArchive(BulkImportFixture.files(), to: archive, method: method)
        XCTAssertEqual(BulkImportSource.picked(archive), .archive(archive))
        let report = await BulkPresetImporter.run(.archive(archive), library: library)
        await assertAcceptance(report, library: library, before: before, hidden: 1)
        XCTAssertEqual(report.sourceName, "Preset Pack.zip")
    }

    // MARK: - S3: cancel

    func testCancelAfter30FilesKeepsExactlyWhatWasAdded() async throws {
        let temp = try BulkImportFixture.temporaryFolder(self)
        let library = try await BulkImportFixture.seededLibrary(in: temp)
        let before = await storeContents(library)
        let folder = try BulkImportFixture.writeFolder(BulkImportFixture.files(), in: temp)
        let cancel = CancelAfter(30)
        let report = await BulkPresetImporter.run(.folder(folder), library: library,
                                                  isCancelled: { cancel.isCancelled() }, progress: { cancel.progress($0) })
        XCTAssertTrue(report.cancelled)
        XCTAssertEqual(report.counts.handled, 30)
        XCTAssertEqual(report.items.count, 30)
        XCTAssertEqual(report.notHandled, 70)
        XCTAssertEqual(report.items.map(\.path), Array(report.items.map(\.path).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }))
        let after = await storeContents(library)
        let newIDs = Set(after.map(\.id)).subtracting(before.map(\.id))
        XCTAssertGreaterThan(report.counts.added, 0)
        XCTAssertEqual(newIDs.count, report.counts.added, "every added file is stored, and no other")
        XCTAssertEqual(newIDs, Set(report.items.compactMap(\.presetID)))
        XCTAssertTrue(report.summary.hasPrefix("Import cancelled after 30 of 100 files. Added \(report.counts.added)."), report.summary)
        XCTAssertTrue(report.summary.hasSuffix("70 files were not handled."), report.summary)

        // Importing again finishes the job: the first run's presets are now duplicates.
        let again = await BulkPresetImporter.run(.folder(folder), library: library)
        XCTAssertEqual(again.counts.added, 70 - report.counts.added)
        XCTAssertEqual(again.counts.duplicate, 15 + report.counts.added)
        XCTAssertEqual(again.counts.handled, 100)
        let final = await storeContents(library)
        XCTAssertEqual(final.count, 75)
    }

    func testCancelBeforeTheFirstFileAddsNothing() async throws {
        let temp = try BulkImportFixture.temporaryFolder(self)
        let library = UserPresetLibrary(directory: temp.appendingPathComponent("UserPresets"))
        let folder = try BulkImportFixture.writeFolder(BulkImportFixture.files(), in: temp)
        let report = await BulkPresetImporter.run(.folder(folder), library: library, isCancelled: { true })
        XCTAssertTrue(report.cancelled)
        XCTAssertEqual(report.counts.handled, 0)
        XCTAssertEqual(report.notHandled, 100)
        let after = await storeContents(library)
        XCTAssertTrue(after.isEmpty)
    }

    // MARK: - S4: zip slip

    func testZipSlipEntriesAreSkippedAndNothingIsWrittenOutsideTheStore() async throws {
        let temp = try BulkImportFixture.temporaryFolder(self)
        let storeDirectory = temp.appendingPathComponent("UserPresets", isDirectory: true)
        let library = UserPresetLibrary(directory: storeDirectory)
        var zip = RawZip()
        zip.add("../evil.milk", text: BulkImportFixture.valid(1))
        zip.add("../../evil2.milk", text: BulkImportFixture.valid(2))
        zip.add("/tmp/abs.milk", text: BulkImportFixture.valid(3))
        zip.add("dir\\back.milk", text: BulkImportFixture.valid(4))
        zip.add("fine/ok.milk", text: BulkImportFixture.valid(5))
        let archive = temp.appendingPathComponent("inner", isDirectory: true).appendingPathComponent("slip.zip")
        try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        try zip.build().write(to: archive)
        let report = await BulkPresetImporter.run(.archive(archive), library: library)
        XCTAssertEqual(report.counts, BulkImportCounts(added: 1, duplicate: 0, invalid: 0, tooLarge: 0, unsupported: 4, failed: 0))
        for item in report.items where item.kind == .unsupported {
            XCTAssertEqual(item.detail, "Its name points outside the archive's folder.", item.path)
        }
        // Nothing appeared next to the archive or above it; the store holds only content-addressed files.
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: temp.path)), ["UserPresets", "inner"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: archive.deletingLastPathComponent().path), ["slip.zip"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/abs.milk"))
        let stored = try FileManager.default.contentsOfDirectory(atPath: storeDirectory.appendingPathComponent("files").path)
        XCTAssertEqual(stored.count, 1)
        XCTAssertTrue(stored.allSatisfy(UserPresetStore.isStoredFileName))
    }

    // MARK: - Bounds and failures

    func testOverTheBoundsNothingIsImported() async throws {
        let temp = try BulkImportFixture.temporaryFolder(self)
        let library = UserPresetLibrary(directory: temp.appendingPathComponent("UserPresets"))
        let folder = try BulkImportFixture.writeFolder(BulkImportFixture.files(), in: temp)
        var limits = BulkImportLimits.standard
        limits.maxFiles = 99
        let tooMany = await BulkPresetImporter.run(.folder(folder), library: library, limits: limits)
        XCTAssertEqual(tooMany.refusal, "It has more than 99 files.")
        XCTAssertEqual(tooMany.summary, "Nothing was imported. It has more than 99 files.")
        limits = .standard
        limits.maxTotalBytes = 10_000
        let tooBig = await BulkPresetImporter.run(.folder(folder), library: library, limits: limits)
        XCTAssertNotNil(tooBig.refusal)
        let after = await storeContents(library)
        XCTAssertTrue(after.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("UserPresets/index.json").path))
    }

    func testLinksAndDeepFoldersAreNotFollowed() async throws {
        let temp = try BulkImportFixture.temporaryFolder(self)
        let library = UserPresetLibrary(directory: temp.appendingPathComponent("UserPresets"))
        let outside = temp.appendingPathComponent("outside.milk")
        try Data(BulkImportFixture.valid(7).utf8).write(to: outside)
        var deep = "Deep"
        for level in 1...9 { deep += "/L\(level)" }
        let folder = try BulkImportFixture.writeFolder([.init(path: "top.milk", data: Data(BulkImportFixture.valid(8).utf8)),
                                                       .init(path: deep + "/buried.milk", data: Data(BulkImportFixture.valid(9).utf8))],
                                                      in: temp)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.milk"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked folder"), withDestinationURL: temp)
        let report = await BulkPresetImporter.run(.folder(folder), library: library)
        XCTAssertEqual(report.counts.added, 1)
        XCTAssertEqual(report.counts.unsupported, 2, "two links, neither followed")
        XCTAssertEqual(report.foldersNotOpened, 1)
        XCTAssertTrue(report.summary.hasSuffix("1 deeper folder was not opened."), report.summary)
    }

    func testAFailingBatchTurnsItsFilesIntoFailures() async throws {
        let temp = try BulkImportFixture.temporaryFolder(self)
        let library = UserPresetLibrary(directory: temp.appendingPathComponent("UserPresets"))
        _ = await library.load()
        let folder = try BulkImportFixture.writeFolder((0..<3).map { .init(path: "P\($0).milk", data: Data(BulkImportFixture.valid($0).utf8)) },
                                                      in: temp)
        await library.setStoreFault { (operation: UserPresetStore.FileOperation, _: URL) throws in
            if operation == .write { throw UserPresetStore.StoreError.saveFailed }
        }
        let report = await BulkPresetImporter.run(.folder(folder), library: library)
        XCTAssertEqual(report.counts, BulkImportCounts(added: 0, duplicate: 0, invalid: 0, tooLarge: 0, unsupported: 0, failed: 3))
        XCTAssertTrue(report.items.allSatisfy { $0.detail == "Could not be saved." })
        await library.setStoreFault(nil)
        let after = await storeContents(library)
        XCTAssertTrue(after.isEmpty)
    }

    func testLibraryFullFailsTheRest() async throws {
        let temp = try BulkImportFixture.temporaryFolder(self)
        let library = UserPresetLibrary(directory: temp.appendingPathComponent("UserPresets"))
        let files: [BulkImportFixture.File] = (0..<5).map { .init(path: "P\($0).milk", data: Data(BulkImportFixture.valid($0).utf8)) }
        let folder = try BulkImportFixture.writeFolder(files, in: temp)
        var limits = BulkImportLimits.standard
        limits.maxLibraryPresets = 3   // the real cap is 1,000 (PRE-012-R27); the rule is the same
        limits.batchSize = 2
        let report = await BulkPresetImporter.run(.folder(folder), library: library, limits: limits)
        XCTAssertEqual(report.counts, BulkImportCounts(added: 3, duplicate: 0, invalid: 0, tooLarge: 0, unsupported: 0, failed: 2))
        XCTAssertEqual(report.items.filter { $0.kind == .failed }.map(\.path), ["P3.milk", "P4.milk"])
        XCTAssertTrue(report.items.filter { $0.kind == .failed }.allSatisfy { $0.detail == "My Presets is full (3 presets)." })
        let after = await storeContents(library)
        XCTAssertEqual(after.count, 3)
    }

    // MARK: - Words

    func testSummaryWords() {
        XCTAssertEqual(BulkImportText.counts(BulkImportCounts()), "Added 0. Skipped 0. Failed 0.")
        XCTAssertEqual(BulkImportText.counts(BulkImportCounts(added: 1, duplicate: 1, invalid: 0, tooLarge: 0, unsupported: 1, failed: 2)),
                       "Added 1. Skipped 2: 1 duplicate, 1 not a preset. Failed 2.")
        XCTAssertEqual(BulkImportText.quarter(handled: 24, total: 100), 0)
        XCTAssertEqual(BulkImportText.quarter(handled: 25, total: 100), 1)
        XCTAssertEqual(BulkImportText.quarter(handled: 100, total: 100), 3)
        XCTAssertEqual(BulkImportText.start(sourceName: "Pack", total: 1_200), "Importing Pack: 1,200 files.")
    }
}
