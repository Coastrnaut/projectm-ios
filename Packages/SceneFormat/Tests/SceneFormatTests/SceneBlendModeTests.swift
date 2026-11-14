// CMP-004-T12 (US3; CMP-004-S5, R7, R8): the scene format draws the six blend mode names, keeps any
// other name verbatim (decode → encode and load → capture) and reports it. CPU only, runs on Linux.
import Compositor
import Foundation
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneBlendModeTests: XCTestCase {
    private func scene(blends: [String]) -> SceneDocument {
        let layers = blends.enumerated().map { (pair: (offset: Int, element: String)) -> SceneLayer in
            SceneLayer(instance: UInt64(pair.offset + 1), content: pair.offset == 0 ? .circularSpectrum : .linearSpectrum,
                       composite: SceneComposite(opacity: 0.8, blendMode: pair.element))
        }
        return SceneDocument(id: SceneFixtures.sceneID, name: "Blends", layers: layers, parameters: [:])
    }

    func testKnownNamesGiveNoWarningAndReachTheLiveStack() throws {
        let registry = try SceneFixtures.registry()
        for mode in LayerBlendMode.allCases {
            let document = scene(blends: ["normal", mode.rawValue])
            XCTAssertFalse(document.validate(registry: registry).contains { (i: SceneIssue) -> Bool in i.code == .unsupportedBlendMode },
                           "\(mode) is drawn, not warned about")
            let loaded = try document.liveState(registry: registry)
            XCTAssertEqual(loaded.state.stack.entries.map(\.settings.blendMode), [.normal, mode])
            XCTAssertEqual(loaded.state.preservedBlendModes, [:])
            let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
            XCTAssertEqual(captured.layers.map(\.composite.blendMode), ["normal", mode.rawValue], "capture writes the name")
            XCTAssertEqual(captured, document, "load → capture is a fixed point for \(mode)")
        }
    }

    func testUnknownNamesAreKeptReportedAndDrawnAsNormal() throws {
        let registry = try SceneFixtures.registry()
        for unknown in ["softLight", "Screen"] {
            let document = scene(blends: ["multiply", unknown])
            // decode → encode keeps the string.
            let decoded = try SceneDocument.decode(document.encoded())
            XCTAssertEqual(decoded.document.layers[1].composite.blendMode, unknown)
            XCTAssertEqual(decoded.document.encoded(), document.encoded())

            let issues = document.validate(registry: registry)
            XCTAssertEqual(issues.map(\.code), [.unsupportedBlendMode])
            XCTAssertEqual(issues.first?.path, "$.layers[1].composite.blend")

            let report = SceneRepairReport(document: document, registry: registry)
            XCTAssertEqual(report.entries.map(\.code), ["unsupportedBlendMode"])
            XCTAssertEqual(report.entries.first?.group, .valuesAdjusted)
            XCTAssertEqual(report.entries.first?.severity, .note)
            XCTAssertTrue(report.canOpenAsIs)

            let loaded = try document.liveState(registry: registry)
            XCTAssertEqual(loaded.state.stack.entries.map(\.settings.blendMode), [.multiply, .normal], "drawn as normal")
            XCTAssertEqual(loaded.state.preservedBlendModes, [LayerInstanceID(rawValue: 2): unknown])
            let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
            XCTAssertEqual(captured.layers.map(\.composite.blendMode), ["multiply", unknown], "load → capture keeps \(unknown)")
        }
    }

    func testAPreservedNameYieldsToAModeSetLive() throws {
        let registry = try SceneFixtures.registry()
        let document = scene(blends: ["normal", "softLight"])
        var state = try document.liveState(registry: registry).state
        let id = LayerInstanceID(rawValue: 2)
        try state.stack.setSettings(LayerCompositeSettings(opacity: 0.8, blendMode: .screen), of: id)
        let captured = try SceneDocument(capturing: state, id: document.id, name: document.name)
        XCTAssertEqual(captured.layers[1].composite.blendMode, "screen", "a mode chosen live replaces the kept name")
    }
}
