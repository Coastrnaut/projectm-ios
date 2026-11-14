// SceneMigrationMatrixSupport.swift — QA-004: the scene migration matrix loader, the TEST-ONLY chains
// and the cell checks every container's runner uses (QA-004-R1 to R5; specs/084-qa-004-scene-migration-
// matrix, contracts/migration-matrix.md).
//
// SwiftPM cannot share test sources between packages, so this file is copied byte for byte into each
// runner's test target (SceneFormat, ShowControl, SceneArchive, RenderGoldens, projectM-iOSTests);
// SceneMigrationMatrixMetaTests fails when a copy differs. Public SceneFormat API only.
//
// The chains other than `standard` are SYNTHETIC and test-only: version 1 is the only scene format
// version ever written (SCN-013 research D1), so the app's chain is empty. They are never registered
// in the app.
import Foundation
import SceneFormat
import XCTest

struct SceneMigrationMatrix: Decodable {
    struct Container: Decodable {
        let id: String
        let reader: String
        let test: String
        let surfaces: String
    }

    struct Chain: Decodable {
        let id: String
        let testOnly: Bool
        let target: Int
        let steps: [String]
    }

    struct Outcome: Decodable {
        /// `current`, `migrated` or `refused`.
        let kind: String
        let from: Int?
        let to: Int?
        let log: [String]?
        let error: String?
        let message: String?
    }

    struct Row: Decodable {
        let id: String
        let title: String
        /// The version value as JSON text; nil removes the key.
        let versionJSON: String?
        let format: String?
        let chain: String
        /// `as-is` or `v0-title` (the synthetic version-0 shape: `name` stored as `title`).
        let shape: String
        /// `all` (every historical fixture; the golden container: every committed golden scene) or one manifest file.
        let base: String
        let outcome: Outcome
        let notApplicable: [String: String]
    }

    struct ErrorEntry: Decodable {
        let `case`: String
        let code: String
        let group: String
        let severity: String
        let ifOpened: String
        let when: String
        let coveredBy: [String]
    }

    struct MigrationErrorEntry: Decodable {
        let `case`: String
        let decodeError: String
    }

    /// One stored document a cell reads.
    struct Input {
        let name: String
        let bytes: [UInt8]
        /// The current-schema canonical document a current or migrated outcome must encode to.
        let expected: [UInt8]
        let documentID: String
    }

    let format: String
    let currentVersion: Int
    let oldestSupportedVersion: Int
    let goldenBase: String
    let containers: [Container]
    let chains: [Chain]
    let rows: [Row]
    let errors: [ErrorEntry]
    let migrationErrors: [MigrationErrorEntry]

    // MARK: Files

