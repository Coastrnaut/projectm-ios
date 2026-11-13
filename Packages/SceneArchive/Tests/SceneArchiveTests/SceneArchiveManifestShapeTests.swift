// SceneArchiveManifestShapeTests.swift — FILE-007-T06 (FILE-007-R6, R9, S2): a scene archive whose
// manifest.json is hostile (deep nesting, a huge list or string, a duplicate key) is refused by the
// bounded check of `SceneArchiveFormat.manifestSchema` before any decoding, with the exact typed
// reason; an oversize manifest is refused by the ZIP layer before it is read; a valid archive reads
// as before. Every hostile archive here has correct CRC-32s, so only the manifest's shape decides.
import Foundation
import LocalPortability
@testable import SceneArchive
import XCTest

final class SceneArchiveManifestShapeTests: XCTestCase {
    /// The fixture archive with its manifest replaced by `manifest` (rezipped: every CRC-32 correct).
    private func archive(manifest: [UInt8]) throws -> Data {
        let entries = try StoredZipReader.read(try ArchiveFixtures.archive(), limits: SceneArchiveLimits.standard.portable.zip)
        var out = Data()
        let zip = StoredZipWriter(modified: ArchiveFixtures.date) { (chunk: Data) in out.append(chunk) }
        for entry in entries {
            try zip.add(path: entry.path, data: entry.path == PortableArchive.manifestPath ? Data(manifest) : entry.data)
        }
        try zip.finish()
        return out
    }

    private func refusal(_ archive: Data) throws -> SceneArchiveError? {
        do {
            _ = try SceneArchiveReader.read(archive, registry: try ArchiveFixtures.registry())
            return nil
        } catch let error as SceneArchiveError {
            return error
        }
    }

    private func originalManifest() throws -> [UInt8] {
        let entries = try StoredZipReader.read(try ArchiveFixtures.archive(), limits: SceneArchiveLimits.standard.portable.zip)
        return Array(try XCTUnwrap(entries.first(where: { (e: StoredZipEntry) -> Bool in e.path == PortableArchive.manifestPath })).data)
    }

    func testTheSchemaIsDeclaredOnce() {
        let schema = SceneArchiveFormat.manifestSchema
        XCTAssertEqual(schema.name, SceneArchiveFormat.formatName)
        XCTAssertEqual(schema.currentVersion, SceneArchiveFormat.currentVersion)
        XCTAssertEqual(schema.verdict(for: 2), .newer)
        XCTAssertEqual(schema.limits, JSONLimits(maxBytes: 65_536, maxDepth: 8, maxStringBytes: 4_096, maxNumberBytes: 32, maxElements: 256))
    }

    func testAValidArchiveStillReads() throws {
        let contents = try SceneArchiveReader.read(try ArchiveFixtures.archive(), registry: try ArchiveFixtures.registry())
        XCTAssertEqual(contents.media.count, 2)
        // The real manifest is far inside every limit.
        let summary = try SceneArchiveFormat.manifestSchema.validate(Data(try originalManifest()))
        XCTAssertLessThanOrEqual(summary.deepest, 3)
    }

    func testHostileManifestsAreRefusedBeforeDecoding() throws {
        let deep = Array(("{\"files\":" + String(repeating: "[", count: 10_000)).utf8)
        XCTAssertEqual(try refusal(try archive(manifest: deep)), .archive(.manifestRejected(.nestingTooDeep(offset: 16, limit: 8))))

        let manyElements = Array(("{\"assets\":[" + Array(repeating: "0", count: 300).joined(separator: ",") + "]}").utf8)
        XCTAssertEqual(try refusal(try archive(manifest: manyElements)), .archive(.manifestRejected(.tooManyElements(offset: 523, limit: 256))))

        let longString = Array(("{\"scene\":\"" + String(repeating: "x", count: 5_000) + "\"}").utf8)
        XCTAssertEqual(try refusal(try archive(manifest: longString)), .archive(.manifestRejected(.stringTooLong(offset: 4_106, limit: 4_096))))

        // A second "scene" key: the platform decoder would silently keep one of them.
        let original = try originalManifest()
        let key = Array("\"scene\":".utf8)
        let position = try XCTUnwrap((0...(original.count - key.count)).first { (i: Int) -> Bool in Array(original[i..<(i + key.count)]) == key })
        let prefix = Array("\"scene\":\"x\",".utf8)
        let duplicate = [original[0]] + prefix + Array(original[1...])
        XCTAssertEqual(try refusal(try archive(manifest: duplicate)),
                       .archive(.manifestRejected(.duplicateKey(offset: position + prefix.count + 6))))

        let notJSON = Array("{\"format\":\"projectm-ios.scene-archive\",".utf8)
        XCTAssertEqual(try refusal(try archive(manifest: notJSON)), .archive(.manifestRejected(.unexpectedEnd(offset: 39))))
    }

    func testAnOversizeManifestIsRefusedBeforeItIsRead() throws {
        // 100,000 bytes: over the 64 KiB manifest entry limit, refused by the ZIP layer by its header.
        let oversize = Array(("{\"note\":\"" + String(repeating: "x", count: 100_000) + "\"}").utf8)
        XCTAssertEqual(try refusal(try archive(manifest: oversize)), .archive(.zip(.entryTooLarge(PortableArchive.manifestPath))))
    }
}
