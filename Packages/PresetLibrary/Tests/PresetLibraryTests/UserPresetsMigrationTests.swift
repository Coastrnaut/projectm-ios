// PRE-015-T02: the user-preset record moves to version 2 (PRE-015-R21; research D4). Version 1 is
// PRE-012's golden fixture, which stays immutable; version 2 adds an optional duplicate origin
// and edit date.
import XCTest
@testable import PresetLibrary

final class UserPresetsMigrationTests: XCTestCase {
    private typealias F = UserPresetFixtures
    private struct WriteFailure: Error {}

    private func golden(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Golden"))
        return try Data(contentsOf: url)
    }

    func testTheCurrentVersionIsTwo() {
        XCTAssertEqual(UserPresetsFile.currentVersion, 2)
        XCTAssertNotNil(UserPresetsFile.migrations[1])
    }

    func testVersion1MigratesWithEveryRecordIntact() throws {
        let v1 = try golden("user-presets-v1")
        let migrated = try UserPresetsFile.decode(v1)
        XCTAssertEqual(migrated.migratedFrom, 1)
        XCTAssertEqual(migrated.file.schemaVersion, 2)
        XCTAssertEqual(migrated.file.presets.count, 4)
        for preset in migrated.file.presets {
            XCTAssertNil(preset.duplicateOf)
            XCTAssertNil(preset.modifiedAt)
            XCTAssertEqual(preset.license.origin, .userImport)
        }
        XCTAssertEqual(migrated.file.presets[0].name, "Sunrise 🌅 שלום")
        XCTAssertEqual(migrated.file.presets[3].quarantine?.code, "aReasonThisVersionDoesNotKnow")
    }

    func testTheMigrationStepChangesOnlyTheVersion() throws {
        let v1 = try golden("user-presets-v1")
        let step = try XCTUnwrap(UserPresetsFile.migrations[1])
        let out = try step(v1)
        var before = try XCTUnwrap(JSONSerialization.jsonObject(with: v1) as? [String: Any])
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: out) as? [String: Any])
        XCTAssertEqual(after["schemaVersion"] as? Int, 2)
        before["schemaVersion"] = 2
        XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after))
        // Pure: the same input gives the same output.
        XCTAssertEqual(try step(v1), out)
    }

    func testTheGoldenVersion2FixtureDecodesIntact() throws {
        let decoded = try UserPresetsFile.decode(try golden("user-presets-v2"))
        XCTAssertNil(decoded.migratedFrom)
        let presets = decoded.file.presets
        XCTAssertEqual(presets.count, 2)
        XCTAssertNil(presets[0].duplicateOf)
        XCTAssertEqual(presets[0].modifiedAt, Date(timeIntervalSince1970: 1_794_481_200))
        let copy = presets[1]
        XCTAssertEqual(copy.license.origin, .bundledDuplicate)
        XCTAssertFalse(copy.license.rightsVerified)
        let origin = try XCTUnwrap(copy.duplicateOf)
        XCTAssertEqual(origin.presetID, "cream-of-the-crop/Folder/Example.milk")
        XCTAssertEqual(origin.packTitle, "Cream of the Crop")
        XCTAssertTrue(origin.requiresLibraryUnlock)
        XCTAssertEqual(origin.blobHash, "0123456789abcdef0123456789abcdef01234567")
        XCTAssertEqual(try UserPresetsFile.decode(try decoded.file.encode()).file, decoded.file)
    }

    func testOriginAndDuplicateRecordMustAgree() throws {
        for change in [{ (p: inout [[String: Any]]) in p[1]["duplicateOf"] = nil },
                       { (p: inout [[String: Any]]) in
                           var license = p[0]["license"] as! [String: Any]
                           license["origin"] = "bundledDuplicate"
                           p[0]["license"] = license
                       },
                       { (p: inout [[String: Any]]) in
                           p[0]["duplicateOf"] = p[1]["duplicateOf"]
                       },
                       { (p: inout [[String: Any]]) in
                           var origin = p[1]["duplicateOf"] as! [String: Any]
                           origin["blobHash"] = "../not-a-hash"
                           p[1]["duplicateOf"] = origin
                       },
                       { (p: inout [[String: Any]]) in
                           var origin = p[1]["duplicateOf"] as! [String: Any]
                           origin["licenseStatement"] = String(repeating: "x", count: 1_001)
                           p[1]["duplicateOf"] = origin
                       }] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try golden("user-presets-v2")) as? [String: Any])
            var presets = try XCTUnwrap(object["presets"] as? [[String: Any]])
            change(&presets)
            object["presets"] = presets
            XCTAssertThrowsError(try UserPresetsFile.decode(try JSONSerialization.data(withJSONObject: object))) {
                XCTAssertEqual($0 as? UserPresetsFile.ReadError, .unreadable)
            }
        }
    }

    func testAStoreKeepsTheVersion1BackupUntilTheMigratedFileIsSaved() throws {
        let directory = try F.tempDirectory(self)
        let v1 = try golden("user-presets-v1")
        try v1.write(to: directory.appendingPathComponent(UserPresetStore.indexFileName))
        let backup = directory.appendingPathComponent("index.v1.backup.json")

        // The migrated file cannot be saved: the original stays, with its backup.
        let failing = UserPresetStore(directory: directory, write: { _, _ in throw WriteFailure() })
        XCTAssertEqual(failing.availability, .available)
        XCTAssertEqual(failing.presets.count, 4)
        XCTAssertEqual(try Data(contentsOf: backup), v1)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(UserPresetStore.indexFileName)), v1)

        // The next launch saves it; the backup goes.
        let store = UserPresetStore(directory: directory)
        XCTAssertEqual(store.presets.count, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        let saved = try Data(contentsOf: directory.appendingPathComponent(UserPresetStore.indexFileName))
        XCTAssertNil(try UserPresetsFile.decode(saved).migratedFrom)
    }

    func testAVersion3FileIsNeitherReadNorChanged() throws {
        let directory = try F.tempDirectory(self)
        let newer = Data(#"{"schemaVersion":3,"presets":[]}"#.utf8)
        try newer.write(to: directory.appendingPathComponent(UserPresetStore.indexFileName))
        let store = UserPresetStore(directory: directory)
        XCTAssertEqual(store.availability, .newerFormat(version: 3))
        XCTAssertEqual(F.snapshot(directory), ["/index.json": newer])
    }
}
