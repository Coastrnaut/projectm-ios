// Task T074: PresetRepository with fixture presets. Bundled preset files are joined with
// LICENSES.md; a file with no row or with an empty field is excluded (FR-047); presets are sorted
// alphabetically by display name.
import XCTest
@testable import Rendering

final class PresetRepositoryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("presets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("pack"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ path: String, _ text: String = "[preset00]\n") throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func licenses(_ rows: [String]) throws {
        let text = """
        # Preset licenses

        Every bundled preset needs a complete row (FR-047).

        | File | Display name | Pack | Author | License | Source URL | Source version |
        |------|--------------|------|--------|---------|------------|----------------|
        \(rows.joined(separator: "\n"))

        Notes after the table are ignored.
        """
        try text.write(to: folder.appendingPathComponent("LICENSES.md"), atomically: true, encoding: .utf8)
    }

    private func row(_ file: String, _ name: String, license: String = "CC0-1.0", version: String = "abc1234") -> String {
        "| \(file) | \(name) | pack | Author | \(license) | https://example.org/presets | \(version) |"
    }

    func testJoinsFilesWithRowsAndSortsByDisplayName() throws {
        try file("pack/zeta.milk")
        try file("pack/alpha.milk")
        try file("pack/beta.prjm")
        try licenses([row("pack/zeta.milk", "Zeta"), row("pack/alpha.milk", "alpha"), row("pack/beta.prjm", "Beta 10")])
        let catalog = try PresetRepository(presetsFolder: folder).load()
        XCTAssertEqual(catalog.presets.map(\.name), ["alpha", "Beta 10", "Zeta"])
        XCTAssertEqual(catalog.presets.map(\.id), ["pack/alpha.milk", "pack/beta.prjm", "pack/zeta.milk"])
        XCTAssertEqual(catalog.excluded, [])
        let alpha = try XCTUnwrap(catalog.presets.first)
        XCTAssertEqual(alpha.fileURL.lastPathComponent, "alpha.milk")
        XCTAssertEqual([alpha.packID, alpha.author, alpha.license, alpha.sourceURL, alpha.sourceVersion],
                       ["pack", "Author", "CC0-1.0", "https://example.org/presets", "abc1234"])
    }

    func testFilesWithoutARowOrWithEmptyFieldsAreExcluded() throws {
        try file("pack/licensed.milk")
        try file("pack/unlisted.milk")
        try file("pack/nolicense.milk")
        try file("pack/notes.txt")   // not a preset
        try licenses([row("pack/licensed.milk", "Licensed"),
                      row("pack/nolicense.milk", "No license", license: "", version: "")])
        let catalog = try PresetRepository(presetsFolder: folder).load()
        XCTAssertEqual(catalog.presets.map(\.id), ["pack/licensed.milk"])
        XCTAssertEqual(catalog.excluded, [
            PresetExclusion(path: "pack/nolicense.milk", reason: .missingFields(["License", "Source version"])),
            PresetExclusion(path: "pack/unlisted.milk", reason: .noLicenseRow),
        ])
    }

    func testRowsForMissingFilesAndDuplicatesAreReported() throws {
        try file("pack/a.milk")
        try licenses([row("pack/a.milk", "A"), row("pack/a.milk", "A again"), row("pack/gone.milk", "Gone")])
        let catalog = try PresetRepository(presetsFolder: folder).load()
        XCTAssertEqual(catalog.presets.map(\.name), ["A"])
        XCTAssertEqual(catalog.excluded, [
            PresetExclusion(path: "pack/a.milk", reason: .duplicateRow),
            PresetExclusion(path: "pack/gone.milk", reason: .fileMissing),
        ])
    }

    func testEscapedPipeAndShortRows() throws {
        XCTAssertEqual(PresetRepository.cells(of: "| a \\| b | c |"), ["a | b", "c"])
        try file("pack/short.milk")
        try licenses(["| pack/short.milk | Short | pack |"])
        let catalog = try PresetRepository(presetsFolder: folder).load()
        XCTAssertEqual(catalog.presets, [])
        XCTAssertEqual(catalog.excluded.first?.reason,
                       .missingFields(["Author", "License", "Source URL", "Source version"]))
    }

    func testMissingFolderFileOrTableThrows() throws {
        XCTAssertThrowsError(try PresetRepository(presetsFolder: folder.appendingPathComponent("nope")).load())
        XCTAssertThrowsError(try PresetRepository(presetsFolder: folder).load()) { error in
            XCTAssertEqual(error as? PresetRepositoryError, .licensesFileMissing)
        }
        try "# Licenses\n\nNo table here.\n".write(to: folder.appendingPathComponent("LICENSES.md"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try PresetRepository(presetsFolder: folder).load()) { error in
            XCTAssertEqual(error as? PresetRepositoryError, .licensesTableMissing)
        }
    }

    func testEmptyTableGivesAnEmptyCatalog() throws {
        try licenses([])
        XCTAssertEqual(try PresetRepository(presetsFolder: folder).load(), PresetCatalog(presets: [], excluded: []))
    }
}
