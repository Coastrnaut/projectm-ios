// PRE-014-T14: what an export leaves out and why (ADR-0008; PRE-014-R2, R5, R6, R18; S2, S6),
// and that a failed export leaves no file and changes nothing in the store.
import LocalPortability
import XCTest
@testable import PresetLibrary

final class UserPresetExportTests: XCTestCase {
    private typealias X = ExportFixtures
    private var directory: URL!
    private var folder: URL!
    private var output: URL!

    override func setUpWithError() throws {
        let base = try UserPresetFixtures.tempDirectory(self)
        directory = base.appendingPathComponent("UserPresets")
        folder = base.appendingPathComponent("picked")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        output = base.appendingPathComponent("export.zip")
    }

    /// An import, an Included copy, a pack copy edited while unlocked, a second pack copy, a
    /// quarantined file and a waiting preset; the library ends locked or unlocked.
    private func mixedLibrary(unlockedAtEnd: Bool) async throws -> (UserPresetLibrary, imported: UserPreset, included: UserPreset) {
        let ids = CountingIDs()
        let library = await X.library(directory, ids: ids, unlocked: true)
        let imported = try await X.importFile(library, named: "Mine.milk", text: X.text("mine"), in: folder)
        let includedText = X.text("included")
        let included = try await X.duplicate(library, X.source("Alpha", text: includedText, packID: "included", locked: false), text: includedText)
        let packText = X.text("pack")
        let pack = try await X.duplicate(library, X.source("Gamma", text: packText, packID: "cream-of-the-crop", locked: true), text: packText)
        guard case .saved = await library.edit(pack.id, name: "Gamma, mine now", text: X.text("pack-edited"), expectedSHA256: pack.sha256) else {
            throw NSError(domain: "fixture", code: 4)
        }
        let otherPack = X.text("pack-two")
        try await X.duplicate(library, X.source("Delta", text: otherPack, packID: "cream-of-the-crop", locked: true), text: otherPack)
        let quarantined = try await X.importFile(library, named: "Broken.milk", text: UserPresetFixtures.preset(header: ""), in: folder)
        XCTAssertEqual(quarantined.state, .quarantined)
        await library.setTrial(nil)
        let waiting = try await X.importFile(library, named: "Later.milk", text: X.text("later"), in: folder)
        XCTAssertEqual(waiting.state, .pending)
        await library.setLibraryUnlocked(unlockedAtEnd)
        return (library, imported, included)
    }

    func testPlanListsOnlyImportsAndIncludedCopiesWhateverTheEntitlement() async throws {
        for unlocked in [true, false] {
            try? FileManager.default.removeItem(at: directory)
            let (library, imported, included) = try await mixedLibrary(unlockedAtEnd: unlocked)
            let plan = await library.exportPlan()
            XCTAssertEqual(Set(plan.exportable.map(\.id)), [imported.id, included.id], "unlocked: \(unlocked)")
            XCTAssertEqual(plan.excluded, [.fullLibraryCopy: 2, .quarantined: 1, .notChecked: 1], "unlocked: \(unlocked)")
        }
    }

    func testExportWritesOnlyExportablePresetsEvenWhenAskedForEverything() async throws {
        let (library, imported, included) = try await mixedLibrary(unlockedAtEnd: true)
        let snapshot = await library.snapshot
        let everything = (snapshot.playable + snapshot.pending + snapshot.quarantined + snapshot.needsUnlock).map(\.id)
        XCTAssertEqual(everything.count, 6)
        let before = UserPresetFixtures.snapshot(directory)
        let (summary, data) = try await X.exportData(library, ids: everything + ["user/does-not-exist"], to: output)

        let archive = try UserPresetArchiveReader.read(data)
        XCTAssertEqual(Set(archive.manifest.presets.map(\.id)), [imported.id, included.id])
        XCTAssertFalse(archive.manifest.presets.contains { $0.duplicateOf?.requiresLibraryUnlock == true })
        XCTAssertEqual(summary.exported, 2)
        XCTAssertEqual(summary.excluded, [.fullLibraryCopy: 2, .quarantined: 1, .notChecked: 1, .unavailable: 1])
        XCTAssertEqual(summary.fileName, "export.zip")
        XCTAssertEqual(summary.message,
                       "Exported 2 presets. Not exported: 2 copies of presets from the full library (part of the purchase; they stay on this device); "
                       + "1 file in Quarantine (it failed a check); 1 preset waiting to be checked; 1 preset that could not be read.")
        XCTAssertEqual(UserPresetFixtures.snapshot(directory), before, "an export only reads the store")
    }

    func testSelectionIsHonoured() async throws {
        let (library, imported, _) = try await mixedLibrary(unlockedAtEnd: false)
        let (summary, data) = try await X.exportData(library, ids: [imported.id], to: output)
        XCTAssertEqual(try UserPresetArchiveReader.read(data).manifest.presets.map(\.id), [imported.id])
        XCTAssertEqual(summary.message.hasPrefix("Exported 1 preset. Not exported:"), true)
    }

