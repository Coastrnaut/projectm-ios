// SceneValidationTests.swift — every validation issue with its exact code, path and message
// (SCN-001-T16; SCN-001-S3; contract C5).
import Compositor
import Foundation
import GeneratorGraphImport
import ParameterExpression
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneValidationTests: XCTestCase {
    private typealias Expected = (SceneIssue.Code, String, String)

    /// The all-kinds fixture without its unknown layer: no issue at all.
    private func clean() throws -> SceneDocument {
        var d = try SceneFixtures.allKinds()
        d.layers.removeLast()
        return d
    }

    private func check(_ name: String, availability: FakeAvailability = FakeAvailability(), _ expected: [Expected],
                       file: StaticString = #filePath, line: UInt = #line, _ mutate: (inout SceneDocument) throws -> Void) throws {
        var d = try clean()
        try mutate(&d)
        let issues = d.validate(registry: try SceneFixtures.registry(), assets: availability)
        XCTAssertEqual(issues.map { (i: SceneIssue) -> String in "\(i.code.rawValue) | \(i.path) | \(i.message)" },
                       expected.map { (e: Expected) -> String in "\(e.0.rawValue) | \(e.1) | \(e.2)" }, name, file: file, line: line)
        for (issue, e) in zip(issues, expected) { XCTAssertEqual(issue.severity, e.0.severity, name, file: file, line: line) }
    }

    func testCleanFixtureHasNoIssue() throws {
        XCTAssertEqual(try clean().validate(registry: try SceneFixtures.registry(), assets: FakeAvailability()), [])
    }

    func testHeaderAndLayerIssues() throws {
        try check("lowercase ID", [(.invalidSceneID, "$.id", "The scene ID \"6f9619ff-8b86-d011-b42d-00c04fc964ff\" is not an uppercase UUID.")]) {
            $0.id = $0.id.lowercased()
        }
        try check("path as ID", [(.invalidSceneID, "$.id", "The scene ID \"/tmp/scene\" is not an uppercase UUID.")]) { $0.id = "/tmp/scene" }
        let nameMessage = "The scene name must be 1…120 characters without control characters."
        try check("blank name", [(.invalidName, "$.name", nameMessage)]) { $0.name = "  \n" }
        try check("control in name", [(.invalidName, "$.name", nameMessage)]) { $0.name = "Bell\u{07}" }
        try check("long name", [(.invalidName, "$.name", nameMessage)]) { $0.name = String(repeating: "é", count: 121) }
        try check("120 characters", []) { $0.name = String(repeating: "🎛", count: 120) }
        try check("instance 0", [(.instanceOutOfRange, "$.layers[1].instance", "Layer 1 has instance ID 0; IDs are 1…9007199254740991.")]) {
            $0.layers[1].instance = 0
        }
        try check("instance 2^53", [(.instanceOutOfRange, "$.layers[1].instance",
                                     "Layer 1 has instance ID 9007199254740992; IDs are 1…9007199254740991.")]) {
            $0.layers[1].instance = 9_007_199_254_740_992
        }
        try check("duplicate", [(.duplicateInstance, "$.layers[1].instance", "Layer 1 uses instance ID 1, already used by layer 0.")]) {
            $0.layers[1].instance = 1
        }
        try check("second camera", [(.kindLimit, "$.layers[7].kind", "Layer 7 is \"camera\" layer number 2; a scene holds at most 1.")]) {
            $0.layers.append(SceneLayer(instance: 50, content: .camera))
        }
        try check("value name", [(.invalidValueName, "$.layers[0].values",
                                  "Layer 0 has a value named \"\"; names are 1…64 bytes without control characters.")]) {
            $0.layers[0].values[""] = 1
        }
        try check("unknown kind", [(.unknownLayerKind, "$.layers[7].kind", "Layer 7 has the unknown kind \"aurora\"; it is kept but not shown.")]) {
            $0.layers.append(SceneLayer(instance: 77, content: .unknown(kind: "aurora")))
        }
        try check("blend", [(.unsupportedBlendMode, "$.layers[1].composite.blend",
                             "Layer 1 uses the blend mode \"screen\", which this version draws as normal.")]) {
            $0.layers[1].composite.blendMode = "screen"
        }
        try check("material", [(.unknownMaterial, "$.layers[5].content.material", "Layer 5 uses the unknown material \"material.lava\".")]) {
            $0.layers[5].content = .material(id: "material.lava")
        }
    }

    func testAssetIssues() throws {
        try check("dangling", [(.danglingAsset, "$.layers[2].content.asset", "Layer 2 refers to the asset \"nope\", which the scene does not define."),
                               (.unusedAsset, "$.assets.photo1", "Asset \"photo1\" is not used by any layer; it is kept.")]) {
            $0.layers[2].content = .photo(asset: "nope")
        }
        try check("mismatch", [(.assetTypeMismatch, "$.layers[2].content.asset",
                                "Layer 2 (photo) refers to the asset \"clip\", which is a video asset."),
                               (.unusedAsset, "$.assets.photo1", "Asset \"photo1\" is not used by any layer; it is kept.")]) {
            $0.layers[2].content = .photo(asset: "clip")
        }
        try check("key", [(.invalidAssetKey, "$.assets[\"Bad-Key\"]",
                           "The asset key \"Bad-Key\" must start with a lowercase ASCII letter and hold only ASCII letters and digits (at most 64)."),
                          (.unknownAssetType, "$.assets[\"Bad-Key\"].type", "Asset \"Bad-Key\" has the unknown type \"hologram\"; it is kept but not used.")]) {
            $0.assets["Bad-Key"] = SceneAsset(.unknown(type: "hologram"))
        }
        try check("path as store ID", [(.invalidStoreID, "$.assets.photo1.storeID",
                                        "Asset \"photo1\" has the store ID \"/var/mobile/a.png\"; store IDs are uppercase UUIDs, never paths.")]) {
            $0.assets["photo1"] = .photo(storeID: "/var/mobile/a.png")
        }
        try check("URL as store ID", [(.invalidStoreID, "$.assets.clip.storeID",
                                       "Asset \"clip\" has the store ID \"file:///a.mov\"; store IDs are uppercase UUIDs, never paths.")]) {
            $0.assets["clip"] = .video(storeID: "file:///a.mov")
        }
        try check("missing", availability: FakeAvailability(photos: [], videos: [SceneFixtures.videoID]),
                  [(.missingAsset, "$.assets.photo1",
                    "Asset \"photo1\" (photo \(SceneFixtures.photoID)) is not on this device; its layer draws nothing until it is restored.")]) { _ in }
        try check("damaged text", [(.invalidTextAsset, "$.assets.caption.spec", "Text asset \"caption\" is damaged.")]) {
            $0.assets["caption"] = SceneAsset(.text(spec: .string("hello")))
        }
        try check("newer text", [(.invalidTextAsset, "$.assets.caption.spec",
                                  "Text asset \"caption\" uses text format version 2, which this version cannot read.")]) {
            $0.assets["caption"] = SceneAsset(.text(spec: .object(["version": .integer(2)])))
        }
        let badGraph = SceneJSON.object(["format": .string("something else")])
        var importerMessage = ""
        do { _ = try GeneratorGraphImporter.importGraph(Data(badGraph.canonicalBytes)) } catch { importerMessage = error.message }
        XCTAssertFalse(importerMessage.isEmpty)
        try check("graph", [(.invalidGraphAsset, "$.assets.graph1.document", "Generator graph asset \"graph1\" is refused: \(importerMessage)")]) {
            $0.assets["graph1"] = SceneAsset(.generatorGraph(document: badGraph))
        }
        try check("unused", [(.unusedAsset, "$.assets.spare", "Asset \"spare\" is not used by any layer; it is kept.")]) {
            $0.assets["spare"] = .photo(storeID: SceneFixtures.photoID)
        }
    }

    func testParameterIssuesFollowMOD001Restore() throws {
        try check("malformed", [(.malformedParameterID, "$.parameters.Bad",
                                 "The parameter ID \"Bad\" is ill-formed: the ID needs at least two dot-separated segments (domain.name).")]) {
            $0.parameters["Bad"] = .boolean(true)
        }
        try check("orphan", [(.orphanedParameter, "$.parameters[\"visual.retired.thing\"]",
                              "\"visual.retired.thing\" is not a parameter of this version; its value is kept but not applied.")]) {
            $0.parameters["visual.retired.thing"] = .continuous(1)
        }
        try check("kind", [(.rejectedParameter, "$.parameters[\"visual.circularSpectrum.gap\"]",
                            "\"visual.circularSpectrum.gap\" holds a continuous value, not a integer value; the current value is kept.")]) {
            $0.parameters[VisualParameterIDs.circularSpectrumGap] = .integer(3)
        }
        try check("enum case", [(.rejectedParameter, "$.parameters[\"visual.linearSpectrum.orientation\"]",
                                 "\"visual.linearSpectrum.orientation\" has no case \"diagonal\"; the current value is kept.")]) {
            $0.parameters[VisualParameterIDs.linearSpectrumOrientation] = .enumeration("diagonal")
        }
        try check("clamped", [(.parameterClamped, "$.parameters[\"visual.circularSpectrum.gap\"]",
                               "\"visual.circularSpectrum.gap\" value 5.0 is outside its range; it is applied as 0.9.")]) {
            $0.parameters[VisualParameterIDs.circularSpectrumGap] = .continuous(5)
        }
    }

    func testBindingExpressionAndModulationIssues() throws {
        let barCount = VisualParameterIDs.circularSpectrumBarCount
        try check("not numeric", [(.invalidBinding, "$.bindings[0]",
                                   "Binding 0: \(AudioFeatureBindingError.notNumeric(barCount, kind: "enum").description).")]) {
            $0.bindings[0].target = barCount
        }
        try check("output range", [(.invalidBinding, "$.bindings[1]",
                                    "Binding 1: \(AudioFeatureBindingError.outputOutOfRange(VisualParameterIDs.bloomIntensity, .multiply, minimum: 0, maximum: 1).description).")]) {
            $0.bindings[1].mapping.outputStart = 2
        }
        try check("duplicate target", [(.duplicateBindingTarget, "$.bindings[1].target",
                                        "Binding 1 targets \"visual.circularSpectrum.gap\", already bound by binding 0.")]) {
            $0.bindings[1].target = VisualParameterIDs.circularSpectrumGap
        }
        var expressionError = ""
        do { _ = try CompiledExpression(source: "audio.onset *") } catch { expressionError = "\(error)" }
        XCTAssertFalse(expressionError.isEmpty)
        try check("expression", [(.invalidExpression, "$.bindings[0].expression", "Binding 0 expression: \(expressionError).")]) {
            $0.bindings[0].expression = "audio.onset *"
        }
        // A feedback loop: the LFO drives the glow radius and the radius drives the LFO's rate.
        let loop = SceneModulation(
            generators: [ModulationGenerator(id: "lfo.one", displayName: "LFO One", inputs: ["rate"])],
            edges: [ModulationEdge(source: .generator("lfo.one"), target: .parameter(VisualParameterIDs.bloomRadius)),
                    ModulationEdge(source: .parameter(VisualParameterIDs.bloomRadius), target: .generator("lfo.one"), input: "rate")])
        let graphIssues = ModulationGraph(generators: loop.generators, edges: loop.connections.compactMap(\.edge))
            .validate(in: try SceneFixtures.registry())
        XCTAssertEqual(graphIssues.map(\.problem), [.cycle])
        let cycleMessage = try XCTUnwrap(graphIssues.first?.message)
        XCTAssertTrue(cycleMessage.contains("effect.bloom.radius → lfo.one.rate"), cycleMessage)
        // MOD-013: the connection that closes the loop is rejected at its own path; the rest is live.
        try check("cycle", [(.rejectedConnection, "$.modulation.connections[1]",
                             "Connection 1 (effect.bloom.radius → lfo.one.rate): \(cycleMessage); it is kept but not applied.")]) {
            $0.modulation = loop
        }
        // A contradictory generator declaration still refuses the document.
        try check("generators", [(.invalidModulation, "$.modulation.generators[1]",
                                  "Modulation: " + (ModulationGraph(generators: [loop.generators[0], loop.generators[0]])
                                      .validate(in: try SceneFixtures.registry()).first?.message ?? "")),
                                 (.rejectedConnection, "$.modulation.connections[0]",
                                  "Connection 0 (lfo.one → effect.bloom.radius): the modulation section's generators are invalid; it is kept but not applied.")]) {
            $0.modulation.generators.append($0.modulation.generators[0])
        }
    }

    func testErrorsBlockOpeningAndWarningsDoNot() throws {
        var warningsOnly = try clean()
        warningsOnly.parameters["visual.retired.thing"] = .continuous(1)
        warningsOnly.layers[1].composite.blendMode = "screen"
        let loaded = try warningsOnly.liveState(registry: try SceneFixtures.registry(), assets: FakeAvailability(photos: []))
        XCTAssertEqual(loaded.warnings.map(\.code), [.unsupportedBlendMode, .missingAsset, .orphanedParameter])
        XCTAssertEqual(loaded.state.stack.count, 7)
        XCTAssertTrue(SceneIssue.Code.allCases.contains { $0.severity == .error })
    }
}
