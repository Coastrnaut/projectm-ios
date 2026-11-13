// PRE-014-T09: manifest.json with a checksummed file list on top of the stored ZIP.
import XCTest
import LocalPortability

final class PortableArchiveTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_794_484_800)
    private let format = "org.example.test-archive"
    private let limits = PortableArchiveLimits(maxFiles: 4, maxFileBytes: 1_024, maxManifestBytes: 8_192)

    private struct Manifest: Codable {
        var format: String
        var formatVersion: Int
        var files: [PortableFileRecord]
        var note: String?
    }

    private func manifestData(_ manifest: Manifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    /// Writes `files`, then a manifest built from the records (`edit` may change it first).
    private func archive(_ files: [(String, String)], version: Int = 1, extra: [(String, String)] = [],
                         edit: (inout Manifest) -> Void = { _ in }) throws -> Data {
        var out = Data()
        let writer = PortableArchiveWriter(modified: date) { out.append($0) }
        var records: [PortableFileRecord] = []
        for (path, text) in files { records.append(try writer.add(path: path, data: Data(text.utf8))) }
        for (path, text) in extra { _ = try writer.add(path: path, data: Data(text.utf8)) }
        var manifest = Manifest(format: format, formatVersion: version, files: records, note: "kept")
        edit(&manifest)
        try writer.finish(manifest: try manifestData(manifest))
        return out
    }

    private func read(_ data: Data, supported: Int = 1) throws -> PortableArchiveContents {
        try PortableArchive.read(data, format: format, supportedVersion: supported, limits: limits)
    }

    private func assertRefused(_ data: Data, _ expected: PortableArchiveError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try read(data), file: file, line: line) { error in
            XCTAssertEqual(error as? PortableArchiveError, expected, file: file, line: line)
        }
    }

    func testRoundTrip() throws {
        let contents = try read(try archive([("docs/a.txt", "alpha"), ("b.txt", "beta ✓")]))
        XCTAssertEqual(contents.formatVersion, 1)
        XCTAssertEqual(contents.records.map(\.path), ["docs/a.txt", "b.txt"])
        XCTAssertEqual(contents.records[0].sha256, PortableSHA256.hex(Array("alpha".utf8)))
        XCTAssertEqual(contents.records[1].byteCount, Array("beta ✓".utf8).count)
        XCTAssertEqual(contents.files["b.txt"], Data("beta ✓".utf8))
        let manifest = try JSONDecoder().decode(Manifest.self, from: contents.manifest)
        XCTAssertEqual(manifest.note, "kept", "the caller's own keys come back untouched")
    }

    func testManifestIsTheLastEntry() throws {
        let entries = try StoredZipReader.read(try archive([("a", "1")]), limits: limits.zip)
        XCTAssertEqual(entries.map(\.path), ["a", PortableArchive.manifestPath])
    }

    func testWriterRefusesTheManifestPathAsAFile() {
        let writer = PortableArchiveWriter(modified: date) { _ in }
        XCTAssertThrowsError(try writer.add(path: PortableArchive.manifestPath, data: Data())) {
            XCTAssertEqual($0 as? StoredZipError, .duplicatePath(PortableArchive.manifestPath))
        }
    }

    func testRefusesAnArchiveWithoutAManifest() throws {
        var out = Data()
        let writer = StoredZipWriter(modified: date) { out.append($0) }
        try writer.add(path: "a.txt", data: Data("1".utf8))
        try writer.finish()
        assertRefused(out, .missingManifest)
    }

    func testRefusesAnOversizeManifest() throws {
        let data = try archive([("a", "1")]) { $0.note = String(repeating: "n", count: 9_000) }
        assertRefused(data, .zip(.entryTooLarge(PortableArchive.manifestPath)))
    }

    func testRefusesMalformedManifests() throws {
        var out = Data()
        let writer = PortableArchiveWriter(modified: date) { out.append($0) }
        try writer.finish(manifest: Data("{not json".utf8))
        assertRefused(out, .malformedManifest)

        let badHash = try archive([("a", "1")]) { $0.files[0].sha256 = "ABC" }
        assertRefused(badHash, .invalidRecord("a"))   // FILE-002-R4: named, no longer generic

        let zeroVersion = try archive([("a", "1")], version: 0)
        assertRefused(zeroVersion, .malformedManifest)
    }

    // FILE-002-T02: a malformed record is refused naming its entry (FILE-002-R4).
    func testMalformedRecordsAreRefusedNamingTheEntry() throws {
        let good = PortableSHA256.hex(Data("1".utf8))
        let digests = [good.uppercased(), String(good.dropLast()), good + "0", String(good.dropLast()) + "g", "", String(repeating: " ", count: 64)]
        for digest in digests {
            assertRefused(try archive([("a", "1"), ("b", "2")]) { $0.files[1].sha256 = digest }, .invalidRecord("b"))
        }
        assertRefused(try archive([("a", "1"), ("b", "2")]) { $0.files[1].byteCount = -1 }, .invalidRecord("b"))
    }

    // FILE-002-T02: every per-entry message names the entry; size and checksum differ (FILE-002-R3).
    func testPerEntryMessagesNameTheEntry() {
        let path = "assets/clip.mov"
        let errors: [PortableArchiveError] = [.unlistedFile(path), .missingFile(path), .duplicateListing(path), .lengthMismatch(path),
                                              .checksumMismatch(path), .unsafePath(path), .invalidRecord(path), .zip(.checksumMismatch(path))]
        for error in errors { XCTAssertTrue(error.message.contains(path), "\(error)") }
        XCTAssertNotEqual(PortableArchiveError.lengthMismatch(path).message, PortableArchiveError.checksumMismatch(path).message)
    }

    // FILE-002-T09: a 4 MiB entry verifies; its last byte changed with the CRC-32 repaired is caught by
    // the SHA-256 (FILE-002-S3).
    func testALargeEntryVerifiesAndItsTamperIsCaught() throws {
        let size = 4 * 1_024 * 1_024
        var big = Data(count: size)
        big.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            for i in 0..<size { raw[i] = UInt8(truncatingIfNeeded: i &* 31 &+ (i >> 9)) }
        }
        let largeLimits = PortableArchiveLimits(maxFiles: 2, maxFileBytes: size, maxManifestBytes: 8_192)
        var out = Data()
        let writer = PortableArchiveWriter(modified: date) { out.append($0) }
        let record = try writer.add(path: "big.bin", data: big)
        try writer.finish(manifest: try manifestData(Manifest(format: format, formatVersion: 1, files: [record], note: nil)))
        let contents = try PortableArchive.read(out, format: format, supportedVersion: 1, limits: largeLimits)
        XCTAssertEqual(contents.files["big.bin"], big)
        XCTAssertEqual(record.byteCount, size)

        var tampered = out
        tampered[tampered.startIndex + ZipBytes.dataStart(tampered, entry: 0) + size - 1] ^= 0x01
        XCTAssertThrowsError(try PortableArchive.read(tampered, format: format, supportedVersion: 1, limits: largeLimits)) { (error: Error) in
            XCTAssertEqual(error as? PortableArchiveError, .zip(.checksumMismatch("big.bin")), "CRC-32 stale: the ZIP layer catches it")
        }
        ZipBytes.repairCRC(&tampered, entry: 0)
        XCTAssertThrowsError(try PortableArchive.read(tampered, format: format, supportedVersion: 1, limits: largeLimits)) { (error: Error) in
            XCTAssertEqual(error as? PortableArchiveError, .checksumMismatch("big.bin"), "CRC-32 repaired: the SHA-256 catches it")
        }
    }

    func testRefusesAnotherFormat() throws {
        assertRefused(try archive([("a", "1")]) { $0.format = "org.example.other" }, .wrongFormat)
    }

    func testRefusesANewerVersionWithItsOwnError() throws {
        let data = try archive([("a", "1")], version: 2)
        assertRefused(data, .newerVersion(2))
        XCTAssertEqual(try read(data, supported: 2).formatVersion, 2)
    }

    func testRefusesUnlistedAndMissingFiles() throws {
        assertRefused(try archive([("a", "1")], extra: [("smuggled.txt", "x")]), .unlistedFile("smuggled.txt"))
        assertRefused(try archive([("a", "1")]) { $0.files.append(PortableFileRecord(path: "gone.txt", sha256: String(repeating: "0", count: 64), byteCount: 1)) },
                      .missingFile("gone.txt"))
    }

    func testRefusesMismatchesAndDuplicateListings() throws {
        assertRefused(try archive([("a", "1")]) { $0.files[0].byteCount = 2 }, .lengthMismatch("a"))
        assertRefused(try archive([("a", "1")]) { $0.files[0].sha256 = String(repeating: "0", count: 64) }, .checksumMismatch("a"))
        assertRefused(try archive([("a", "1")]) { $0.files.append($0.files[0]) }, .duplicateListing("a"))
        assertRefused(try archive([("a", "1")]) { $0.files[0].path = "../a" }, .unsafePath("../a"))
    }

    func testRefusesTooManyFiles() throws {
        let data = try archive((0..<5).map { ("f\($0)", "x") })
        assertRefused(data, .zip(.tooManyEntries(5)))
    }

    func testZipErrorsPassThrough() throws {
        var data = try archive([("a", "1")])
        data[ZipBytes.dataStart(data, entry: 0)] ^= 0x01
        assertRefused(data, .zip(.checksumMismatch("a")))
    }

    func testLimitsCoverTheLargestValidArchive() {
        let zip = limits.zip
        XCTAssertEqual(zip.maxEntries, 5)
        XCTAssertEqual(zip.limit(for: PortableArchive.manifestPath), 8_192)
        XCTAssertEqual(zip.limit(for: "a"), 1_024)
        XCTAssertGreaterThanOrEqual(zip.maxArchiveBytes, 4 * 1_024 + 8_192 + 5 * (30 + 46 + 2 * 255) + 22)
    }

    func testErrorsHaveWords() {
        for error in [PortableArchiveError.missingManifest, .malformedManifest, .wrongFormat, .newerVersion(2), .unlistedFile("a"),
                      .missingFile("a"), .duplicateListing("a"), .lengthMismatch("a"), .checksumMismatch("a"), .unsafePath("a"),
                      .invalidRecord("a"), .zip(.truncated)] {
            XCTAssertFalse(error.message.isEmpty, "\(error)")
        }
        XCTAssertEqual(PortableArchiveError.zip(.truncated).message, StoredZipError.truncated.message)
    }
}
