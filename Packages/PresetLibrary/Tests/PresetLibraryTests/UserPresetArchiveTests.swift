// PRE-014-T11: the acceptance, "Round-trip archive preserves IDs and metadata without network"
// (PRE-014-R7-R14; S1, S3, S4). A fixture library is exported through UserPresetLibrary, read back
// with UserPresetArchiveReader and compared field by field; the format is pinned by a golden
// hash; altered and hostile archives are refused with their reason.
import LocalPortability
import XCTest
@testable import PresetLibrary

final class UserPresetArchiveTests: XCTestCase {
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

    // MARK: - Round trip (S1)

    func testRoundTripPreservesIDsMetadataAndTexts() async throws {
        let library = try await X.exportableLibrary(directory, folder: folder, ids: CountingIDs())
        let stored = await library.snapshot.playable
        XCTAssertEqual(stored.count, 3)
        let (summary, data) = try await X.exportData(library, to: output)
        XCTAssertEqual(summary.exported, 3)

        let archive = try UserPresetArchiveReader.read(data)
        XCTAssertEqual(archive.manifest.format, "org.projectmios.user-presets")
        XCTAssertEqual(archive.manifest.formatVersion, 1)
        XCTAssertEqual(archive.manifest.appVersion, "1.1 (2)")
        XCTAssertEqual(archive.manifest.exportedAt, X.now)
        XCTAssertEqual(archive.manifest.presets.map(\.id), stored.map(\.id).sorted())

        for record in stored {
            let exported = try XCTUnwrap(archive.manifest.presets.first { $0.id == record.id }, record.name)
            XCTAssertEqual(exported.name, record.name)
            XCTAssertEqual(exported.author, record.author)
            XCTAssertEqual(exported.authorFromFileName, record.license.authorFromFileName)
            XCTAssertEqual(exported.originalFileName, record.originalFileName)
            XCTAssertEqual(exported.origin, record.license.origin)
            XCTAssertEqual(exported.rightsVerified, record.license.rightsVerified)
            XCTAssertEqual(exported.licenseLines, record.license.linesFound)
            XCTAssertEqual(exported.warnings, record.warnings)
            XCTAssertEqual(exported.duplicateOf, record.duplicateOf)
            XCTAssertEqual(exported.importedAt, record.importedAt)
            XCTAssertEqual(exported.modifiedAt, record.modifiedAt)
            XCTAssertEqual(exported.sha256, record.sha256)
            XCTAssertEqual(exported.blobHash, record.blobHash)
            XCTAssertEqual(exported.byteCount, record.byteCount)
            XCTAssertEqual(exported.path, "presets/\(record.id.dropFirst(5)).milk")
            let text = await library.data(for: record.id)
            XCTAssertEqual(archive.texts[record.id], text, record.name)

            // What PRE-013 will store: the same record, waiting for its own checks.
            var expected = record
            expected.state = .pending
            expected.provenOnScreen = false
            expected.quarantine = nil
            XCTAssertEqual(exported.userPreset(), expected)
            XCTAssertTrue(exported.userPreset().isWellFormed)
        }

        // The fixture covers what the acceptance names.
        let presets = archive.manifest.presets
        XCTAssertTrue(presets.contains { $0.licenseLines.contains { $0.contains("CC-BY 4.0") } && $0.authorFromFileName })
        XCTAssertTrue(presets.contains { $0.name.contains("🌌") && !$0.warnings.isEmpty })
        let copy = try XCTUnwrap(presets.first { $0.origin == .bundledDuplicate })
        XCTAssertEqual(copy.duplicateOf?.packID, "included")
        XCTAssertEqual(copy.duplicateOf?.licenseStatement, "Bundled with projectM; see the app's licenses screen.")
        XCTAssertFalse(copy.rightsVerified)
        XCTAssertEqual(copy.modifiedAt, X.later)
    }

