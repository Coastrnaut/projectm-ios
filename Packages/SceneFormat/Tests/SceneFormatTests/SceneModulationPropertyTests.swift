// SceneModulationPropertyTests.swift — 200 seeded random edge sets reach a fixed point after one
// capture, and every preserved edge survives the re-save (MOD-013-T14; MOD-013-S3; contract M6).
//
// Fixed seed (SplitMix64, from ScenePropertyTests), so every host checks the same documents. Each
// document mixes valid, renamed, retired, unknown and malformed IDs, invalid mappings, bad
// expressions, duplicate targets and loops.
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneModulationPropertyTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    private let sources = ["audio.band.0", "audio.band.7", "audio.onset", "audio.bandMean", "audio.beatConfidence", "audio.legacyPulse",
                           "audio.flux", "audio.band.200", "audio.newThing", "Bad"]
    private let targets: [ParameterID] = [IDs.circularSpectrumGap, IDs.circularSpectrumInnerRadius, IDs.bloomIntensity,
                                          IDs.bloomThreshold, IDs.bloomKnee, "effect.glow.amount", "effect.glow.old",
                                          "visual.future.x", "Bad", IDs.circularSpectrumBarCount]
    private let expressions: [String?] = [nil, nil, "audio.onset * 2", "audio.onset *"]

    private func document(_ rng: inout SplitMix64) -> SceneDocument {
        func pick<T>(_ items: [T]) -> T { items[Int(rng.next() % UInt64(items.count))] }
        var bindings: [SceneBinding] = []
        for _ in 0..<Int(rng.next() % 9) {
            let end: Double = rng.next() % 8 == 0 ? 2 : Double(rng.next() % 1_000) / 1_000
            bindings.append(SceneBinding(sourceID: pick(sources), target: pick(targets),
                                         mapping: LinearMapping(outputStart: 1, outputEnd: end), mix: .multiply,
                                         expression: pick(expressions),
                                         extra: rng.next() % 4 == 0 ? ["future": .integer(Int64(rng.next() % 100))] : [:]))
        }
        let nodes: [SceneNodeRef] = [.generator("lfo.one"), .generator("lfo.two"), .parameter(IDs.bloomKnee), .parameter(IDs.bloomRadius),
                                     .parameter("visual.future.y"), .parameter("effect.glow.amount"), .audio("audio.onset"),
                                     .audio("audio.legacyPulse"), .audio("audio.flux"), .audio("audio.zzz")]
        var connections: [SceneConnection] = []
        for _ in 0..<Int(rng.next() % 7) {
            connections.append(SceneConnection(source: pick(nodes), target: pick(nodes), input: rng.next() % 2 == 0 ? "value" : "rate"))
        }
        let generators = [ModulationGenerator(id: "lfo.one", displayName: "LFO One", inputs: ["rate"]),
                          ModulationGenerator(id: "lfo.two", displayName: "LFO Two", inputs: ["rate"])]
        return SceneDocument(id: SceneFixtures.sceneID, name: "Random", bindings: bindings,
                             modulation: SceneModulation(generators: generators, connections: connections))
    }

    func testCaptureIsAFixedPointAndPreservedEdgesSurvive() throws {
        let registry = try MigrationFixtures.registry()
        var rng = SplitMix64(state: 0x4D4F_442D_3031_33)   // "MOD-013"
        var outcomes: [SceneModulationOutcome: Int] = [:]
        for n in 0..<200 {
            let original = document(&rng)
            let first = try original.liveState(registry: registry)
            for entry in first.modulationReport.entries { outcomes[entry.outcome, default: 0] += 1 }
            XCTAssertEqual(first.modulationReport.entries.count, original.bindings.count + original.modulation.connections.count, "doc \(n)")
            let captured = try SceneDocument(capturing: first.state, id: original.id, name: original.name)
            // Preserved edges are written back verbatim, after the live ones; dropped ones are gone.
            let preserved = first.state.preserved
            XCTAssertEqual(Array(captured.bindings.suffix(preserved.bindings.count)), preserved.bindings, "doc \(n)")
            XCTAssertEqual(Array(captured.modulation.connections.suffix(preserved.connections.count)), preserved.connections, "doc \(n)")
            let dropped = first.modulationReport.paths(.dropped).count
            XCTAssertEqual(captured.bindings.count + captured.modulation.connections.count,
                           original.bindings.count + original.modulation.connections.count - dropped, "doc \(n)")
            // capture → encode → decode → restore → capture: byte-identical.
            let bytes = captured.encoded()
            let reopened = try SceneDocument.decode(bytes).document.liveState(registry: registry)
            XCTAssertEqual(reopened.state.bindings, first.state.bindings, "doc \(n)")
            XCTAssertEqual(reopened.state.modulation, first.state.modulation, "doc \(n)")
            XCTAssertEqual(try SceneDocument(capturing: reopened.state, id: original.id, name: original.name).encoded(), bytes, "doc \(n)")
            XCTAssertEqual(reopened.modulationReport.paths(.dropped), [], "doc \(n)")
        }
        // The generator reaches every outcome.
        for outcome in SceneModulationOutcome.allCases { XCTAssertGreaterThan(outcomes[outcome] ?? 0, 10, "\(outcome)") }
    }
}
