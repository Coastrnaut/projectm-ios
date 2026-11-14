// LooseZipReaderTests.swift — PRE-013-T03 (specs/174-pre-013-bulk-import; contract C1; research
// PRE-013-D1, D2): per-entry verdicts, reading stored and deflated entries, zip slip, links,
// encryption, other methods, damage and bounds.
import Foundation
import LocalPortability
import XCTest

final class LooseZipReaderTests: XCTestCase {
    private func verdicts(_ zip: RawZip) throws -> [String: LooseZipEntry.Verdict] {
        var result: [String: LooseZipEntry.Verdict] = [:]
        for entry in try LooseZipReader.entries(zip.build()) { result[entry.path] = entry.verdict }
        return result
    }

    func testStoredEntriesReadBack() throws {
        var zip = RawZip()
        zip.add("a.milk", text: "alpha")
        zip.add("folder/b.milk", text: "bravo")
        zip.add("folder/", Data(), unixMode: 0o040755)
        let data = zip.build()
        let entries = try LooseZipReader.entries(data)
        XCTAssertEqual(entries.map(\.path), ["a.milk", "folder/b.milk", "folder"])
        XCTAssertEqual(entries.map(\.verdict), [.file, .file, .directory])
        XCTAssertEqual(try LooseZipReader.data(of: entries[1], in: data, limit: 100), Data("bravo".utf8))
        XCTAssertThrowsError(try LooseZipReader.data(of: entries[1], in: data, limit: 4)) { error in
            XCTAssertEqual(error as? LooseZipError, .tooLarge)
        }
    }

    func testDeflatedEntriesReadBack() throws {
        guard RawZip.canDeflate, LooseZipReader.readsDeflate else { throw XCTSkip("no Compression framework on this platform") }
        let text = String(repeating: "per_frame_1=zoom = zoom + 0.01*sin(time);\n", count: 40)
        var zip = RawZip()
        zip.add("deflated.milk", text: text, method: 8)
        let data = zip.build()
        let entry = try XCTUnwrap(LooseZipReader.entries(data).first)
        XCTAssertEqual(entry.verdict, .file)
        XCTAssertLessThan(data.count, text.utf8.count, "the entry really is compressed")
        XCTAssertEqual(try LooseZipReader.data(of: entry, in: data, limit: 1 << 20), Data(text.utf8))
    }

    func testUnsafeNamesAreNeverReadable() throws {
        var zip = RawZip()
        zip.add("../evil.milk", text: "x")
        zip.add("/abs.milk", text: "x")
        zip.add("a\\b.milk", text: "x")
        zip.add("ok/../../up.milk", text: "x")
        zip.add("safe.milk", text: "x")
        let found = try verdicts(zip)
        XCTAssertEqual(found["../evil.milk"], .unsafePath(.dotComponent))
        XCTAssertEqual(found["/abs.milk"], .unsafePath(.absolute))
        XCTAssertEqual(found["a\\b.milk"], .unsafePath(.backslash))
        XCTAssertEqual(found["ok/../../up.milk"], .unsafePath(.dotComponent))
        XCTAssertEqual(found["safe.milk"], .file)
        let data = zip.build()
        let evil = try XCTUnwrap(LooseZipReader.entries(data).first)
        XCTAssertThrowsError(try LooseZipReader.data(of: evil, in: data, limit: 100)) { error in
            XCTAssertEqual(error as? LooseZipError, .notReadable)
        }
    }

    func testLinksEncryptionAndOtherMethodsAreNotFiles() throws {
        var zip = RawZip()
        zip.add("link.milk", Data("target.milk".utf8), unixMode: 0o120777)
        zip.add("secret.milk", Data("x".utf8), flags: 0x0801)
        zip.add("bzip.milk", Data("x".utf8), method: 12)
        zip.add("dos.milk", Data("x".utf8), unixMode: nil)
        let found = try verdicts(zip)
        XCTAssertEqual(found["link.milk"], .link)
        XCTAssertEqual(found["secret.milk"], .encrypted)
        XCTAssertEqual(found["bzip.milk"], .unsupportedMethod(12))
        XCTAssertEqual(found["dos.milk"], .file)
    }

    func testDamagedEntryThrowsAndTheOthersStillRead() throws {
        var zip = RawZip()
        zip.add("good.milk", text: "good")
        zip.add("bad.milk", text: "badd")
        var data = zip.build()
        let entries = try LooseZipReader.entries(data)
        // Flip a data byte of the second entry: its CRC no longer matches.
        let local = 30 + "good.milk".utf8.count + 4
        data[data.startIndex + local + 30 + "bad.milk".utf8.count] ^= 0xFF
        XCTAssertThrowsError(try LooseZipReader.data(of: entries[1], in: data, limit: 100)) { error in
            XCTAssertEqual(error as? LooseZipError, .damaged("checksum"))
        }
        XCTAssertEqual(try LooseZipReader.data(of: entries[0], in: data, limit: 100), Data("good".utf8))
    }

    func testNotAZipAndTruncatedDirectoryAreRefusedAsAWhole() throws {
        XCTAssertThrowsError(try LooseZipReader.entries(Data("not a zip at all, just text".utf8)))
        XCTAssertThrowsError(try LooseZipReader.entries(Data()))
        var zip = RawZip()
        zip.add("a.milk", text: "alpha")
        var data = zip.build()
        // The end record claims more entries than the central directory holds.
        let end = data.count - 22
        data[data.startIndex + end + 8] = 5
        data[data.startIndex + end + 10] = 5
        XCTAssertThrowsError(try LooseZipReader.entries(data)) { error in
            XCTAssertEqual(error as? LooseZipError, .unreadable("central directory"))
        }
    }

    func testArchiveWithACommentIsReadable() throws {
        var zip = RawZip()
        zip.add("a.milk", text: "alpha")
        var data = zip.build()
        let comment = Data("made by some tool".utf8)
        data[data.startIndex + data.count - 2] = UInt8(comment.count)
        data.append(comment)
        XCTAssertEqual(try LooseZipReader.entries(data).map(\.path), ["a.milk"])
    }
}
