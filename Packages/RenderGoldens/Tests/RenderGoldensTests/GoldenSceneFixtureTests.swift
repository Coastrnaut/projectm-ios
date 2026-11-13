// QA-002-T07 (US2; QA-002-R1-R3; contract G1): the stored scenes are valid, canonical SCN-001 documents
// whose live state opens without warnings, one per catalog run, using only supported native layers.
// SceneFormat is plain Swift: runs on Linux.
import Foundation
import GoldenImages
import ParameterGraph
import ProceduralMaterials
import SceneFormat
import VisualParameters
import XCTest

final class GoldenSceneFixtureTests: XCTestCase {
    private func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: VisualParameterCatalog.descriptors + ProceduralMaterialCatalog.descriptors)
    }

    func testEverySceneFileHasOneRunAndViceVersa() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: GoldenPaths.scenes.path)
            .filter { (f: String) -> Bool in f.hasSuffix(".scene.json") }.sorted()
        XCTAssertEqual(files, GoldenSceneCatalog.runs.map(\.fileName).sorted())
    }

    func testScenesAreCanonicalValidAndSupported() throws {
        let registry = try registry()
        var kinds: Set<String> = []
        for run in GoldenSceneCatalog.runs {
            let bytes = try GoldenPaths.sceneBytes(run)
            let decoded = try SceneDocument.decode(bytes)
            XCTAssertEqual(decoded.warnings, [], run.name)
            XCTAssertEqual(decoded.document.encoded(), bytes, "\(run.name): stored in canonical form")
            let load = try decoded.document.liveState(registry: registry)
            XCTAssertEqual(load.warnings, [], run.name)
            XCTAssertEqual(load.state.stack.entries.count, decoded.document.layers.count, "\(run.name): every layer is live")
            for layer in decoded.document.layers {
                kinds.insert(layer.kind)
                XCTAssertFalse(["camera", "video"].contains(layer.kind), "\(run.name): no live input")
                XCTAssertTrue(layer.content.isKnown, run.name)
                if case let .photo(key) = layer.content, case let .photo(storeID)? = decoded.document.assets[key]?.kind {
                    XCTAssertNotNil(run.photos[storeID], "\(run.name): its photo is generated from the seed")
                }
            }
            XCTAssertTrue(decoded.document.name.hasPrefix("QA-002 "), run.name)
        }
        // QA-002-R1 coverage.
        XCTAssertEqual(kinds, ["photo", "material", "generator.graph", "spectrum.circular", "spectrum.linear", "text"])
        let stack = try XCTUnwrap(GoldenSceneCatalog.run(named: "stack-composite"))
        let document = try SceneDocument.decode(GoldenPaths.sceneBytes(stack)).document
        XCTAssertTrue(document.layers.contains { (l: SceneLayer) -> Bool in l.composite.opacity < 1 })
        XCTAssertTrue(document.layers.contains { (l: SceneLayer) -> Bool in l.composite.transform != .identity })
        XCTAssertTrue(GoldenSceneCatalog.runs.contains { (r: GoldenSceneRun) -> Bool in r.audio == .alternating(count: 32) && r.reduceFlashing })
        XCTAssertEqual(GoldenSceneCatalog.runs.filter(\.osSensitive).map(\.name), ["text-caption"])
    }
}
