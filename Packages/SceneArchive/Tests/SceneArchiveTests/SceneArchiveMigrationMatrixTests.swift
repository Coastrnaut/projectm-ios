// SceneArchiveMigrationMatrixTests.swift — QA-004-T06: every matrix row as the `scene.json` of a FILE-001/002
// archive (container "archive"; QA-004-R3; contracts/scene-decode-errors.md "How each container surfaces").
// Each input is packed by the hand builder with its checksums, plus the FILE-001 test media for each photo
// and video asset of the expected document, then read through `SceneArchiveReader.read(_:registry:migrator:)`.
// Rows naming a test-only chain use synthetic steps (SceneMigrationMatrixSupport.swift).
import Foundation
@testable import SceneArchive
import SceneFormat
import XCTest

final class SceneArchiveMigrationMatrixTests: XCTestCase {
    func testArchiveContainer() throws {
        let matrix = try SceneMigrationMatrix.load()
        let registry = try ArchiveFixtures.registry()
        var ran: [String] = []
        for row in matrix.rows(for: "archive") {
            let migrator = try matrix.migrator(row.chain)
            for input in try matrix.inputs(row) {
                let context = "archive \(row.id) \(input.name)"
                var files: [(String, Data)] = [(SceneArchiveFormat.scenePath, Data(input.bytes))]
                var records: [SceneArchiveAssetRecord] = []
                if row.outcome.kind != "refused" {
                    for asset in try SceneDocument.decode(input.expected).document.mediaAssets {
                        let ext = asset.type == .photo ? "png" : "mov"
                        let path = SceneArchiveFormat.assetPath(key: asset.key, fileExtension: ext)
                        files.append((path, asset.type == .photo ? ArchiveFixtures.pngBytes : ArchiveFixtures.movieBytes))
                        records.append(SceneArchiveAssetRecord(key: asset.key, type: asset.type.rawValue, path: path))
                    }
                }
                let archive = try ArchiveFixtures.handBuilt(files: files, records: records)
                do {
                    let contents = try SceneArchiveReader.read(archive, registry: registry, migrator: migrator)
                    matrix.checkDocument(contents.document, input, row, context)
                    XCTAssertEqual(contents.media.count, records.count, context)
                } catch {
                    switch error {
                    case let .sceneRefused(decodeError):
                        matrix.checkRefused(decodeError, row, context)
                        XCTAssertEqual(error.message, "The scene could not be read: " + decodeError.message, context)
                    default:
                        XCTFail("\(context): \(error.message)")
                    }
                }
            }
            ran.append(row.id)
        }
        matrix.checkRan("archive", rows: ran)
    }

    /// The new parameter defaults to the app's chain: a synthetic version-0 scene is refused as before.
    func testReaderDefaultsToTheAppsChain() throws {
        let matrix = try SceneMigrationMatrix.load()
        let row = try XCTUnwrap(matrix.rows.first { (r: SceneMigrationMatrix.Row) -> Bool in r.id == "QA-004-M14" })
        let input = try XCTUnwrap(try matrix.inputs(row).first)
        let archive = try ArchiveFixtures.handBuilt(files: [(SceneArchiveFormat.scenePath, Data(input.bytes))], records: [])
        XCTAssertThrowsError(try SceneArchiveReader.read(archive, registry: try ArchiveFixtures.registry())) { (error: Error) in
            XCTAssertEqual(error as? SceneArchiveError, .sceneRefused(.invalidVersion("0")))
        }
    }
}
