// PaletteBackupTests.swift — UIX-011-T09 (UIX-011-R11, S4; research UIX-011-D7; contract P5): the library backup
// carries the user palettes; restore merges them per palette by the choice (Keep both = a copy under a derived
// ID, Replace, Skip); FILE-011's "Scenes and show" erase removes them.
import Foundation
import SceneFormat
import XCTest
@testable import LibraryBackup

final class PaletteBackupTests: XCTestCase {
    private let idA = "0000C011-0000-4000-8000-00000000000A"
    private let idB = "0000C011-0000-4000-8000-00000000000B"
    private let black = PaletteColor(red: 0, green: 0, blue: 0)
    private let teal = PaletteColor(red: 0, green: 0x80, blue: 0x80)

    private func write(_ folders: LibraryFolders, _ palettes: [ColorPalette]) throws {
        try FileManager.default.createDirectory(at: folders.url(.palettes), withIntermediateDirectories: true)
        try Data(PaletteFile.encode(PaletteLibrary(user: palettes))).write(to: folders.palettesFile)
    }

    private func read(_ folders: LibraryFolders) throws -> PaletteLibrary {
        try PaletteFile.decode([UInt8](Data(contentsOf: folders.palettesFile))).library
    }

    private func palette(_ id: String, _ name: String, _ colors: [PaletteColor]) -> ColorPalette {
        ColorPalette(id: id, name: name, colors: colors)
    }

    func testABackupRoundTripKeepsEveryPalette() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        try write(source, [palette(idA, "Neon", [black, teal]), palette(idB, "Dusk", [teal, black, teal])])
        let backup = try BackupFixtures.backup(of: source)
        XCTAssertTrue(try LibraryBackupReader.read(backup).manifest.files.contains { $0.path == LibraryBackupFormat.palettesPath })

        let fresh = BackupFixtures.sandbox(self, "fresh")
        let outcome = try BackupFixtures.restore(backup, into: fresh, sink: BackupFixtures.SettingsSink())
        guard case .restored = outcome else { return XCTFail("not restored: \(outcome)") }
        XCTAssertEqual(try read(fresh), try read(source))
        XCTAssertNotNil(try LibraryRecords.read(folders: fresh, settings: [:]).digests["palettes"])
        XCTAssertEqual(try LibraryRecords.read(folders: fresh, settings: [:]).digests["palettes"],
                       try LibraryRecords.read(folders: source, settings: [:]).digests["palettes"])
    }

    func testRestoreMergesPalettesByChoice() {
        let backup = LibraryContents(palettes: PaletteLibrary(user: [palette(idA, "Neon", [black, teal]), palette(idB, "Dusk", [teal, teal])]))
        let device = LibraryContents(palettes: PaletteLibrary(user: [palette(idA, "Neon", [teal, teal])]))

        let both = LibraryRestorePlanner.plan(backup: backup, library: device, choice: .keepBoth)
        XCTAssertEqual(both.palettes?.user.map(\.name), ["Neon", "Neon copy", "Dusk"], "in backup order")
        XCTAssertEqual(both.palettes?.user.first?.colors, [teal, teal], "the device's palette is untouched")
        XCTAssertEqual(both.count(.palettes, .clash), 1)
        XCTAssertEqual(both.count(.palettes, .new), 1)
        XCTAssertEqual(both.changedFolders, [.palettes])
        XCTAssertEqual(LibraryRestorePlanner.plan(backup: backup, library: device, choice: .keepBoth).palettes, both.palettes, "deterministic")

        let replaced = LibraryRestorePlanner.plan(backup: backup, library: device, choice: .replace)
        XCTAssertEqual(replaced.palettes?.palette(idA)?.colors, [black, teal])
        XCTAssertEqual(replaced.palettes?.user.count, 2)

        let skipped = LibraryRestorePlanner.plan(backup: backup, library: device, choice: .skip)
        XCTAssertEqual(skipped.palettes?.palette(idA)?.colors, [teal, teal])
        XCTAssertEqual(skipped.palettes?.user.count, 2, "a new palette is added under Skip too")

        let same = LibraryRestorePlanner.plan(backup: device, library: device)
        XCTAssertNil(same.palettes, "identical palettes change nothing")
        XCTAssertEqual(same.count(.palettes, .identical), 1)
    }

    func testEraseOfScenesRemovesPalettes() throws {
        let sandbox = try EraseFixtures.sandbox(self, "palettes")
        let before = LibraryEraseInventory.count(.scenes, root: sandbox.root, settings: [:])
        try write(sandbox.folders, [palette(idA, "Neon", [black, teal])])
        XCTAssertEqual(LibraryEraseInventory.count(.scenes, root: sandbox.root, settings: [:]), before + 1, "one user palette")
        XCTAssertTrue(LibraryErasePolicy.folders(.scenes).contains(LibraryFolders.Folder.palettes.rawValue))
        try EraseFixtures.erase([.scenes], in: sandbox, defaults: EraseFixtures.Defaults())
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.folders.palettesFile.path))
    }
}
