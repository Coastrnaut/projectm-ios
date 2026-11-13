// SceneArchiveTamperTests.swift — FILE-002-T04, T07: the tamper table. Each case changes the FILE-001
// fixture archive (written by SceneArchiveWriter, so every entry is listed with its size and SHA-256)
// and must be refused with its exact error naming the entry (FILE-002-R2 to R4, S1). The reader writes
// nothing; "before import modifies library" is proven in the app (SceneArchiveTamperImportTests).
//
// "CRC stale" = the bytes changed in place, the ZIP CRC-32 left as written (accidental damage or a
// naive edit). "CRC repaired" = the archive rewritten so every CRC-32 matches (an editor that rezips).
import Foundation
import LocalPortability
@testable import SceneArchive
import SceneFormat
import XCTest

final class SceneArchiveTamperTests: XCTestCase {
    private typealias Entries = [(path: String, data: Data)]

    private func entries(_ archive: Data) throws -> Entries {
        try StoredZipReader.read(archive, limits: SceneArchiveLimits.standard.portable.zip)
            .map { (entry: StoredZipEntry) -> (path: String, data: Data) in (entry.path, entry.data) }
    }

    /// Rewrites the entries in order (every CRC-32 correct).
    private func rezip(_ entries: Entries) throws -> Data {
        var out = Data()
        let zip = StoredZipWriter(modified: ArchiveFixtures.date) { (chunk: Data) in out.append(chunk) }
        for entry in entries { try zip.add(path: entry.path, data: entry.data) }
        try zip.finish()
        return out
    }

