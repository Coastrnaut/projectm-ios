// SceneMigrationMatrixMetaTests.swift — QA-004-T09: the matrix and the error table cannot fall behind the
// code (QA-004-R7; contracts/migration-matrix.md "Meta-test").
//
// Cases of `SceneDecodeError` and `SceneMigrationError` come from two places: a scan of the enums' source
// (a new case is seen without anyone listing it) and the exhaustive switches below (the compiler refuses a
// new case until it has a name and a sample). Every check runs as `problems(...)`, which is also run on
// deliberately broken copies to show each check can fail.
import Foundation
@testable import SceneFormat
import XCTest

final class SceneMigrationMatrixMetaTests: XCTestCase {
    // MARK: Cases in code

    private static var sourcesDirectory: URL {
        SceneMigrationMatrix.repositoryRoot.appendingPathComponent("Packages/SceneFormat/Sources/SceneFormat", isDirectory: true)
    }

    private static var contractURL: URL {
        SceneMigrationMatrix.repositoryRoot.appendingPathComponent("specs/084-qa-004-scene-migration-matrix/contracts/scene-decode-errors.md")
    }

    /// The case names declared in `enum <name>` of a source file (four-space `case <identifier>` lines up to
    /// the enum's closing brace; `case` lines inside switches are indented deeper).
    static func declaredCases(of name: String, in file: String) throws -> [String] {
        let text = try String(contentsOf: sourcesDirectory.appendingPathComponent(file), encoding: .utf8)
        var inside = false
        var cases: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if !inside {
                if line.hasPrefix("public enum \(name)") || line.hasPrefix("enum \(name)") { inside = true }
                continue
            }
            if line == "}" { break }
            guard line.hasPrefix("    case ") else { continue }
            let rest = line.dropFirst("    case ".count)
            let identifier = String(rest.prefix { (c: Character) -> Bool in c.isLetter || c.isNumber || c == "_" })
            if !identifier.isEmpty { cases.append(identifier) }
        }
        return cases
    }

    /// Exhaustive: a new `SceneDecodeError` case does not compile until it is named here.
    static func name(_ error: SceneDecodeError) -> String {
        switch error {
        case .empty: "empty"
        case .tooLarge: "tooLarge"
        case .notJSON: "notJSON"
        case .nestingTooDeep: "nestingTooDeep"
        case .duplicateKey: "duplicateKey"
        case .notAScene: "notAScene"
        case .newerVersion: "newerVersion"
        case .invalidVersion: "invalidVersion"
        case .tooMany: "tooMany"
        case .malformed: "malformed"
        case .migrationFailed: "migrationFailed"
        }
    }

    /// One sample per case name (nil for a name without a sample: the meta-test then fails).
    static func sample(_ name: String) -> SceneDecodeError? {
        switch name {
        case "empty": .empty
        case "tooLarge": .tooLarge(bytes: 2_000_000, limit: SceneLimits.maximumBytes)
        case "notJSON": .notJSON(offset: 3, reason: "unexpected character")
        case "nestingTooDeep": .nestingTooDeep(limit: SceneLimits.maximumDepth)
        case "duplicateKey": .duplicateKey(path: "$", key: "name")
        case "notAScene": .notAScene
        case "newerVersion": .newerVersion(2)
        case "invalidVersion": .invalidVersion("0")
        case "tooMany": .tooMany(what: "layers", count: 99, limit: SceneLimits.maximumLayers)
        case "malformed": .malformed(path: "$.name", reason: "must be a string")
        case "migrationFailed": .migrationFailed(fromVersion: 0, step: "test-v0-to-v1", path: "$.title", reason: "missing title")
        default: nil
        }
    }

    /// Exhaustive: a new `SceneMigrationError` case does not compile until it has a sample.
    static func migrationSamples() -> [(name: String, error: SceneMigrationError)] {
        let all: [SceneMigrationError] = [.notAScene, .invalidVersion("x"), .newerVersion(2), .missingStep(fromVersion: 0),
                                          .stepFailed(step: "s", fromVersion: 0, path: "$", reason: "r")]
        return all.map { (e: SceneMigrationError) -> (name: String, error: SceneMigrationError) in
            switch e {
            case .notAScene: ("notAScene", e)
            case .invalidVersion: ("invalidVersion", e)
            case .newerVersion: ("newerVersion", e)
            case .missingStep: ("missingStep", e)
            case .stepFailed: ("stepFailed", e)
            }
        }
    }

    // MARK: The checks

    /// Every completeness problem of `matrix` against the code; empty means complete.
    static func problems(_ matrix: SceneMigrationMatrix, decodeCases: [String], migrationCases: [String], contract: String,
                         manifestVersions: Set<Int>, standard: SceneMigrator = .standard) -> [String] {
        var p: [String] = []
        // Versions in code.
        if matrix.currentVersion != SceneDocument.currentVersion { p.append("currentVersion differs from the code") }
        if matrix.oldestSupportedVersion != standard.oldestVersion { p.append("oldestSupportedVersion differs from the code") }

        // Error table: every case in code, nothing else.
        let documented = Set(matrix.errors.map(\.case))
        for name in decodeCases {
            guard let entry = matrix.errors.first(where: { (e: SceneMigrationMatrix.ErrorEntry) -> Bool in e.case == name }) else {
                p.append("SceneDecodeError.\(name) has no error table entry")
                continue
            }
            if entry.code != "refusal." + name { p.append("\(name): code \(entry.code)") }
            if !contract.contains("`refusal.\(name)`") { p.append("\(name) is not in contracts/scene-decode-errors.md") }
            if !contract.contains(entry.ifOpened) { p.append("\(name): the contract lacks its report text") }
            if entry.coveredBy.isEmpty { p.append("\(name) is covered by nothing") }
            guard let sample = sample(name) else {
                p.append("SceneDecodeError.\(name) has no test sample")
                continue
            }
            if Self.name(sample) != name { p.append("\(name): sample is \(Self.name(sample))") }
            let report = SceneRepairReport(refusal: sample)
            guard report.entries.count == 1, let reported = report.entries.first else {
                p.append("\(name): the report has \(report.entries.count) entries")
                continue
            }
            if reported.code != entry.code { p.append("\(name): report code \(reported.code)") }
            if reported.group.rawValue != entry.group { p.append("\(name): report group \(reported.group.rawValue), table \(entry.group)") }
            if reported.ifOpened != entry.ifOpened { p.append("\(name): report text differs from the table") }
            if entry.severity != "cannotOpen" || reported.severity != .cannotOpen { p.append("\(name): not cannot-open") }
            for covering in entry.coveredBy where covering.hasPrefix("QA-004-M") {
                guard let row = matrix.rows.first(where: { (r: SceneMigrationMatrix.Row) -> Bool in r.id == covering }) else {
                    p.append("\(name) is covered by a missing row \(covering)")
                    continue
                }
                if row.outcome.error != name { p.append("\(covering) does not refuse with \(name)") }
            }
        }
        for extra in documented.subtracting(decodeCases) { p.append("table entry \(extra) is not a case in code") }

        // Migration errors.
        let mapped = Set(matrix.migrationErrors.map(\.case))
        for name in migrationCases where !mapped.contains(name) { p.append("SceneMigrationError.\(name) has no mapping entry") }
        for extra in mapped.subtracting(migrationCases) { p.append("mapping entry \(extra) is not a case in code") }
        for (name, error) in migrationSamples() {
            guard let entry = matrix.migrationErrors.first(where: { (e: SceneMigrationMatrix.MigrationErrorEntry) -> Bool in e.case == name }) else { continue }
            if Self.name(error.decodeError) != entry.decodeError { p.append("\(name) maps to \(Self.name(error.decodeError)), table \(entry.decodeError)") }
        }

        // Chains.
        let chainIDs = Set(matrix.chains.map(\.id))
        if let s = matrix.chains.first(where: { (c: SceneMigrationMatrix.Chain) -> Bool in c.id == "standard" }) {
            if s.testOnly || s.target != standard.targetVersion || s.steps != standard.steps.map(\.identifier) {
                p.append("the standard chain differs from SceneMigrator.standard")
            }
        } else {
            p.append("no standard chain")
        }
        for c in matrix.chains where c.id != "standard" && (!c.testOnly || !c.id.hasPrefix("test-")) {
            p.append("chain \(c.id) must be marked test-only and named test-…")
        }

        // Rows.
        let containerIDs = Set(matrix.containers.map(\.id))
        let standardRows = matrix.rows.filter { (r: SceneMigrationMatrix.Row) -> Bool in r.chain == "standard" && r.format == nil && r.shape == "as-is" }
        func row(version text: String) -> SceneMigrationMatrix.Row? {
            standardRows.first { (r: SceneMigrationMatrix.Row) -> Bool in r.versionJSON == text }
        }
        if matrix.oldestSupportedVersion <= matrix.currentVersion {
            for v in matrix.oldestSupportedVersion...matrix.currentVersion {
                guard let r = row(version: String(v)) else {
                    p.append("supported version \(v) has no row")
                    continue
                }
                if r.outcome.kind == "refused" { p.append("supported version \(v) is refused") }
            }
        }
        if row(version: String(matrix.oldestSupportedVersion - 1)) == nil { p.append("oldest - 1 has no row") }
        if row(version: String(matrix.currentVersion + 1)) == nil { p.append("current + 1 has no row") }
        let nonInteger = standardRows.contains { (r: SceneMigrationMatrix.Row) -> Bool in
            guard let text = r.versionJSON, let value = try? SceneJSON.parse(Array(text.utf8)), let number = value.numberValue else { return false }
            return number.int64Value == nil
        }
        if !nonInteger { p.append("no row with a non-integer version") }
        if !standardRows.contains(where: { (r: SceneMigrationMatrix.Row) -> Bool in r.versionJSON == nil }) { p.append("no row with a missing version") }
        for step in standard.steps {
            let covered = standardRows.contains { (r: SceneMigrationMatrix.Row) -> Bool in
                r.versionJSON == String(step.fromVersion) && r.outcome.kind == "migrated"
            }
            if !covered { p.append("production step \(step.identifier) has no migrated row") }
        }
        for v in manifestVersions where !standardRows.contains(where: { (r: SceneMigrationMatrix.Row) -> Bool in r.versionJSON == String(v) && r.base == "all" }) {
            p.append("historical fixtures of version \(v) have no row over every fixture")
        }
        var seen: Set<String> = []
        for r in matrix.rows {
            if !seen.insert(r.id).inserted { p.append("row \(r.id) twice") }
            if !r.id.hasPrefix("QA-004-M") { p.append("row \(r.id) is not a QA-004 row ID") }
            if !chainIDs.contains(r.chain) { p.append("\(r.id): unknown chain \(r.chain)") }
            if r.chain != "standard" && !r.title.hasPrefix("TEST-ONLY") { p.append("\(r.id) uses a test chain without the TEST-ONLY label") }
            switch r.outcome.kind {
            case "current":
                break
            case "migrated":
                if r.outcome.from == nil || r.outcome.to == nil || (r.outcome.log ?? []).isEmpty { p.append("\(r.id): incomplete migrated outcome") }
            case "refused":
                if !documented.contains(r.outcome.error ?? "") { p.append("\(r.id): refusal \(r.outcome.error ?? "nil") is not documented") }
                if (r.outcome.message ?? "").isEmpty { p.append("\(r.id): no message") }
            default:
                p.append("\(r.id): unknown outcome \(r.outcome.kind)")
            }
            for (container, reason) in r.notApplicable {
                if !containerIDs.contains(container) { p.append("\(r.id): unknown container \(container)") }
                if reason.trimmingCharacters(in: .whitespaces).isEmpty { p.append("\(r.id): \(container) is skipped without a reason") }
            }
        }
        return p
    }

    private func current() throws -> (SceneMigrationMatrix, [String], [String], String, Set<Int>) {
        let decodeCases = try Self.declaredCases(of: "SceneDecodeError", in: "SceneIssue.swift")
        let migrationCases = try Self.declaredCases(of: "SceneMigrationError", in: "SceneMigration.swift")
        let contract = try String(contentsOf: Self.contractURL, encoding: .utf8)
        let versions = Set(try LegacyFixtureManifest.load().fixtures.map(\.version))
        return (try SceneMigrationMatrix.load(), decodeCases, migrationCases, contract, versions)
    }

    // MARK: Tests

    func testTheSourceScanFindsEveryCase() throws {
        let decodeCases = try Self.declaredCases(of: "SceneDecodeError", in: "SceneIssue.swift")
        XCTAssertEqual(decodeCases.count, 11, "\(decodeCases)")
        for name in decodeCases {
            let sample = try XCTUnwrap(Self.sample(name), name)
            XCTAssertEqual(Self.name(sample), name)
        }
        let migrationCases = try Self.declaredCases(of: "SceneMigrationError", in: "SceneMigration.swift")
        XCTAssertEqual(migrationCases, Self.migrationSamples().map(\.name))
    }

    func testMatrixAndErrorTableAreComplete() throws {
        let (matrix, decodeCases, migrationCases, contract, versions) = try current()
        XCTAssertEqual(matrix.format, "projectm-ios.scene-migration-matrix")
        XCTAssertEqual(Self.problems(matrix, decodeCases: decodeCases, migrationCases: migrationCases, contract: contract,
                                     manifestVersions: versions), [])
    }

    /// Each container names a runner that exists, names its container and carries an identical copy of the support file.
    func testEveryContainerHasARunnerWithTheSharedSupportFile() throws {
        let matrix = try SceneMigrationMatrix.load()
        XCTAssertEqual(Set(matrix.containers.map(\.id)), ["decode", "repairReport", "showStore", "archive", "autosave", "golden"])
        let root = SceneMigrationMatrix.repositoryRoot
        let support = try Data(contentsOf: root.appendingPathComponent("Packages/SceneFormat/Tests/SceneFormatTests/SceneMigrationMatrixSupport.swift"))
        for container in matrix.containers {
            let test = root.appendingPathComponent(container.test)
            let text = try String(contentsOf: test, encoding: .utf8)
            XCTAssertTrue(text.contains("\"\(container.id)\""), "\(container.test) runs \(container.id)")
            XCTAssertTrue(text.contains("checkRan(\"\(container.id)\""), "\(container.test) checks it ran every \(container.id) cell")
            let copy = test.deletingLastPathComponent().appendingPathComponent("SceneMigrationMatrixSupport.swift")
            XCTAssertEqual(try? Data(contentsOf: copy), support, "\(copy.path) is an identical copy")
        }
        let contract = try String(contentsOf: Self.contractURL, encoding: .utf8)
        for container in matrix.containers {
            XCTAssertTrue(contract.contains("| \(container.id) |"), "the contract says how \(container.id) surfaces a refusal")
        }
    }

    /// The checks are not vacuous: each broken copy is caught.
    func testEachCheckCatchesABrokenCopy() throws {
        let (_, decodeCases, migrationCases, contract, versions) = try current()
        let url = SceneMigrationMatrix.legacyDirectory.appendingPathComponent("matrix.json")
        func broken(_ edit: (inout [String: Any]) -> Void) throws -> SceneMigrationMatrix {
            var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            edit(&json)
            return try JSONDecoder().decode(SceneMigrationMatrix.self, from: JSONSerialization.data(withJSONObject: json))
        }
        func rows(_ json: [String: Any]) -> [[String: Any]] { json["rows"] as? [[String: Any]] ?? [] }
        func expect(_ matrix: SceneMigrationMatrix, cases: [String]? = nil, migration: [String]? = nil, contract text: String? = nil,
                    manifest: Set<Int>? = nil, standard: SceneMigrator = .standard, _ needle: String, line: UInt = #line) {
            let found = Self.problems(matrix, decodeCases: cases ?? decodeCases, migrationCases: migration ?? migrationCases,
                                      contract: text ?? contract, manifestVersions: manifest ?? versions, standard: standard)
            XCTAssertTrue(found.contains { (s: String) -> Bool in s.contains(needle) }, "expected \"\(needle)\" in \(found)", line: line)
        }
        let intact = try broken { (_: inout [String: Any]) in }
        // A new decode error case in code, a missing sample, a missing contract row.
        expect(intact, cases: decodeCases + ["futureCase"], "SceneDecodeError.futureCase has no error table entry")
        expect(intact, contract: contract.replacingOccurrences(of: "`refusal.tooMany`", with: "`gone`"), "tooMany is not in contracts")
        // A new migration error case in code.
        expect(intact, migration: migrationCases + ["futureStep"], "SceneMigrationError.futureStep has no mapping entry")
        // A table entry removed, a report text changed.
        expect(try broken { (j: inout [String: Any]) in
            j["errors"] = (j["errors"] as? [[String: Any]] ?? []).filter { (e: [String: Any]) -> Bool in e["case"] as? String != "malformed" }
        }, "SceneDecodeError.malformed has no error table entry")
        expect(try broken { (j: inout [String: Any]) in
            j["errors"] = (j["errors"] as? [[String: Any]] ?? []).map { (e: [String: Any]) -> [String: Any] in
                var e = e
                if e["case"] as? String == "newerVersion" { e["ifOpened"] = "Something else." }
                return e
            }
        }, "newerVersion: report text differs")
        // Version rows removed: current + 1, the supported version, the missing version.
        expect(try broken { (j: inout [String: Any]) in
            j["rows"] = rows(j).filter { (r: [String: Any]) -> Bool in r["versionJSON"] as? String != "2" }
        }, "current + 1 has no row")
        expect(try broken { (j: inout [String: Any]) in
            j["rows"] = rows(j).filter { (r: [String: Any]) -> Bool in r["id"] as? String != "QA-004-M01" }
        }, "supported version 1 has no row")
        expect(try broken { (j: inout [String: Any]) in
            j["rows"] = rows(j).filter { (r: [String: Any]) -> Bool in !(r["versionJSON"] is NSNull) }
        }, "no row with a missing version")
        // A historical version without a row; a production step without a migrated row; the current version moved.
        expect(intact, manifest: versions.union([7]), "historical fixtures of version 7 have no row")
        let stepped = SceneMigrator(steps: [SceneMigrationMatrix.testV0ToV1], targetVersion: 1)
        expect(intact, standard: stepped, "production step test-v0-to-v1 has no migrated row")
        expect(try broken { (j: inout [String: Any]) in j["currentVersion"] = 2 }, "currentVersion differs from the code")
        // A skipped cell without a reason; an undocumented refusal; an unlabelled test chain row.
        expect(try broken { (j: inout [String: Any]) in
            j["rows"] = rows(j).map { (r: [String: Any]) -> [String: Any] in
                var r = r
                if r["id"] as? String == "QA-004-M14" { r["notApplicable"] = ["golden": " "] }
                return r
            }
        }, "QA-004-M14: golden is skipped without a reason")
        expect(try broken { (j: inout [String: Any]) in
            j["rows"] = rows(j).map { (r: [String: Any]) -> [String: Any] in
                var r = r
                if r["id"] as? String == "QA-004-M02" { r["outcome"] = ["kind": "refused", "error": "somethingNew", "message": "x"] }
                return r
            }
        }, "QA-004-M02: refusal somethingNew is not documented")
        expect(try broken { (j: inout [String: Any]) in
            j["rows"] = rows(j).map { (r: [String: Any]) -> [String: Any] in
                var r = r
                if r["id"] as? String == "QA-004-M16" { r["title"] = "chain with a gap" }
                return r
            }
        }, "QA-004-M16 uses a test chain without the TEST-ONLY label")
    }
}
