// PRE-014-T07: the stored-only ZIP writer and the bounded reader (research D2, D4).
import XCTest
import LocalPortability

final class StoredZipTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_794_484_800)   // 2026-11-12T12:00:00Z
    private let limits = StoredZipLimits(maxEntries: 10, maxEntryBytes: 1_024, maxArchiveBytes: 64 * 1_024)

    private func archive(_ entries: [(String, String)], modified: Date? = nil) throws -> Data {
        var out = Data()
        let writer = StoredZipWriter(modified: modified ?? date) { out.append($0) }
        for (path, text) in entries { try writer.add(path: path, data: Data(text.utf8)) }
        try writer.finish()
        return out
    }

    private var sample: [(String, String)] {
        [("presets/a.milk", "[preset00]\nzoom=1.0\n"), ("presets/b.milk", "second ✓ text"), ("manifest.json", "{}")]
    }

    private func assertRefused(_ data: Data, _ expected: StoredZipError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try StoredZipReader.read(data, limits: limits), file: file, line: line) { error in
            XCTAssertEqual(error as? StoredZipError, expected, file: file, line: line)
        }
    }

    // MARK: - Round trip and determinism

    func testRoundTrip() throws {
        let data = try archive(sample)
        let entries = try StoredZipReader.read(data, limits: limits)
        XCTAssertEqual(entries.map(\.path), sample.map(\.0))
        XCTAssertEqual(entries.map { String(decoding: $0.data, as: UTF8.self) }, sample.map(\.1))
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
    }

    func testFormatFieldsAreStoredUTF8WithoutExtras() throws {
        let data = try archive(sample)
        for central in ZipBytes.centralHeaders(data) {
            XCTAssertEqual(ZipBytes.u16(data, central + 4), 0x0314, "made by Unix, 2.0")
            XCTAssertEqual(ZipBytes.u16(data, central + 6), 20, "version needed 2.0")
            XCTAssertEqual(ZipBytes.u16(data, central + 8), 0x0800, "UTF-8 names only")
            XCTAssertEqual(ZipBytes.u16(data, central + 10), 0, "stored")
            XCTAssertEqual(ZipBytes.u16(data, central + 30), 0, "no extra field")
            XCTAssertEqual(ZipBytes.u16(data, central + 32), 0, "no comment")
            XCTAssertEqual(ZipBytes.u32(data, central + 38), 0o100644 << 16, "mode 0644")
        }
        XCTAssertEqual(ZipBytes.u16(data, ZipBytes.endRecord(data) + 20), 0, "no archive comment")
        // DOS time 12:00:00, date 2026-11-12.
        let first = ZipBytes.centralHeaders(data)[0]
        XCTAssertEqual(ZipBytes.u16(data, first + 12), 12 << 11)
        XCTAssertEqual(ZipBytes.u16(data, first + 14), (2026 - 1980) << 9 | 11 << 5 | 12)
    }

    func testIdenticalInputGivesIdenticalBytes() throws {
        XCTAssertEqual(try archive(sample), try archive(sample))
        XCTAssertNotEqual(try archive(sample), try archive(sample, modified: date.addingTimeInterval(60)))
    }

    func testDatesOutsideTheDOSRangeAreClamped() throws {
        let early = try archive([("a", "x")], modified: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(ZipBytes.u16(early, ZipBytes.centralHeaders(early)[0] + 14), 0 << 9 | 1 << 5 | 1)
        XCTAssertNoThrow(try StoredZipReader.read(early, limits: limits))
    }

    func testEmptyArchiveAndEmptyEntry() throws {
        XCTAssertEqual(try StoredZipReader.read(try archive([]), limits: limits), [])
        XCTAssertEqual(try StoredZipReader.read(try archive([("empty.txt", "")]), limits: limits).first?.data, Data())
    }

    // MARK: - Writer refusals

    func testWriterRefusesUnsafeAndDuplicatePaths() throws {
        let writer = StoredZipWriter(modified: date) { _ in }
        XCTAssertThrowsError(try writer.add(path: "../x", data: Data())) { XCTAssertEqual($0 as? StoredZipError, .unsafePath("../x")) }
        XCTAssertThrowsError(try writer.add(path: "/x", data: Data())) { XCTAssertEqual($0 as? StoredZipError, .unsafePath("/x")) }
        try writer.add(path: "A.milk", data: Data("1".utf8))
        XCTAssertThrowsError(try writer.add(path: "a.milk", data: Data())) { XCTAssertEqual($0 as? StoredZipError, .duplicatePath("a.milk")) }
        try writer.finish()
        XCTAssertThrowsError(try writer.add(path: "b", data: Data())) { XCTAssertEqual($0 as? StoredZipError, .finished) }
    }

    func testWriterPassesSinkErrorsOn() {
        struct Full: Error {}
        let writer = StoredZipWriter(modified: date) { _ in throw Full() }
        XCTAssertThrowsError(try writer.add(path: "a", data: Data("x".utf8))) { XCTAssertTrue($0 is Full) }
    }

    // MARK: - Reader refusals

    func testRefusesNonZipData() {
        assertRefused(Data(), .notAZip)
        assertRefused(Data("hello, this is not an archive at all".utf8), .notAZip)
        assertRefused(Data((0..<500).map { UInt8(truncatingIfNeeded: $0 &* 73) }), .notAZip)
    }

    func testEveryTruncationIsRefusedWithoutCrashing() throws {
        let data = try archive(sample)
        for length in 1..<data.count {
            XCTAssertThrowsError(try StoredZipReader.read(data.prefix(length), limits: limits), "length \(length)") { error in
                let refusal = error as? StoredZipError
                XCTAssertTrue(refusal == .truncated || refusal == .notAZip || refusal.map { if case .malformed = $0 { true } else { false } } == true,
                              "length \(length): \(String(describing: refusal))")
            }
        }
    }

    func testFlippedDataByteFailsTheChecksum() throws {
        var data = try archive(sample)
        data[ZipBytes.dataStart(data, entry: 1)] ^= 0x01
        assertRefused(data, .checksumMismatch("presets/b.milk"))
    }

    func testRefusesCompressionEncryptionAndOtherOptions() throws {
        let clean = try archive(sample)
        var compressed = clean
        ZipBytes.set16(&compressed, ZipBytes.centralHeaders(clean)[0] + 10, 8)
        ZipBytes.set16(&compressed, ZipBytes.localHeader(clean, entry: 0) + 8, 8)
        assertRefused(compressed, .unsupported("compressed entries"))

        var encrypted = clean
        ZipBytes.set16(&encrypted, ZipBytes.centralHeaders(clean)[0] + 8, 0x0801)
        assertRefused(encrypted, .unsupported("encryption"))

        var descriptor = clean
        ZipBytes.set16(&descriptor, ZipBytes.centralHeaders(clean)[0] + 8, 0x0808)
        assertRefused(descriptor, .unsupported("options the app does not read"))
    }

    func testRefusesAnArchiveComment() throws {
        var data = try archive(sample)
        ZipBytes.set16(&data, ZipBytes.endRecord(data) + 20, 5)
        data.append(contentsOf: Array("hello".utf8))
        assertRefused(data, .unsupported("an archive comment"))
    }

    func testRefusesZIP64Markers() throws {
        let clean = try archive(sample)
        var entries = clean
        ZipBytes.set16(&entries, ZipBytes.endRecord(clean) + 8, 0xFFFF)
        ZipBytes.set16(&entries, ZipBytes.endRecord(clean) + 10, 0xFFFF)
        assertRefused(entries, .unsupported("ZIP64"))

        var size = clean
        ZipBytes.set32(&size, ZipBytes.centralHeaders(clean)[0] + 20, 0xFFFF_FFFF)
        ZipBytes.set32(&size, ZipBytes.centralHeaders(clean)[0] + 24, 0xFFFF_FFFF)
        assertRefused(size, .unsupported("ZIP64"))
    }

    func testRefusesHeadersThatDisagree() throws {
        let clean = try archive(sample)
        var name = clean
        name[ZipBytes.localHeader(clean, entry: 0) + 30] = UInt8(ascii: "q")
        assertRefused(name, .malformed("headers of presets/a.milk disagree"))

        var crc = clean
        ZipBytes.set32(&crc, ZipBytes.localHeader(clean, entry: 1) + 14, 1234)
        assertRefused(crc, .malformed("headers of presets/b.milk disagree"))
    }

    func testRefusesOverlappingEntries() throws {
        let clean = try archive(sample)
        var overlap = clean
        // The second entry claims to start where the first does.
        ZipBytes.set32(&overlap, ZipBytes.centralHeaders(clean)[1] + 42, ZipBytes.localHeader(clean, entry: 0))
        XCTAssertThrowsError(try StoredZipReader.read(overlap, limits: limits)) { error in
            guard case .malformed = error as? StoredZipError else { return XCTFail("\(error)") }
        }
    }

    func testRefusesOutOfBoundsOffsets() throws {
        let clean = try archive(sample)
        var far = clean
        ZipBytes.set32(&far, ZipBytes.centralHeaders(clean)[2] + 42, clean.count + 100)
        XCTAssertThrowsError(try StoredZipReader.read(far, limits: limits)) { error in
            guard case .malformed = error as? StoredZipError else { return XCTFail("\(error)") }
        }
    }

    func testRefusesTooManyEntries() throws {
        let data = try archive((0..<11).map { ("f\($0)", "x") })
        assertRefused(data, .tooManyEntries(10))
    }

    func testRefusesAnOversizeEntryBeforeReadingIt() throws {
        let big = String(repeating: "x", count: 1_025)
        var data = try archive([("big.milk", big)])
        // Corrupt the bytes: a reader that read them first would report a checksum mismatch.
        data[ZipBytes.dataStart(data, entry: 0)] ^= 0xFF
        assertRefused(data, .entryTooLarge("big.milk"))
    }

    func testPerPathLimitOverride() throws {
        let data = try archive([("manifest.json", String(repeating: "x", count: 2_000))])
        var bigger = limits
        bigger.entryLimits = ["manifest.json": 4_096]
        XCTAssertEqual(try StoredZipReader.read(data, limits: bigger).count, 1)
        assertRefused(data, .entryTooLarge("manifest.json"))
    }

    func testRefusesAnArchiveOverTheTotalLimit() {
        let small = StoredZipLimits(maxEntries: 10, maxEntryBytes: 1_024, maxArchiveBytes: 100)
        XCTAssertThrowsError(try StoredZipReader.read(try archive(sample), limits: small)) {
            XCTAssertEqual($0 as? StoredZipError, .archiveTooLarge)
        }
    }

    func testRefusesUnsafeNamesInTheArchive() throws {
        // A safe name of the same length is written, then replaced in both headers.
        for badPath in ["../../../a.mi", "/etc/passwd.x", "presets\\a.milk", "C:/presets/a.m"] {
            var data = try archive([(String(repeating: "n", count: badPath.utf8.count), "x")])
            let central = ZipBytes.centralHeaders(data)[0]
            let local = ZipBytes.localHeader(data, entry: 0)
            for (index, byte) in badPath.utf8.enumerated() {
                data[central + 46 + index] = byte
                data[local + 30 + index] = byte
            }
            assertRefused(data, .unsafePath(badPath))
        }
    }

    func testRefusesNamesThatDifferOnlyInCase() throws {
        var data = try archive([("presets/a.milk", "1"), ("presets/b.milk", "2")])
        let central = ZipBytes.centralHeaders(data)[1]
        let local = ZipBytes.localHeader(data, entry: 1)
        data[central + 46 + 8] = UInt8(ascii: "A")
        data[local + 30 + 8] = UInt8(ascii: "A")
        assertRefused(data, .duplicatePath("presets/A.milk"))
    }

    func testRefusesNamesThatAreNotUTF8() throws {
        var data = try archive([("ab", "1")])
        let central = ZipBytes.centralHeaders(data)[0]
        let local = ZipBytes.localHeader(data, entry: 0)
        data[central + 46] = 0xFF
        data[local + 30] = 0xFF
        assertRefused(data, .malformed("a name that is not UTF-8"))
    }

    func testErrorsHaveWords() {
        for error in [StoredZipError.notAZip, .truncated, .unsupported("compressed entries"), .malformed("x"), .unsafePath("../x"),
                      .duplicatePath("a"), .tooManyEntries(3), .entryTooLarge("a"), .archiveTooLarge, .checksumMismatch("a"), .finished] {
            XCTAssertFalse(error.message.isEmpty, "\(error)")
        }
    }

    // MARK: - FILE-001-T03: symbolic links and special files (FILE-001-R14)

    private func withMode(_ mode: Int, madeBy: Int = 0x0314) throws -> Data {
        var data = try archive(sample)
        let central = ZipBytes.centralHeaders(data)[1]
        ZipBytes.set16(&data, central + 4, madeBy)
        ZipBytes.set32(&data, central + 38, mode << 16)
        return data
    }

    func testSymbolicLinkAndSpecialEntriesAreRefused() throws {
        let refusal = StoredZipError.unsupported("symbolic links or special files")
        assertRefused(try withMode(0o120777), refusal)     // symbolic link
        assertRefused(try withMode(0o040755), refusal)     // directory
        assertRefused(try withMode(0o010644), refusal)     // FIFO
    }

    func testRegularAndUnsetModesAndNonUnixHostsAreRead() throws {
        XCTAssertEqual(try StoredZipReader.read(try withMode(0o100600), limits: limits).count, 3)
        XCTAssertEqual(try StoredZipReader.read(try withMode(0), limits: limits).count, 3)
        // An MS-DOS host (0) carries no Unix type in the high bits.
        XCTAssertEqual(try StoredZipReader.read(try withMode(0o120777, madeBy: 0x0014), limits: limits).count, 3)
    }
}