    /// The manifest as JSON, edited, written back with sorted keys.
    private func editingManifest(_ entries: Entries, _ edit: (inout [[String: Any]]) -> Void) throws -> Entries {
        try entries.map { (entry: (path: String, data: Data)) -> (path: String, data: Data) in
            guard entry.path == PortableArchive.manifestPath else { return entry }
            var manifest = try XCTUnwrap(try JSONSerialization.jsonObject(with: entry.data) as? [String: Any])
            var files = try XCTUnwrap(manifest["files"] as? [[String: Any]])
            edit(&files)
            manifest["files"] = files
            return (entry.path, try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .withoutEscapingSlashes]))
        }
    }

    private func setRecord(_ files: inout [[String: Any]], _ path: String, _ key: String, _ value: Any) {
        for index in files.indices where files[index]["path"] as? String == path { files[index][key] = value }
    }

    private func replacing(_ entries: Entries, _ path: String, with data: Data) -> Entries {
        entries.map { (entry: (path: String, data: Data)) -> (path: String, data: Data) in entry.path == path ? (path, data) : entry }
    }

    /// The offset of `path`'s stored bytes in the archive.
    private func dataStart(_ archive: Data, _ path: String) throws -> Int {
        let names = try entries(archive).map(\.path)
        return ZipHeaders.dataStart(archive, entry: try XCTUnwrap(names.firstIndex(of: path)))
    }

    private func flipped(_ data: Data) -> Data {
        var copy = data
        copy[copy.startIndex + copy.count / 2] ^= 0x01
        return copy
    }

    private func read(_ archive: Data) throws -> SceneArchiveContents {
        try SceneArchiveReader.read(archive, registry: try ArchiveFixtures.registry())
    }

    private func refusal(_ archive: Data) throws -> SceneArchiveError? {
        do {
            _ = try read(archive)
            return nil
        } catch let error as SceneArchiveError {
            return error
        }
    }

    // MARK: - FILE-002-T04: the tamper table (FILE-002-S1)

    func testEveryTamperCaseIsRefusedWithItsExactErrorNamingTheEntry() throws {
        let good = try ArchiveFixtures.archive()
        let original = try entries(good)
        XCTAssertEqual(original.map(\.path), ["scene.json", "assets/clip.mov", "assets/photo1.png", "manifest.json"])
        XCTAssertEqual(try read(good).media.count, 2, "the untampered control is accepted")
        let bytes: [String: Data] = Dictionary(uniqueKeysWithValues: original.map { (e: (path: String, data: Data)) -> (String, Data) in (e.path, e.data) })
        let files = ["scene.json", "assets/clip.mov", "assets/photo1.png"]

        var cases: [(name: String, archive: Data, expected: SceneArchiveError)] = []
        for path in files {
            let entryBytes = try XCTUnwrap(bytes[path])
            // 1-3: a byte changed in place, CRC-32 stale → the ZIP layer.
            var inPlace = good
            let start = try dataStart(good, path)
            inPlace[inPlace.startIndex + start + entryBytes.count / 2] ^= 0x01
            cases.append(("\(path): byte changed, CRC stale", inPlace, .archive(.zip(.checksumMismatch(path)))))
            // 4-6: a byte changed, CRC-32 repaired, manifest stale → the SHA-256.
            cases.append(("\(path): byte changed, CRC repaired", try rezip(replacing(original, path, with: flipped(entryBytes))),
                          .archive(.checksumMismatch(path))))
            // 7-9: the manifest's size changed.
            cases.append(("\(path): size field changed", try rezip(try editingManifest(original) { (f: inout [[String: Any]]) in
                setRecord(&f, path, "byteCount", entryBytes.count + 1)
            }), .archive(.lengthMismatch(path))))
            // 10-12: the manifest's checksum changed (CRC-32 of the manifest repaired).
            cases.append(("\(path): checksum field changed", try rezip(try editingManifest(original) { (f: inout [[String: Any]]) in
                setRecord(&f, path, "sha256", String(repeating: "0", count: 64))
            }), .archive(.checksumMismatch(path))))
        }
        let video = "assets/clip.mov", videoBytes = try XCTUnwrap(bytes[video])
        // 13: checksum edited to match a changed file, the file's CRC-32 left stale → the ZIP layer.
        var matchedButStale = try rezip(try editingManifest(original) { (f: inout [[String: Any]]) in
            setRecord(&f, video, "sha256", PortableSHA256.hex(flipped(videoBytes)))
        })
        let videoStart = try dataStart(matchedButStale, video)
        matchedButStale[matchedButStale.startIndex + videoStart + videoBytes.count / 2] ^= 0x01
        cases.append(("checksum matches the changed video, CRC stale", matchedButStale, .archive(.zip(.checksumMismatch(video)))))
        // 14: the manifest itself changed in place (its CRC-32 stale).
        var manifestEdited = good
        let manifestStart = try dataStart(good, "manifest.json")
        manifestEdited[manifestEdited.startIndex + manifestStart + 10] ^= 0x01
        cases.append(("manifest changed in place", manifestEdited, .archive(.zip(.checksumMismatch("manifest.json")))))
        // 15: an extra entry not in the manifest (the plain scene leaves room under the entry limit).
        let plain = try entries(try SceneArchiveWriter.data(document: ArchiveFixtures.plainScene(), media: [],
                                                             registry: try ArchiveFixtures.registry(), modified: ArchiveFixtures.date))
        cases.append(("extra entry", try rezip([plain[0], ("assets/extra.png", ArchiveFixtures.pngBytes), plain[1]]),
                      .archive(.unlistedFile("assets/extra.png"))))
        // 16: an entry renamed (the listed name is absent).
        let renamed = original.map { (e: (path: String, data: Data)) -> (path: String, data: Data) in
            e.path == "assets/photo1.png" ? ("assets/photo2.png", e.data) : e
        }
        cases.append(("entry renamed", try rezip(renamed), .archive(.missingFile("assets/photo1.png"))))
        // 17-20: malformed digests and a negative size → named record refusal.
        let goodDigest = PortableSHA256.hex(videoBytes)
        for (label, value) in [("upper-case digest", goodDigest.uppercased() as Any), ("63-character digest", String(goodDigest.dropLast()) as Any),
                               ("non-hex digest", String(goodDigest.dropLast()) + "z" as Any)] {
            cases.append((label, try rezip(try editingManifest(original) { (f: inout [[String: Any]]) in setRecord(&f, video, "sha256", value) }),
                          .archive(.invalidRecord(video))))
        }
        cases.append(("negative size", try rezip(try editingManifest(original) { (f: inout [[String: Any]]) in setRecord(&f, video, "byteCount", -1) }),
                      .archive(.invalidRecord(video))))

        XCTAssertEqual(cases.count, 20)
        for testCase in cases {
            let error = try refusal(testCase.archive)
            XCTAssertEqual(error, testCase.expected, testCase.name)
            let named = testCase.expected.message
            XCTAssertTrue(["scene.json", "assets/", "manifest.json"].contains { (name: String) -> Bool in named.contains(name) },
                          "\(testCase.name): the message names the entry: \(named)")
        }
    }

    /// The honest limit (FILE-002-R7, research D5): a consistent edit of a file, its record and its
    /// CRC-32 passes the checksum layer. No signature exists in format version 1.
    func testAConsistentEditOfFileRecordAndCRCIsNotDetectedByChecksums() throws {
        let original = try entries(try ArchiveFixtures.archive())
        let scene = try XCTUnwrap(original.first { (e: (path: String, data: Data)) -> Bool in e.path == "scene.json" }?.data)
        let forged = Data(String(decoding: scene, as: UTF8.self).replacingOccurrences(of: "Night Drive", with: "Night Drivf").utf8)
        XCTAssertNotEqual(forged, scene)
        let consistent = try rezip(try editingManifest(replacing(original, "scene.json", with: forged)) { (f: inout [[String: Any]]) in
            setRecord(&f, "scene.json", "sha256", PortableSHA256.hex(forged))
            setRecord(&f, "scene.json", "byteCount", forged.count)
        })
        XCTAssertEqual(try read(consistent).document.name, "Night Drivf", "accepted: checksums give integrity, not authenticity")
    }

    // MARK: - FILE-002-T07: every entry carries its size and SHA-256 (FILE-002-R1, R8)

    func testEveryEntryIsListedWithItsSizeAndChecksum() throws {
        let archive = try entries(try ArchiveFixtures.archive())
        let manifestData = try XCTUnwrap(archive.last { (e: (path: String, data: Data)) -> Bool in e.path == PortableArchive.manifestPath }?.data)
        let manifest = try XCTUnwrap(try JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(manifest["formatVersion"] as? Int, 1, "format version unchanged (R8)")
        let records = try XCTUnwrap(manifest["files"] as? [[String: Any]])
        let stored = archive.filter { (e: (path: String, data: Data)) -> Bool in e.path != PortableArchive.manifestPath }
        XCTAssertEqual(records.count, stored.count, "one record per entry, none missing")
        for entry in stored {
            let matching = records.filter { (r: [String: Any]) -> Bool in r["path"] as? String == entry.path }
            XCTAssertEqual(matching.count, 1, entry.path)
            var hasher = PortableSHA256.Hasher()
            hasher.update(entry.data)
            XCTAssertEqual(matching.first?["sha256"] as? String, hasher.finalize(), entry.path)
            XCTAssertEqual(matching.first?["byteCount"] as? Int, entry.data.count, entry.path)
        }
    }
}