    func testManifestCarriesNoDeviceOrPurchaseData() async throws {
        let library = try await X.exportableLibrary(directory, folder: folder, ids: CountingIDs())
        let (_, data) = try await X.exportData(library, to: output)
        let archive = try UserPresetArchiveReader.read(data)
        let manifest = try XCTUnwrap(String(data: archive.manifestData, encoding: .utf8))
        for forbidden in ["/Users/", "/var/", "/private/", "Application Support", "UserPresets", "file:", "unlock\"", "entitle",
                          "purchase", "transaction", "state", "proven", "quarantine", NSUserName()] where !forbidden.isEmpty {
            XCTAssertFalse(manifest.contains(forbidden), "manifest mentions \(forbidden)")
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: archive.manifestData) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["format", "formatVersion", "appVersion", "exportedAt", "files", "presets"])
        let entries = try StoredZipReader.read(data, limits: UserPresetArchiveFormat.limits.zip)
        XCTAssertEqual(entries.last?.path, "manifest.json")
        XCTAssertTrue(entries.dropLast().allSatisfy { $0.path.hasPrefix("presets/") && $0.path.hasSuffix(".milk") })
    }

    func testSameInputGivesTheSameBytes() async throws {
        let library = try await X.exportableLibrary(directory, folder: folder, ids: CountingIDs())
        let (_, first) = try await X.exportData(library, to: output)
        let second = output.deletingLastPathComponent().appendingPathComponent("again.zip")
        let (_, again) = try await X.exportData(library, to: second)
        XCTAssertEqual(first, again)
    }

    // MARK: - Golden format (S4)

    static func goldenRecords() -> [(UserPreset, Data)] {
        let first = Data("[preset00]\nzoom=1.000000\n// License: CC0\n".utf8)
        let second = Data("[preset00]\nrot=0.020000\n".utf8)
        let a = UserPreset(id: "user/00000000-0000-4000-8000-000000000002", name: "Waves “quoted” 🌊", author: "Ann",
                           originalFileName: "Ann - Waves.milk", sha256: ContentHash.sha256Hex([UInt8](first)),
                           blobHash: ContentHash.gitBlobSHA1Hex([UInt8](first)), byteCount: first.count,
                           importedAt: Date(timeIntervalSince1970: 1_800_000_000), state: .playable, provenOnScreen: true,
                           warnings: [PresetImportWarning(.ignoredLines, detail: "1")],
                           license: PresetLicenseMetadata(authorFromFileName: true, linesFound: ["// License: CC0"]))
        let origin = PresetDuplicateOrigin(presetID: "included/Beta.milk", name: "Beta", packID: "included", packTitle: "Included",
                                           sha256: String(repeating: "a", count: 64), blobHash: String(repeating: "b", count: 40),
                                           licenseStatement: "Statement.", requiresLibraryUnlock: false)
        let b = UserPreset(id: "user/00000000-0000-4000-8000-000000000001", name: "Beta copy", author: "Bo", originalFileName: "Beta.milk",
                           sha256: ContentHash.sha256Hex([UInt8](second)), blobHash: ContentHash.gitBlobSHA1Hex([UInt8](second)),
                           byteCount: second.count, importedAt: Date(timeIntervalSince1970: 1_800_000_100), state: .playable,
                           license: PresetLicenseMetadata(origin: .bundledDuplicate, authorFromFileName: false, linesFound: []),
                           duplicateOf: origin, modifiedAt: Date(timeIntervalSince1970: 1_800_000_200))
        return [(a, first), (b, second)]
    }

    static func goldenArchive() throws -> Data {
        let records = goldenRecords()
        var out = Data()
        try UserPresetArchiveWriter.write(records.map(\.0), appVersion: "1.1 (2)", exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                          contents: { preset in records.first { $0.0.id == preset.id }?.1 }, sink: { out.append($0) })
        return out
    }

    /// The bytes of format version 1 for a fixed input. A change here is a format change: bump
    /// the format version and keep reading version 1.
    static let goldenSHA256 = "ad40f883ea014fc822430605bb5646e565a6a39eacd154bf70357daa0d133794"

    func testGoldenArchiveHash() throws {
        let data = try Self.goldenArchive()
        XCTAssertEqual(data, try Self.goldenArchive())
        XCTAssertEqual(PortableSHA256.hex(data), Self.goldenSHA256)
        let archive = try UserPresetArchiveReader.read(data)
        XCTAssertEqual(archive.manifest.presets.map(\.id), ["user/00000000-0000-4000-8000-000000000001", "user/00000000-0000-4000-8000-000000000002"])
        // Optional fields: absent when the record has none.
        let manifest = String(decoding: archive.manifestData, as: UTF8.self)
        XCTAssertEqual(manifest.components(separatedBy: "\"modifiedAt\"").count - 1, 1)
        XCTAssertEqual(manifest.components(separatedBy: "\"duplicateOf\"").count - 1, 1)
    }

    /// PRE-014-T13: `EXPORT_FIXTURE_OUT=<path> swift test --filter testWriteFixtureForInteroperability`
    /// writes the golden archive for `unzip -t` and Python's zipfile.
    func testWriteFixtureForInteroperability() throws {
        guard let path = ProcessInfo.processInfo.environment["EXPORT_FIXTURE_OUT"] else { throw XCTSkip("EXPORT_FIXTURE_OUT not set") }
        try Self.goldenArchive().write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Refusals (S3)

    private func rebuild(_ data: Data, manifest edit: (inout UserPresetArchiveManifest) -> Void = { _ in },
                         texts: (inout [String: Data]) -> Void = { _ in }) throws -> Data {
        let entries = try StoredZipReader.read(data, limits: UserPresetArchiveFormat.limits.zip)
        var manifest = try UserPresetArchiveManifest.decode(try XCTUnwrap(entries.first { $0.path == "manifest.json" }).data)
        var files: [String: Data] = [:]
        for entry in entries where entry.path != "manifest.json" { files[entry.path] = entry.data }
        texts(&files)
        edit(&manifest)
        var out = Data()
        let writer = PortableArchiveWriter(modified: Date(timeIntervalSince1970: 1_800_000_000)) { out.append($0) }
        for path in files.keys.sorted() { _ = try writer.add(path: path, data: files[path]!) }
        try writer.finish(manifest: try manifest.encoded())
        return out
    }

    private func assertRefused(_ data: Data, _ expected: UserPresetArchiveError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try UserPresetArchiveReader.read(data), file: file, line: line) { error in
            XCTAssertEqual(error as? UserPresetArchiveError, expected, file: file, line: line)
            XCTAssertFalse((error as? UserPresetArchiveError)?.message.isEmpty ?? true, file: file, line: line)
        }
    }

    private let firstID = "user/00000000-0000-4000-8000-000000000001"

    func testUnchangedRebuildIsAccepted() throws {
        XCTAssertEqual(try UserPresetArchiveReader.read(try rebuild(try Self.goldenArchive())).manifest.presets.count, 2)
    }

    func testFlippedTextByteFailsTheChecksum() throws {
        var data = try Self.goldenArchive()
        let entries = try StoredZipReader.read(data, limits: UserPresetArchiveFormat.limits.zip)
        let text = entries[0].data
        let at = try XCTUnwrap(data.range(of: text)).lowerBound + 3
        data[at] ^= 0x01
        assertRefused(data, .archive(.zip(.checksumMismatch(entries[0].path))))
    }

    func testTruncatedArchiveIsRefused() throws {
        let data = try Self.goldenArchive()
        for cut in [1, 10, data.count / 2, data.count - 23, data.count - 1] {
            XCTAssertThrowsError(try UserPresetArchiveReader.read(data.prefix(cut)), "cut \(cut)")
        }
        assertRefused(data.prefix(data.count - 1), .archive(.zip(.truncated)))
    }

    func testUnsafePathsAreRefused() throws {
        let golden = try Self.goldenArchive()
        for badPath in ["../x", "/x", "presets/../../x.milk"] {
            let data = try rebuild(golden) { $0.files[0].path = badPath; $0.presets[0].path = badPath }
            assertRefused(data, .archive(.unsafePath(badPath)))
        }
    }

    func testAPresetPathMustBeItsOwnIDsPath() throws {
        let golden = try Self.goldenArchive()
        let data = try rebuild(golden) { $0.presets[0].path = $0.presets[1].path }
        assertRefused(data, .pathMismatch(firstID))
    }

    func testTextThatDoesNotMatchItsHashesIsRefused() throws {
        let golden = try Self.goldenArchive()
        let replacement = Data("[preset00]\nzoom=2.0\n".utf8)
        let data = try rebuild(golden, manifest: {
            let sha = PortableSHA256.hex(replacement)
            $0.files[0].sha256 = sha; $0.files[0].byteCount = replacement.count
            $0.presets[0].sha256 = sha; $0.presets[0].byteCount = replacement.count   // blobHash left as it was
        }, texts: { $0[$0.keys.sorted()[0]] = replacement })
        assertRefused(data, .contentMismatch(firstID))
        let disagreeing = try rebuild(golden) { $0.presets[0].byteCount += 1 }
        assertRefused(disagreeing, .contentMismatch(firstID))
    }

    func testDuplicateIDsAndTextsAreRefused() throws {
        let golden = try Self.goldenArchive()
        assertRefused(try rebuild(golden) { $0.presets[1].id = $0.presets[0].id }, .duplicatePreset(firstID))
    }

    func testRightsClaimsAreRefused() throws {
        assertRefused(try rebuild(try Self.goldenArchive()) { $0.presets[0].rightsVerified = true }, .rightsClaimed(firstID))
    }

    func testCopiesOfFullLibraryPresetsAreRefused() throws {
        let golden = try Self.goldenArchive()
        assertRefused(try rebuild(golden) { $0.presets[0].duplicateOf?.requiresLibraryUnlock = true }, .fullLibraryCopy(firstID))
        assertRefused(try rebuild(golden) { $0.presets[0].duplicateOf?.packID = "cream-of-the-crop" }, .fullLibraryCopy(firstID))
    }

    func testOriginAndDuplicateOfMustAgree() throws {
        let golden = try Self.goldenArchive()
        assertRefused(try rebuild(golden) { $0.presets[0].duplicateOf = nil }, .invalidPreset(firstID))
        assertRefused(try rebuild(golden) { $0.presets[0].id = "user/../../evil" }, .invalidPreset("user/../../evil"))
        assertRefused(try rebuild(golden) { $0.presets[0].name = "" }, .invalidPreset(firstID))
    }

    func testFilesNoPresetUsesAreRefused() throws {
        let golden = try Self.goldenArchive()
        let data = try rebuild(golden) { $0.presets.removeFirst() }
        assertRefused(data, .unreferencedFile("presets/00000000-0000-4000-8000-000000000001.milk"))
    }

    func testTooManyPresetsAreRefused() throws {
        let golden = try Self.goldenArchive()
        let data = try rebuild(golden) { manifest in
            manifest.presets = Array(repeating: manifest.presets[0], count: PresetImportLimits.maxUserPresets + 1)
        }
        assertRefused(data, .tooManyPresets)
    }

    func testNewerAndForeignFormatsAreRefused() throws {
        let golden = try Self.goldenArchive()
        assertRefused(try rebuild(golden) { $0.formatVersion = 2 }, .archive(.newerVersion(2)))
        assertRefused(try rebuild(golden) { $0.format = "org.example.other" }, .archive(.wrongFormat))
        XCTAssertEqual(UserPresetArchiveError.archive(.newerVersion(2)).message,
                       "This archive was made by a newer version of the app. Update the app to read it.")
    }

    func testGarbageIsRefusedWithoutCrashing() {
        for data in [Data(), Data("PK".utf8), Data(repeating: 0x50, count: 4_096), Data((0..<2_048).map { UInt8(truncatingIfNeeded: $0 * 7) })] {
            XCTAssertThrowsError(try UserPresetArchiveReader.read(data))
        }
    }
}