    func testNothingSelectedOrNothingExportable() async throws {
        let (library, _, _) = try await mixedLibrary(unlockedAtEnd: true)
        let none = await library.export(ids: [], appVersion: "1", exportedAt: X.now, to: output)
        XCTAssertEqual(none, .failure(.nothingSelected))
        let pack = await library.snapshot.playable.first { $0.duplicateOf?.requiresLibraryUnlock == true }
        let onlyPack = await library.export(ids: [try XCTUnwrap(pack).id], appVersion: "1", exportedAt: X.now, to: output)
        XCTAssertEqual(onlyPack, .failure(.nothingSelected))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(UserPresetExportError.nothingSelected.message, "Select at least one preset to export.")
    }

    func testAStoredTextThatNoLongerMatchesStopsTheExport() async throws {
        let (library, imported, included) = try await mixedLibrary(unlockedAtEnd: false)
        let stored = directory.appendingPathComponent("files/\(imported.sha256).milk")
        try Data("tampered".utf8).write(to: stored)
        let result = await library.export(ids: [included.id, imported.id], appVersion: "1", exportedAt: X.now, to: output)
        XCTAssertEqual(result, .failure(.contentMismatch))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "no partial file is left")
        XCTAssertEqual(UserPresetExportError.contentMismatch.message, "The presets could not be exported. Nothing was shared.")
    }

    func testAWriteFailureLeavesNoFile() async throws {
        let (library, imported, included) = try await mixedLibrary(unlockedAtEnd: false)
        for writes in [0, 1, 3] {
            let result = await library.export(ids: [imported.id, included.id], appVersion: "1", exportedAt: X.now, to: output, failAfterWrites: writes)
            XCTAssertEqual(result, .failure(.writeFailed), "after \(writes) writes")
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
        let missingFolder = output.deletingLastPathComponent().appendingPathComponent("no/such/folder/x.zip")
        let result = await library.export(ids: [imported.id], appVersion: "1", exportedAt: X.now, to: missingFolder)
        XCTAssertEqual(result, .failure(.writeFailed))
    }

    func testANewerRecordMakesExportUnavailable() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 99, "presets": []}"#.utf8).write(to: directory.appendingPathComponent("index.json"))
        let library = await X.library(directory, ids: CountingIDs())
        let plan = await library.exportPlan()
        XCTAssertEqual(plan, .empty)
        let result = await library.export(ids: ["user/x"], appVersion: "1", exportedAt: X.now, to: output)
        XCTAssertEqual(result, .failure(.libraryUnavailable))
    }

    func testExclusionWords() {
        XCTAssertNil(UserPresetExportExclusion.sentence([:]))
        XCTAssertEqual(UserPresetExportExclusion.sentence([.fullLibraryCopy: 1]),
                       "Not exported: 1 copy of a preset from the full library (part of the purchase; it stays on this device).")
        XCTAssertEqual(UserPresetExportExclusion.sentence([.notChecked: 2, .quarantined: 3]),
                       "Not exported: 3 files in Quarantine (they failed a check); 2 presets waiting to be checked.")
        XCTAssertEqual(UserPresetExportSummary(exported: 1, excluded: [:], fileName: "a.zip").message, "Exported 1 preset.")
    }

    /// S6: many presets export completely. Owner rule 7 (2026-11-14): no wall-clock assertion in the
    /// suite and no 90 s test; CI's iOS 27 simulator took 88 s and failed the old 10 s limit for 1,000
    /// presets. The suite checks completeness on 20; the 1,000-preset timing is an on-demand bench
    /// (`PRE014_BENCH=1`), which reports the time and asserts only completeness.
    func testManyPresetsExportCompletely() async throws {
        try await exportCompletely(count: 20)
    }

    func testAThousandPresetsExportBench() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PRE014_BENCH"] == "1", "bench: set PRE014_BENCH=1")
        let elapsed: TimeInterval = try await exportCompletely(count: PresetImportLimits.maxUserPresets)
        print("PRE014_BENCH export of \(PresetImportLimits.maxUserPresets) presets: \(elapsed) s")
    }

    @discardableResult
    private func exportCompletely(count: Int) async throws -> TimeInterval {
        let ids = CountingIDs()
        let library = await X.library(directory, ids: ids)
        for index in 0..<count {
            try await X.importFile(library, named: "P\(index).milk", text: X.text("bulk-\(index)"), in: folder)
        }
        let start = Date()
        let (summary, data) = try await X.exportData(library, to: output)
        let elapsed: TimeInterval = Date().timeIntervalSince(start)
        XCTAssertEqual(summary.exported, count)
        XCTAssertEqual(try UserPresetArchiveReader.read(data).texts.count, count)
        return elapsed
    }
}