    /// The repository root: the nearest folder above this file that holds Packages/SceneFormat.
    static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Packages/SceneFormat/Package.swift").path) { return url }
            url = url.deletingLastPathComponent()
        }
        return url
    }

    static var legacyDirectory: URL {
        repositoryRoot.appendingPathComponent("Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy", isDirectory: true)
    }

    static var goldenScenesDirectory: URL {
        repositoryRoot.appendingPathComponent("Packages/RenderGoldens/Scenes", isDirectory: true)
    }

    static func load() throws -> SceneMigrationMatrix {
        try JSONDecoder().decode(SceneMigrationMatrix.self, from: Data(contentsOf: legacyDirectory.appendingPathComponent("matrix.json")))
    }

    private struct Manifest: Decodable {
        struct Row: Decodable {
            let file: String
            let version: Int
            let expected: String
        }

        let fixtures: [Row]
    }

    // MARK: Cells

    /// The rows a container runs (rows that list it as not applicable are left out).
    func rows(for container: String) -> [Row] {
        rows.filter { (row: Row) -> Bool in row.notApplicable[container] == nil }
    }

    /// The chain a row is read with.
    func migrator(_ chainID: String) throws -> SceneMigrator {
        guard let chain = chains.first(where: { (c: Chain) -> Bool in c.id == chainID }) else {
            throw MatrixError.unknownChain(chainID)
        }
        if chain.id == "standard" { return .standard }
        let steps = try chain.steps.map { (id: String) throws -> SceneMigrationStep in
            guard id == Self.testV0ToV1.identifier else { throw MatrixError.unknownStep(id) }
            return Self.testV0ToV1
        }
        return SceneMigrator(steps: steps, targetVersion: chain.target)
    }

    /// TEST-ONLY v0→v1: the made-up version 0 stores the scene name as "title".
    static let testV0ToV1 = SceneMigrationStep(fromVersion: 0, identifier: "test-v0-to-v1", summary: "title to name (test-only)") {
        (object: [String: SceneJSON], recorder: inout SceneMigrationRecorder) throws(SceneMigrationError) -> [String: SceneJSON] in
        var o = object
        guard let title = o.removeValue(forKey: "title") else {
            throw .stepFailed(step: "test-v0-to-v1", fromVersion: 0, path: "$.title", reason: "missing title")
        }
        o["name"] = title
        recorder.renamed("$.title", to: "$.name", "title renamed to name")
        return o
    }

    /// The stored documents of a row: the historical fixtures (or the committed golden scenes) the row
    /// names, rewritten to the row's version, format and shape. A row that changes nothing keeps the
    /// original bytes (hand-written input stays hand-written).
    func inputs(_ row: Row, golden: Bool = false) throws -> [Input] {
        var sources: [(name: String, bytes: [UInt8], expected: [UInt8])] = []
        if golden {
            let folder = Self.goldenScenesDirectory
            let names = row.base == "all"
                ? try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { (n: String) -> Bool in n.hasSuffix(".scene.json") }.sorted()
                : [goldenBase]
            for name in names {
                let bytes = [UInt8](try Data(contentsOf: folder.appendingPathComponent(name)))
                sources.append((name, bytes, bytes))   // committed golden scenes are canonical
            }
        } else {
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.legacyDirectory.appendingPathComponent("manifest.json")))
            let picked = manifest.fixtures.filter { (f: Manifest.Row) -> Bool in row.base == "all" || f.file == row.base }
            guard !picked.isEmpty else { throw MatrixError.unknownBase(row.base) }
            for f in picked {
                sources.append((f.file, [UInt8](try Data(contentsOf: Self.legacyDirectory.appendingPathComponent(f.file))),
                                [UInt8](try Data(contentsOf: Self.legacyDirectory.appendingPathComponent(f.expected)))))
            }
        }
        return try sources.map { (s: (name: String, bytes: [UInt8], expected: [UInt8])) throws -> Input in
            guard case var .object(o) = try SceneJSON.parse(s.bytes) else { throw MatrixError.notAnObject(s.name) }
            let id = o["id"]?.stringValue ?? ""
            let stored = o["version"]?.numberValue?.text
            if row.format == nil, row.shape == "as-is", let v = row.versionJSON, v == stored {
                return Input(name: s.name, bytes: s.bytes, expected: s.expected, documentID: id)
            }
            if let format = row.format { o["format"] = .string(format) }
            if row.shape == "v0-title" { o["title"] = o.removeValue(forKey: "name") }
            if let v = row.versionJSON {
                o["version"] = try SceneJSON.parse(Array(v.utf8))
            } else {
                o.removeValue(forKey: "version")
            }
            return Input(name: s.name, bytes: SceneJSON.object(o).canonicalBytes, expected: s.expected, documentID: id)
        }
    }

    // MARK: Checks

    /// The `SceneDecodeError` case name, from SCN-012's refusal code (`refusal.<case>`).
    static func caseName(_ error: SceneDecodeError) -> String {
        let code = SceneRepairReport(refusal: error).entries.first?.code ?? ""
        return code.hasPrefix("refusal.") ? String(code.dropFirst("refusal.".count)) : code
    }

    /// A refusal: the row expects exactly this case and message, and the case is in the error table.
    func checkRefused(_ error: SceneDecodeError, _ row: Row, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let name = Self.caseName(error)
        XCTAssertEqual(row.outcome.kind, "refused", "\(context): refused with \(error.message)", file: file, line: line)
        XCTAssertEqual(name, row.outcome.error, context, file: file, line: line)
        XCTAssertEqual(error.message, row.outcome.message, context, file: file, line: line)
        XCTAssertTrue(errors.contains { (e: ErrorEntry) -> Bool in e.case == name }, "\(context): \(name) is not in the error table",
                      file: file, line: line)
    }

    /// A document the reader returned: the row expects current or migrated, and it encodes to the expected document.
    func checkDocument(_ document: SceneDocument, _ input: Input, _ row: Row, _ context: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(row.outcome.kind, "refused", "\(context): expected \(row.outcome.error ?? "") but it opened", file: file, line: line)
        XCTAssertEqual(document.encoded(), input.expected, "\(context): encodes to the expected current-schema document", file: file, line: line)
    }

    /// The migration record of a decoded document: unchanged for current, the exact log for migrated.
    func checkRecord(_ record: SceneMigrationRecord, _ row: Row, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        switch row.outcome.kind {
        case "current":
            XCTAssertFalse(record.migrated, context, file: file, line: line)
            XCTAssertEqual(record.log.count, 0, context, file: file, line: line)
        case "migrated":
            XCTAssertTrue(record.migrated, context, file: file, line: line)
            XCTAssertEqual(record.sourceVersion, row.outcome.from, context, file: file, line: line)
            XCTAssertEqual(record.targetVersion, row.outcome.to, context, file: file, line: line)
            XCTAssertEqual(record.log.map(\.description), row.outcome.log ?? [], context, file: file, line: line)
        default:
            XCTFail("\(context): expected a refusal", file: file, line: line)
        }
    }

    /// Asserts the runner's file names its container and that it ran exactly the matrix's cells.
    func checkRan(_ container: String, rows ran: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(containers.contains { (c: Container) -> Bool in c.id == container }, "\(container) is a matrix container",
                      file: file, line: line)
        XCTAssertEqual(ran, rows(for: container).map(\.id), "\(container) ran every applicable row", file: file, line: line)
    }

    enum MatrixError: Error {
        case unknownChain(String)
        case unknownStep(String)
        case unknownBase(String)
        case notAnObject(String)
    }
}
