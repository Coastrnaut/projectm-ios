// GoldenMigrationMatrixTests.swift — QA-004-T07: every applicable matrix row over the QA-002 golden render
// scenes (container "golden"; QA-004-R3; contracts/scene-decode-errors.md "How each container surfaces").
// Inputs are the committed `Scenes/*.scene.json` files, rewritten to each row's version. Where Metal is
// built, the harness's own `GoldenSceneRenderer.document(from:)` reads them (a refusal is
// `.sceneInvalid(message)`); where it is compiled out (Linux shape), `SceneDocument.decode`, the harness's
// only decoding step, reads them. Rows naming a test-only chain are not applicable here (the harness reads
// with the app's chain only).
import Foundation
import GoldenImages
import SceneFormat
import XCTest
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import SceneRenderHarness
#endif

final class GoldenMigrationMatrixTests: XCTestCase {
    func testGoldenContainer() throws {
        let matrix = try SceneMigrationMatrix.load()
        var ran: [String] = []
        for row in matrix.rows(for: "golden") {
            XCTAssertEqual(row.chain, "standard", "\(row.id): the golden harness has no chain seam")
            for input in try matrix.inputs(row, golden: true) {
                let context = "golden \(row.id) \(input.name)"
                // The decode refusal, for its case; the harness must surface exactly its message.
                var refusal: SceneDecodeError?
                do {
                    _ = try SceneDocument.decode(input.bytes)
                } catch {
                    refusal = error
                }
                #if canImport(Metal) && !COMPOSITOR_NO_METAL
                do {
                    let document = try GoldenSceneRenderer.document(from: input.bytes)
                    matrix.checkDocument(document, input, row, context)
                    XCTAssertNil(refusal, context)
                } catch {
                    let decodeError = try XCTUnwrap(refusal, "\(context): \(error)")
                    XCTAssertEqual(error, .sceneInvalid(decodeError.message), context)
                    matrix.checkRefused(decodeError, row, context)
                }
                #else
                if let refusal {
                    matrix.checkRefused(refusal, row, context)
                } else {
                    let result = try SceneDocument.decode(input.bytes)
                    matrix.checkDocument(result.document, input, row, context)
                    matrix.checkRecord(result.migration, row, context)
                }
                #endif
            }
            ran.append(row.id)
        }
        matrix.checkRan("golden", rows: ran)
    }

    /// The matrix's golden inputs are every committed golden scene.
    func testGoldenInputsAreTheCommittedScenes() throws {
        let matrix = try SceneMigrationMatrix.load()
        let row = try XCTUnwrap(matrix.rows.first { (r: SceneMigrationMatrix.Row) -> Bool in r.base == "all" && r.chain == "standard" })
        XCTAssertEqual(try matrix.inputs(row, golden: true).map(\.name), GoldenSceneCatalog.runs.map(\.fileName).sorted())
    }
}
