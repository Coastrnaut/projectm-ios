// DocumentShapeTests.swift — FILE-007-T07, T08 (FILE-007-R5 to R7, R9, S2): the preset archive manifest
// and the two local library files are checked against their declared schemas before anything is
// decoded. A hostile preset archive manifest is refused with the exact typed reason; a hostile
// collections or user presets file is "unreadable" (the store sets it aside); golden files still read.
import Foundation
import LocalPortability
import XCTest
@testable import PresetLibrary

final class DocumentShapeTests: XCTestCase {
    private func text(_ s: String) -> Data { Data(s.utf8) }

    private func golden(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Golden"))
        return try Data(contentsOf: url)
    }

    // MARK: Schemas declared once (R5)

    func testSchemasAreDeclaredWithTheirFormats() {
        XCTAssertEqual(UserPresetArchiveFormat.manifestSchema.name, UserPresetArchiveFormat.name)
        XCTAssertEqual(UserPresetArchiveFormat.manifestSchema.currentVersion, UserPresetArchiveFormat.version)
        XCTAssertEqual(UserPresetArchiveFormat.manifestSchema.limits,
                       JSONLimits(maxBytes: 4 << 20, maxDepth: 8, maxStringBytes: 16_384, maxNumberBytes: 32, maxElements: 4_096))
        XCTAssertEqual(PresetCollectionsFile.schema.currentVersion, PresetCollectionsFile.currentVersion)
        XCTAssertEqual(PresetCollectionsFile.schema.limits.maxBytes, PresetCollectionLimits.maxFileBytes)
        XCTAssertEqual(PresetCollectionsFile.schema.limits.maxElements, 16_384)
        XCTAssertEqual(UserPresetsFile.schema.currentVersion, UserPresetsFile.currentVersion)
        XCTAssertEqual(UserPresetsFile.schema.limits.maxBytes, PresetImportLimits.maxIndexBytes)
        XCTAssertTrue(UserPresetArchiveFormat.manifestSchema.limits.requiresObjectRoot)
        // Local files: a version-0 document (older format, read only by a migration step) may be any value.
        XCTAssertFalse(PresetCollectionsFile.schema.limits.requiresObjectRoot)
        XCTAssertFalse(UserPresetsFile.schema.limits.requiresObjectRoot)
        for schema in [UserPresetArchiveFormat.manifestSchema, PresetCollectionsFile.schema, UserPresetsFile.schema] {
            XCTAssertTrue(schema.limits.rejectsDuplicateKeys, schema.name)
            XCTAssertEqual(schema.verdict(for: schema.currentVersion + 1), .newer, schema.name)
        }
    }

    // MARK: Preset archive manifest (T07)

    private func archive(manifest: String) throws -> Data {
        var out = Data()
        let writer = PortableArchiveWriter(modified: Date(timeIntervalSince1970: 1_794_571_200)) { (chunk: Data) in out.append(chunk) }
        _ = try writer.add(path: "presets/a.milk", data: text("[preset00]\n"))
        try writer.finish(manifest: text(manifest))
        return out
    }

    private func assertArchiveRefused(_ manifest: String, _ expected: JSONShapeError, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try archive(manifest: manifest)
        XCTAssertThrowsError(try UserPresetArchiveReader.read(data), file: file, line: line) { error in
            XCTAssertEqual(error as? UserPresetArchiveError, .archive(.manifestRejected(expected)), file: file, line: line)
        }
    }

    func testHostilePresetArchiveManifestsAreRefusedBeforeDecoding() throws {
        try assertArchiveRefused("{\"presets\":" + String(repeating: "[", count: 10_000), .nestingTooDeep(offset: 18, limit: 8))
        try assertArchiveRefused("{\"files\":[],\"files\":[]}", .duplicateKey(offset: 18))
        try assertArchiveRefused("{\"presets\":[" + Array(repeating: "0", count: 5_000).joined(separator: ",") + "]}",
                                 .tooManyElements(offset: 8_204, limit: 4_096))
        try assertArchiveRefused("{\"appVersion\":\"" + String(repeating: "x", count: 20_000) + "\"}",
                                 .stringTooLong(offset: 15 + 16_384, limit: 16_384))
        try assertArchiveRefused("{\"formatVersion\":" + String(repeating: "9", count: 100) + "}", .numberTooLong(offset: 17 + 32, limit: 32))
        try assertArchiveRefused("[]", .notAnObject(offset: 0))
    }

    // MARK: Local files (T08)

    func testHostileCollectionsFilesAreUnreadable() throws {
        let hostile: [(String, Data)] = [
            ("deep", text("{\"schemaVersion\":1,\"collections\":" + String(repeating: "[", count: 1_000))),
            // Without the check the second key would win and the file would read as "newer".
            ("duplicate version", text("{\"schemaVersion\":1,\"schemaVersion\":2,\"collections\":[]}")),
            ("byte order mark", Data([0xEF, 0xBB, 0xBF]) + text("{\"schemaVersion\":1,\"collections\":[]}")),
            ("invalid UTF-8", text("{\"schemaVersion\":1,\"collections\":[{\"id\":\"a\",\"name\":\"") + Data([0xC0, 0xAF]) + text("\",\"presets\":[]}]}")),
        ]
        for (name, data) in hostile {
            XCTAssertThrowsError(try PresetCollectionsFile.decode(data), name) { error in
                XCTAssertEqual(error as? PresetCollectionsFile.ReadError, .unreadable, name)
            }
        }
        let decoded = try PresetCollectionsFile.decode(try golden("collections-v1"))
        XCTAssertNil(decoded.migratedFrom)
    }

    func testHostileUserPresetsFilesAreUnreadable() throws {
        let hostile: [(String, Data)] = [
            ("deep", text("{\"schemaVersion\":2,\"presets\":" + String(repeating: "[", count: 1_000))),
            ("duplicate version", text("{\"schemaVersion\":2,\"schemaVersion\":3,\"presets\":[]}")),
            ("trailing data", text("{\"schemaVersion\":2,\"presets\":[]} {}")),
        ]
        for (name, data) in hostile {
            XCTAssertThrowsError(try UserPresetsFile.decode(data), name) { error in
                XCTAssertEqual(error as? UserPresetsFile.ReadError, .unreadable, name)
            }
        }
        XCTAssertNil(try UserPresetsFile.decode(try golden("user-presets-v2")).migratedFrom)
        XCTAssertEqual(try UserPresetsFile.decode(try golden("user-presets-v1")).migratedFrom, 1)
    }

    func testAMigrationStepsOutputIsCheckedToo() throws {
        let deep: UserPresetsFile.Migration = { (_: Data) throws -> Data in
            Data(("{\"schemaVersion\":2,\"presets\":" + String(repeating: "[", count: 100)).utf8)
        }
        XCTAssertThrowsError(try UserPresetsFile.decode(text("{\"schemaVersion\":1,\"presets\":[]}"), migrations: [1: deep])) { error in
            XCTAssertEqual(error as? UserPresetsFile.ReadError, .unreadable)
        }
    }

    func testANewerValidFileIsStillRecognisedAsNewer() {
        XCTAssertThrowsError(try UserPresetsFile.decode(text("{\"schemaVersion\":3,\"presets\":[]}"))) { error in
            XCTAssertEqual(error as? UserPresetsFile.ReadError, .newerVersion(3))
        }
        XCTAssertThrowsError(try PresetCollectionsFile.decode(text("{\"schemaVersion\":2,\"collections\":[]}"))) { error in
            XCTAssertEqual(error as? PresetCollectionsFile.ReadError, .newerVersion(2))
        }
    }
}
