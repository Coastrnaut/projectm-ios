// ShowStoreMigrationMatrixTests.swift — QA-004-T05: every matrix row as a SHOW-001 show scene (container
// "showStore"; QA-004-R3; contracts/scene-decode-errors.md "How each container surfaces"). Each input is
// stored as `Scenes/<id>.scene.json` with a one-cue show, then read through `ShowStore.scene(_:)` and
// `ShowStore.load()`. Rows naming a test-only chain use synthetic steps (SceneMigrationMatrixSupport.swift).
import Foundation
import SceneFormat
import ShowControl
import ShowStorage
import XCTest

final class ShowStoreMigrationMatrixTests: XCTestCase {
    func testShowStoreContainer() throws {
        let matrix = try SceneMigrationMatrix.load()
        var ran: [String] = []
        for row in matrix.rows(for: "showStore") {
            let migrator = try matrix.migrator(row.chain)
            for input in try matrix.inputs(row) {
                let context = "showStore \(row.id) \(input.name)"
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QA004-Show-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let store = ShowStore(directory: folder, migrator: migrator)
                try FileManager.default.createDirectory(at: store.scenesFolder, withIntermediateDirectories: true)
                let id = input.documentID
                XCTAssertTrue(ShowCueList.isSceneID(id), "\(context): fixture id \(id) is a scene ID")
                try Data(input.bytes).write(to: store.sceneFile(id))
                var list = ShowCueList()
                _ = try list.append(sceneID: id, label: "Cue")
                try list.encoded().write(to: store.showFile)

                do {
                    let result = try store.scene(id)
                    matrix.checkDocument(result.document, input, row, context)
                    matrix.checkRecord(result.migration, row, context)
                } catch {
                    switch error {
                    case let .unreadable(decodeError):
                        matrix.checkRefused(decodeError, row, context)
                    default:
                        XCTFail("\(context): \(error)")
                    }
                }
                let load = store.load()
                XCTAssertNil(load.refusal, "\(context): the show itself loads")
                XCTAssertEqual(load.list.sceneIDs, [id], context)
                XCTAssertEqual(load.unreadableScenes, row.outcome.kind == "refused" ? [id] : [], context)
                XCTAssertEqual(try Data(contentsOf: store.sceneFile(id)), Data(input.bytes), "\(context): reading writes nothing")
                XCTAssertEqual(store.backups(of: id), [], "\(context): no backup without a save")
            }
            ran.append(row.id)
        }
        matrix.checkRan("showStore", rows: ran)
    }
}
