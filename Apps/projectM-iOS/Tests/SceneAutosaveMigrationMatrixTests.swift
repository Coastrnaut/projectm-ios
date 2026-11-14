// SceneAutosaveMigrationMatrixTests.swift — QA-004-T08: every matrix row as the SCN-002 autosave main file
// (container "autosave"; QA-004-R3; contracts/scene-decode-errors.md "How each container surfaces").
// Each input is written as `current.scene` in a temporary folder and read by `SceneAutosaveStore.load`
// with the app's registry and no media availability. Rows naming a test-only chain use synthetic steps
// (SceneMigrationMatrixSupport.swift).
import Foundation
import ParameterGraph
import SceneFormat
import XCTest
@testable import projectM_iOS

final class SceneAutosaveMigrationMatrixTests: XCTestCase {
    func testAutosaveContainer() throws {
        let matrix = try SceneMigrationMatrix.load()
        let registry = try SceneAutosaveFixtures.registry()
        var ran: [String] = []
        for row in matrix.rows(for: "autosave") {
            let migrator = try matrix.migrator(row.chain)
            for input in try matrix.inputs(row) {
                let context = "autosave \(row.id) \(input.name)"
                let folder = SceneAutosaveFixtures.folder()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let store = SceneAutosaveStore(directory: folder, migrator: migrator)
                try Data(input.bytes).write(to: store.main)

                let load = store.load(registry: registry, assets: nil)
                let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
                switch row.outcome.kind {
                case "refused":
                    XCTAssertNil(load.document, context)
                    XCTAssertEqual(load.source, SceneAutosaveSource.none, context)
                    let message = row.outcome.message ?? ""
                    if row.outcome.error == "newerVersion" {
                        XCTAssertEqual(load.events, [.mainUnreadable(message), .setAsideNewer("current.scene.newer"), .nothingRestored], context)
                        XCTAssertEqual(names, ["current.scene.newer"], "\(context): a newer file is set aside")
                    } else {
                        XCTAssertEqual(load.events, [.mainUnreadable(message), .nothingRestored], context)
                        XCTAssertEqual(names, [SceneAutosaveStore.mainName], "\(context): nothing written")
                        XCTAssertEqual(try Data(contentsOf: store.main), Data(input.bytes), context)
                    }
                    // The same bytes refuse with the documented case through the decode entry point the store uses.
                    do {
                        _ = try SceneDocument.decode(input.bytes, migrator: migrator)
                        XCTFail("\(context): decodes")
                    } catch {
                        matrix.checkRefused(error, row, context)
                    }
                case "migrated":
                    let document = try XCTUnwrap(load.document, "\(context): \(load.events)")
                    matrix.checkDocument(document, input, row, context)
                    XCTAssertEqual(load.source, SceneAutosaveSource.main, context)
                    let changes = (row.outcome.log ?? []).filter { (line: String) -> Bool in !line.contains(": version $.version:") }.count
                    let steps = (row.outcome.to ?? 0) - (row.outcome.from ?? 0)
                    XCTAssertEqual(load.events, [.migrated(from: row.outcome.from ?? -1, to: row.outcome.to ?? -1, steps: steps, changes: changes)],
                                   context)
                    XCTAssertEqual(names, [SceneAutosaveStore.mainName], "\(context): loading writes nothing")
                default:
                    let document = try XCTUnwrap(load.document, "\(context): \(load.events)")
                    matrix.checkDocument(document, input, row, context)
                    XCTAssertEqual(load.source, SceneAutosaveSource.main, context)
                    XCTAssertEqual(load.events, [], context)
                    XCTAssertEqual(names, [SceneAutosaveStore.mainName], "\(context): loading writes nothing")
                }
            }
            ran.append(row.id)
        }
        matrix.checkRan("autosave", rows: ran)
    }
}
