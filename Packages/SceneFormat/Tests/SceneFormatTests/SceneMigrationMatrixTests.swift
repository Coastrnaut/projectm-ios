// SceneMigrationMatrixTests.swift — QA-004-T04: every matrix row through the decode entry point and the
// SCN-012 repair report (containers "decode" and "repairReport"; QA-004-R3, R8; contracts/migration-
// matrix.md, contracts/scene-decode-errors.md). Rows naming a test-only chain use synthetic steps.
import ParameterGraph
import SceneFormat
import XCTest

final class SceneMigrationMatrixTests: XCTestCase {
    func testDecodeContainer() throws {
        let matrix = try SceneMigrationMatrix.load()
        var ran: [String] = []
        for row in matrix.rows(for: "decode") {
            let migrator = try matrix.migrator(row.chain)
            for input in try matrix.inputs(row) {
                let context = "decode \(row.id) \(input.name)"
                do {
                    let result = try SceneDocument.decode(input.bytes, migrator: migrator)
                    matrix.checkDocument(result.document, input, row, context)
                    matrix.checkRecord(result.migration, row, context)
                } catch {
                    matrix.checkRefused(error, row, context)
                }
            }
            ran.append(row.id)
        }
        matrix.checkRan("decode", rows: ran)
    }

    func testRepairReportContainer() throws {
        let matrix = try SceneMigrationMatrix.load()
        let registry = try SceneFixtures.registry()
        var ran: [String] = []
        for row in matrix.rows(for: "repairReport") {
            let migrator = try matrix.migrator(row.chain)
            for input in try matrix.inputs(row) {
                let context = "repairReport \(row.id) \(input.name)"
                let opening = SceneRepairReport.open(bytes: input.bytes, registry: registry, migrator: migrator)
                let refusals = opening.report.entries.filter { (e: SceneRepairReport.Entry) -> Bool in e.code.hasPrefix("refusal.") }
                let notes = opening.report.entries.filter { (e: SceneRepairReport.Entry) -> Bool in e.code == "migration.updated" }
                if row.outcome.kind == "refused" {
                    XCTAssertNil(opening.document, context)
                    XCTAssertEqual(opening.report.entries.count, 1, context)
                    let entry = try XCTUnwrap(refusals.first, context)
                    XCTAssertEqual(entry.code, "refusal." + (row.outcome.error ?? ""), context)
                    XCTAssertEqual(entry.problem, row.outcome.message, context)
                    XCTAssertEqual(entry.severity, .cannotOpen, context)
                    XCTAssertEqual(entry.item, "Scene file", context)
                    XCTAssertEqual(entry.actions, [], context)
                    let documented = try XCTUnwrap(matrix.errors.first { (e: SceneMigrationMatrix.ErrorEntry) -> Bool in e.code == entry.code },
                                                   "\(context): \(entry.code) is documented")
                    XCTAssertEqual(entry.group.rawValue, documented.group, context)
                    XCTAssertEqual(entry.ifOpened, documented.ifOpened, context)
                    XCTAssertEqual(opening.report.statusText, "Cannot open", context)
                } else {
                    let document = try XCTUnwrap(opening.document, context)
                    matrix.checkDocument(document, input, row, context)
                    XCTAssertEqual(refusals.count, 0, context)
                    if row.outcome.kind == "migrated" {
                        XCTAssertEqual(notes.map(\.problem), ["Updated from an older format (version \(row.outcome.from ?? -1) to \(row.outcome.to ?? -1))."],
                                       context)
                        XCTAssertEqual(notes.first?.severity, .note, context)
                    } else {
                        XCTAssertEqual(notes.count, 0, context)
                    }
                }
            }
            ran.append(row.id)
        }
        matrix.checkRan("repairReport", rows: ran)
    }
}
