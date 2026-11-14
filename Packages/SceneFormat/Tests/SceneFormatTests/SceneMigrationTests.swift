// SceneMigrationTests.swift — the migration chain, its audit log and its refusals (SCN-013-T04, T05;
// SCN-013-R1 to R6, R11; contract M1-M3, M6).
//
// Every step here is SYNTHETIC and test-only: version 1 is the only scene format version ever written
// (research SCN-013-D1), so the app's chain is empty. These chains prove the mechanism: v1→v2→v3 on
// the raw value, and a v0→v1 chain (a made-up "version 0") through the full decode.
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneMigrationTests: XCTestCase {
    // MARK: Synthetic chains (test-only)

    /// v1→v2: renames each layer's "values" to "settings" and adds "tags": [].
    static let v1to2 = SceneMigrationStep(fromVersion: 1, identifier: "test-v1-to-v2", summary: "rename layer values, add tags") {
        (object: [String: SceneJSON], recorder: inout SceneMigrationRecorder) throws(SceneMigrationError) -> [String: SceneJSON] in
        var o = object
        if let layers = o["layers"]?.arrayValue {
            var out: [SceneJSON] = []
            for (i, layer) in layers.enumerated() {
                guard var l = layer.objectValue else {
                    throw .stepFailed(step: "test-v1-to-v2", fromVersion: 1, path: SceneJSONPath.index("$.layers", i), reason: "not an object")
                }
                let base = SceneJSONPath.index("$.layers", i)
                if let values = l.removeValue(forKey: "values") {
                    l["settings"] = values
                    recorder.renamed(SceneJSONPath.key(base, "values"), to: SceneJSONPath.key(base, "settings"), "layer values renamed")
                }
                out.append(.object(l))
            }
            o["layers"] = .array(out)
        }
        o["tags"] = .array([])
        recorder.added("$.tags", "empty tag list")
        return o
    }

    /// v2→v3: rewrites the name to upper case (a transformation).
    static let v2to3 = SceneMigrationStep(fromVersion: 2, identifier: "test-v2-to-v3", summary: "upper-case name") {
        (object: [String: SceneJSON], recorder: inout SceneMigrationRecorder) throws(SceneMigrationError) -> [String: SceneJSON] in
        var o = object
        if let name = o["name"]?.stringValue {
            o["name"] = .string(name.uppercased())
            recorder.transformed("$.name", "upper-cased")
        }
        return o
    }

    /// v0→v1: a made-up shape with the scene name under "title" (never written by any app).
    static let v0to1 = SceneMigrationStep(fromVersion: 0, identifier: "test-v0-to-v1", summary: "title to name") {
        (object: [String: SceneJSON], recorder: inout SceneMigrationRecorder) throws(SceneMigrationError) -> [String: SceneJSON] in
        var o = object
        guard let title = o.removeValue(forKey: "title") else {
            throw .stepFailed(step: "test-v0-to-v1", fromVersion: 0, path: "$.title", reason: "missing title")
        }
        o["name"] = title
        recorder.renamed("$.title", to: "$.name", "title renamed to name")
        return o
    }

    private func root(_ text: String) throws -> SceneJSON { try SceneJSON.parse(Array(text.utf8)) }

    private let v1Text = """
    {"format":"projectm-ios.scene","version":1,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Show",
     "future":{"x":1.50},"layers":[{"instance":1,"kind":"camera","values":{"gain":0.25},"extra":true}]}
    """

    // MARK: Chain

    func testStandardChainIsEmptyAndTargetsTheCurrentVersion() {
        XCTAssertTrue(SceneMigrator.standard.steps.isEmpty, "version 1 is the only version ever written")
        XCTAssertEqual(SceneMigrator.standard.targetVersion, SceneDocument.currentVersion)
        XCTAssertEqual(SceneMigrator.standard.oldestVersion, 1)
    }

    func testChainRunsInOrderLogsEachChangeAndKeepsUnknownFields() throws {
        let migrator = SceneMigrator(steps: [Self.v2to3, Self.v1to2], targetVersion: 3)   // registration order does not matter
        let result = try migrator.migrate(try root(v1Text))
        let o = try XCTUnwrap(result.root.objectValue)
        XCTAssertEqual(o["version"], .integer(3))
        XCTAssertEqual(o["name"], .string("SHOW"))
        XCTAssertEqual(o["tags"], .array([]))
        let layer = try XCTUnwrap(o["layers"]?.arrayValue?.first?.objectValue)
        XCTAssertNil(layer["values"])
        XCTAssertEqual(layer["settings"]?.objectValue?["gain"]?.numberValue?.text, "0.25")
        XCTAssertEqual(layer["extra"], .bool(true), "unknown layer field kept")
        XCTAssertEqual(o["future"]?.objectValue?["x"]?.numberValue?.text, "1.50", "unknown field kept with its number text")

        XCTAssertEqual(result.record.sourceVersion, 1)
        XCTAssertEqual(result.record.targetVersion, 3)
        XCTAssertTrue(result.record.migrated)
        XCTAssertEqual(result.record.stepCount, 2)
        XCTAssertEqual(result.record.changeCount, 3)
        XCTAssertEqual(result.record.log.map(\.description), [
            "v1->v2 test-v1-to-v2: renamed $.layers[0].values -> $.layers[0].settings: layer values renamed",
            "v1->v2 test-v1-to-v2: added $.tags: empty tag list",
            "v1->v2 test-v1-to-v2: version $.version: 1 to 2",
            "v2->v3 test-v2-to-v3: transformed $.name: upper-cased",
            "v2->v3 test-v2-to-v3: version $.version: 2 to 3",
        ])
    }

    func testStartingMidChainRunsOnlyTheRemainingSteps() throws {
        let migrator = SceneMigrator(steps: [Self.v1to2, Self.v2to3], targetVersion: 3)
        let text = v1Text.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
        let result = try migrator.migrate(try root(text))
        XCTAssertEqual(result.record.sourceVersion, 2)
        XCTAssertEqual(Set(result.record.log.map(\.step)), ["test-v2-to-v3"])
    }

    func testCurrentVersionIsUnchanged() throws {
        let input = try root(v1Text)
        let result = try SceneMigrator.standard.migrate(input)
        XCTAssertEqual(result.root, input)
        XCTAssertFalse(result.record.migrated)
        XCTAssertTrue(result.record.log.isEmpty)
    }

    // MARK: Refusals (S3)

    func testRefusals() throws {
        let chain = SceneMigrator(steps: [Self.v1to2, Self.v2to3], targetVersion: 3)
        func error(_ migrator: SceneMigrator, _ text: String) throws -> SceneMigrationError? {
            let value = try root(text)
            do throws(SceneMigrationError) {
                _ = try migrator.migrate(value)
                return nil
            } catch {
                return error
            }
        }
        let newer = v1Text.replacingOccurrences(of: "\"version\":1", with: "\"version\":4")
        XCTAssertEqual(try error(chain, newer), .newerVersion(4))
        let zero = v1Text.replacingOccurrences(of: "\"version\":1", with: "\"version\":0")
        XCTAssertEqual(try error(chain, zero), .invalidVersion("0"))
        XCTAssertEqual(try error(.standard, zero), .invalidVersion("0"))
        let fraction = v1Text.replacingOccurrences(of: "\"version\":1", with: "\"version\":1.5")
        XCTAssertEqual(try error(chain, fraction), .invalidVersion("1.5"))
        XCTAssertEqual(try error(chain, #"{"format":"other","version":1}"#), .notAScene)

        let gap = SceneMigrator(steps: [Self.v2to3], targetVersion: 3)
        XCTAssertEqual(try error(gap, v1Text), .missingStep(fromVersion: 1))

        let broken = v1Text.replacingOccurrences(of: #"[{"instance""#, with: #"[7,{"instance""#)
        XCTAssertEqual(try error(chain, broken),
                       .stepFailed(step: "test-v1-to-v2", fromVersion: 1, path: "$.layers[0]", reason: "not an object"))
    }

    func testDecodeMapsMigrationRefusalsToDecodeErrors() throws {
        let gap = SceneMigrator(steps: [], targetVersion: 2)
        let bytes = Array(SceneFixtures.minimalText.utf8)
        XCTAssertThrowsError(try SceneDocument.decode(bytes, migrator: gap)) { (e: Error) in
            XCTAssertEqual(e as? SceneDecodeError, .migrationFailed(fromVersion: 1, step: nil, path: "$.version", reason: "no step from version 1"))
        }
        let newer = Array(SceneFixtures.minimalText.replacingOccurrences(of: "\"version\":1", with: "\"version\":2").utf8)
        XCTAssertThrowsError(try SceneDocument.decode(newer)) { (e: Error) in
            XCTAssertEqual(e as? SceneDecodeError, .newerVersion(2), "unchanged behaviour")
        }
    }

    // MARK: Full decode through a v0→v1 test chain

    private var v0Bytes: [UInt8] {
        Array(SceneFixtures.minimalText.replacingOccurrences(of: "\"version\":1", with: "\"version\":0")
            .replacingOccurrences(of: "\"name\":\"Empty\"", with: "\"title\":\"Empty\"").utf8)
    }

    func testFullDecodeMigratesAndRecords() throws {
        let migrator = SceneMigrator(steps: [Self.v0to1], targetVersion: 1)
        let result = try SceneDocument.decode(v0Bytes, migrator: migrator)
        XCTAssertEqual(result.document.name, "Empty")
        XCTAssertEqual(result.document.encoded(), Array(SceneFixtures.minimalText.utf8))
        XCTAssertEqual(result.migration.sourceVersion, 0)
        XCTAssertTrue(result.migration.migrated)
        XCTAssertEqual(result.migration.changeCount, 1)
        // The production chain refuses the same bytes exactly as before SCN-013.
        XCTAssertThrowsError(try SceneDocument.decode(v0Bytes)) { (e: Error) in
            XCTAssertEqual(e as? SceneDecodeError, .invalidVersion("0"))
        }
        // A current file records no migration.
        XCTAssertFalse(try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).migration.migrated)
    }

    // MARK: SCN-012 report note (T05)

    func testReportOfAMigratedSceneHasOneNoteThatNeedsNoReview() throws {
        let registry = try SceneFixtures.registry()
        let migrator = SceneMigrator(steps: [Self.v0to1], targetVersion: 1)
        let opening = SceneRepairReport.open(bytes: v0Bytes, registry: registry, migrator: migrator)
        XCTAssertNotNil(opening.document)
        let report = opening.report
        let notes = report.entries(in: .formatUpdated)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.severity, .note)
        XCTAssertEqual(notes.first?.code, "migration.updated")
        XCTAssertEqual(notes.first?.problem, "Updated from an older format (version 0 to 1).")
        XCTAssertFalse(report.needsReview)
        XCTAssertTrue(report.canOpenAsIs)
        XCTAssertEqual(report.statusText, "Ready")
        XCTAssertEqual(report.groups.last, .formatUpdated)

        // `open` adds no note for a current file.
        let current = SceneRepairReport.open(bytes: Array(SceneFixtures.minimalText.utf8), registry: registry)
        XCTAssertTrue(current.report.entries(in: .formatUpdated).isEmpty)
    }

    func testMigrationFailureIsACannotOpenUnsupportedVersionEntry() {
        let report = SceneRepairReport(refusal: .migrationFailed(fromVersion: 1, step: nil, path: "$.version", reason: "no step from version 1"))
        XCTAssertEqual(report.groups, [.unsupportedVersion])
        XCTAssertTrue(report.cannotOpen)
        XCTAssertEqual(report.entries.first?.code, "refusal.migrationFailed")
    }
}
