// SceneModulationRestoreTests.swift — MOD-013 acceptance: "Round-trip restores every valid edge and
// flags orphaned targets" (MOD-013-T11 to T13; MOD-013-S1, S2; contract M3 to M6).
import Compositor
import Foundation
import ParameterGraph
import ProceduralMaterials
@testable import SceneFormat
import VisualParameters
import XCTest

enum MigrationFixtures {
    typealias IDs = VisualParameterIDs

    /// The app's catalogs plus a history: `effect.glow.amount` became `effect.glow.strength` (table
    /// version 1), which became `effect.bloom.intensity` (2); `effect.glow.old` became
    /// `effect.bloom.legacy` (1), retired later without a rule; `audio.kick` became `audio.onset`
    /// (2); `audio.flux` was retired (2).
    static func registry() throws -> ParameterRegistry {
        let migrations = try ModulationIDMigrations([
            .renamed("effect.glow.amount", to: "effect.glow.strength", since: 1),
            .renamed("effect.glow.old", to: "effect.bloom.legacy", since: 1),
            .renamed("effect.glow.strength", to: IDs.bloomIntensity.rawValue, since: 2),
            .renamed("audio.kick", to: "audio.onset", since: 2),
            .retired("audio.flux", since: 2),
        ])
        return try ParameterRegistry(descriptors: VisualParameterCatalog.descriptors + ProceduralMaterialCatalog.descriptors,
                                     retiredIDs: ["effect.glow.amount", "effect.glow.strength", "effect.glow.old", "effect.bloom.legacy"],
                                     migrations: migrations)
    }

    static let lfo = ModulationGenerator(id: "lfo.one", displayName: "LFO One", inputs: ["rate"])

    static func multiply(_ source: String, _ target: ParameterID, _ start: Double = 1, _ end: Double = 0.25,
                         expression: String? = nil, extra: [String: SceneJSON] = [:]) -> SceneBinding {
        SceneBinding(sourceID: source, target: target, mapping: LinearMapping(outputStart: start, outputEnd: end), mix: .multiply,
                     expression: expression, extra: extra)
    }

    static func connection(_ source: SceneNodeRef, _ target: SceneNodeRef, _ input: String = ModulationEdge.valueInput) -> SceneConnection {
        SceneConnection(source: source, target: target, input: input)
    }

    /// One document with every case of MOD-013-S1.
    static func everyCase() -> SceneDocument {
        let bindings: [SceneBinding] = [
            SceneBinding(source: .band(2), target: IDs.circularSpectrumGap,
                         mapping: LinearMapping(inputMinimum: 0, inputMaximum: 0.8, outputStart: 0, outputEnd: 0.5),
                         envelope: AudioFeatureEnvelope(attackSeconds: 0.05, releaseSeconds: 0.3), expression: "audio.onset * 2"),
            multiply("audio.kick", "effect.glow.amount"),                                   // renamed twice + source renamed
            multiply("audio.onset", "effect.bloom.legacy"),                                 // retired (no rule)
            multiply("audio.beatConfidence", "visual.future.sparkle"),                      // unknown target
            multiply("audio.band.200", IDs.bloomThreshold, extra: ["futureCurve": .string("easeIn")]), // unknown source
            multiply("audio.bandMean", IDs.linearSpectrumSpacing, 0, 1, expression: "audio.bandMean + 1"),
            SceneBinding(source: .band(5), target: IDs.bloomRadius, mapping: LinearMapping(outputStart: 0, outputEnd: 5)), // out of range
        ]
        let connections: [SceneConnection] = [
            connection(.generator("lfo.one"), .parameter(IDs.bloomKnee)),
            connection(.parameter(IDs.bloomKnee), .generator("lfo.one"), "rate"),          // closes a loop
            connection(.audio("audio.flux"), .generator("lfo.one"), "rate"),               // retired audio feature
            connection(.generator("lfo.one"), .parameter("visual.future.thing")),          // unknown target
            connection(.audio("audio.kick"), .generator("lfo.one"), "rate"),               // renamed source
        ]
        return SceneDocument(id: SceneFixtures.sceneID, name: "Edges", bindings: bindings,
                             modulation: SceneModulation(generators: [lfo], connections: connections))
    }
}

final class SceneModulationRestoreTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    func testEveryCategoryIsReportedWithItsPath() throws {
        let registry = try MigrationFixtures.registry()
        let document = MigrationFixtures.everyCase()
        let loaded = try document.liveState(registry: registry, assets: FakeAvailability())   // the scene opens
        let report = loaded.modulationReport
        XCTAssertEqual(report.entries.map { (e: SceneModulationReport.Entry) -> String in "\(e.path) \(e.outcome.rawValue)" }, [
            "$.bindings[0] restored", "$.bindings[1] rewritten", "$.bindings[2] dropped", "$.bindings[3] orphaned",
            "$.bindings[4] orphaned", "$.bindings[5] restored", "$.bindings[6] rejected",
            "$.modulation.connections[0] restored", "$.modulation.connections[1] rejected", "$.modulation.connections[2] dropped",
            "$.modulation.connections[3] orphaned", "$.modulation.connections[4] rewritten",
        ])
        XCTAssertEqual(report.entries[1].written, "audio.kick → effect.glow.amount")
        XCTAssertEqual(report.entries[1].applied, "audio.onset → effect.bloom.intensity")
        XCTAssertEqual(report.entries[2].reason, "\"effect.bloom.legacy\" is retired")
        XCTAssertEqual(report.entries[3].reason, "\"visual.future.sparkle\" is not a parameter of this version")
        XCTAssertEqual(report.entries[4].reason, "the audio feature \"audio.band.200\" is not known to this version")
        XCTAssertTrue(report.entries[8].reason.contains("effect.bloom.knee → lfo.one.rate → effect.bloom.knee"), report.entries[8].reason)
        XCTAssertEqual(report.entries[11].applied, "audio.onset → lfo.one.rate")
        XCTAssertEqual(report.paths(.orphaned), ["$.bindings[3]", "$.bindings[4]", "$.modulation.connections[3]"])
        XCTAssertEqual("\(report.entries[1])",
                       "rewritten $.bindings[1]: audio.kick → effect.glow.amount as audio.onset → effect.bloom.intensity (migrated to audio.onset → effect.bloom.intensity)")

        // The same outcomes as scene issues (all warnings), each at its path.
        XCTAssertEqual(loaded.warnings.map { (i: SceneIssue) -> String in "\(i.code.rawValue) \(i.path)" }, [
            "migratedReference $.bindings[1]", "retiredReference $.bindings[2]", "orphanedBinding $.bindings[3].target",
            "orphanedBinding $.bindings[4].source", "invalidBinding $.bindings[6]",
            "rejectedConnection $.modulation.connections[1]", "retiredReference $.modulation.connections[2]",
            "orphanedConnection $.modulation.connections[3]", "migratedReference $.modulation.connections[4]",
        ])
        XCTAssertFalse(loaded.warnings.contains(where: \.isError))

        // Every valid edge is live, migrated, in document order; nothing else is.
        let state = loaded.state
        XCTAssertEqual(state.bindings.map { (b: AudioFeatureBinding) -> String in b.source.id + " → " + b.target.rawValue },
                       ["audio.band.2 → visual.circularSpectrum.gap", "audio.onset → effect.bloom.intensity",
                        "audio.bandMean → visual.linearSpectrum.spacing"])
        XCTAssertEqual(state.expressions, [IDs.circularSpectrumGap: "audio.onset * 2", IDs.linearSpectrumSpacing: "audio.bandMean + 1"])
        XCTAssertEqual(state.modulation.edges.map(\.description), ["lfo.one → effect.bloom.knee", "audio.onset → lfo.one.rate"])
        XCTAssertEqual(state.modulation.generators, [MigrationFixtures.lfo])
        let graph = try state.validatedGraph(registry: registry)
        XCTAssertEqual(graph.graph.edges.count, 5)
        let modulator = AudioFeatureModulator(registry: registry)
        try state.apply(to: modulator)
        XCTAssertEqual(modulator.bindings, state.bindings)

        // Orphaned and rejected edges are preserved verbatim, dropped ones are not.
        XCTAssertEqual(state.preserved.bindings, [document.bindings[3], document.bindings[4], document.bindings[6]])
        XCTAssertEqual(state.preserved.bindings[1].extra["futureCurve"], .string("easeIn"))
        XCTAssertEqual(state.preserved.connections, [document.modulation.connections[1], document.modulation.connections[3]])
    }

    func testReSavingKeepsOrphansWritesMigratedIDsAndReachesAFixedPoint() throws {
        let registry = try MigrationFixtures.registry()
        let loaded = try MigrationFixtures.everyCase().liveState(registry: registry)
        let saved = try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Edges")
        XCTAssertEqual(saved.bindings.map(\.edgeText), [
            "audio.band.2 → visual.circularSpectrum.gap", "audio.onset → effect.bloom.intensity",
            "audio.bandMean → visual.linearSpectrum.spacing", "audio.beatConfidence → visual.future.sparkle",
            "audio.band.200 → effect.bloom.threshold", "audio.band.5 → effect.bloom.radius",
        ])
        XCTAssertEqual(saved.bindings[0].expression, "audio.onset * 2")
        XCTAssertEqual(saved.modulation.connections.map(\.description), [
            "lfo.one → effect.bloom.knee", "audio.onset → lfo.one.rate", "effect.bloom.knee → lfo.one.rate", "lfo.one → visual.future.thing",
        ])

        // capture → encode → decode → restore → capture is a fixed point (byte-identical).
        let bytes = saved.encoded()
        let reopened = try SceneDocument.decode(bytes)
        XCTAssertEqual(reopened.warnings, [])
        let again = try reopened.document.liveState(registry: registry)
        XCTAssertEqual(try SceneDocument(capturing: again.state, id: SceneFixtures.sceneID, name: "Edges").encoded(), bytes)
        XCTAssertEqual(again.modulationReport.entries.map(\.outcome),
                       [.restored, .restored, .restored, .orphaned, .orphaned, .rejected, .restored, .restored, .rejected, .orphaned])
        // The orphans are still flagged after the round trip.
        XCTAssertEqual(again.modulationReport.paths(.orphaned), ["$.bindings[3]", "$.bindings[4]", "$.modulation.connections[3]"])
    }

    func testRestoredEdgesEvaluateLikeTheOriginal() throws {
        let registry = try SceneFixtures.registry()
        let original = AudioFeatureModulator(registry: registry)
        try original.bind(AudioFeatureBinding(source: .band(3), target: IDs.circularSpectrumGap, inputMaximum: 0.9, outputStart: 0.1,
                                              outputEnd: 0.6, envelope: AudioFeatureEnvelope(attackSeconds: 0.02, releaseSeconds: 0.4)))
        try original.bind(AudioFeatureBinding(source: .onset, target: IDs.bloomIntensity, outputStart: 1, outputEnd: 0.5, mixMode: .multiply))
        try original.bind(AudioFeatureBinding(source: .bandMean, target: IDs.circularSpectrumInnerRadius, outputStart: -0.2,
                                              outputEnd: 0.3, mixMode: .add, envelope: AudioFeatureEnvelope(attackSeconds: 0.1, releaseSeconds: 0.1)))
        try original.bind(AudioFeatureBinding(source: .beatConfidence, target: IDs.bloomThreshold, inputMinimum: 0.2, inputMaximum: 0.8,
                                              outputStart: 0.9, outputEnd: 0.2))
        let live = SceneLiveState(stack: LayerStack(), bindings: original.bindings,
                                  modulation: ModulationGraph(generators: [MigrationFixtures.lfo],
                                                              edges: [ModulationEdge(source: .generator("lfo.one"), target: .parameter(IDs.bloomKnee))]))
        let bytes = try SceneDocument(capturing: live, id: SceneFixtures.sceneID, name: "Eval").encoded()
        let loaded = try SceneDocument.decode(bytes).document.liveState(registry: registry)
        XCTAssertEqual(loaded.modulationReport.entries.map(\.outcome), [.restored, .restored, .restored, .restored, .restored])
        let restored = AudioFeatureModulator(registry: registry)
        try loaded.state.apply(to: restored)
        XCTAssertEqual(restored.bindings, original.bindings)
        XCTAssertEqual(loaded.state.modulation, live.modulation)

        // 64 frames, a fixed 60 Hz clock, deterministic features: bit-identical effective values.
        var bands = [Float](repeating: 0, count: 8)
        let targets: [ParameterID] = [IDs.circularSpectrumGap, IDs.bloomIntensity, IDs.circularSpectrumInnerRadius, IDs.bloomThreshold]
        var compared = 0
        for frame in 0..<64 {
            let phase = Double(frame) * 0.37
            for k in bands.indices { bands[k] = Float(0.5 + 0.5 * sin(phase + Double(k))) }
            let onset = Float(frame % 7 == 0 ? 1.0 : 0.1)
            let confidence = 0.5 + 0.4 * cos(phase)
            let time = UInt64(frame) * 16_666_667
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                let f = AudioFeatureFrame(bands: buffer, onset: onset, beatConfidence: confidence)
                original.advance(frame: f, timeNanoseconds: time)
                restored.advance(frame: f, timeNanoseconds: time)
            }
            for target in targets {
                let a = original.value(for: target, manual: 0.4)
                let b = restored.value(for: target, manual: 0.4)
                XCTAssertEqual(a.bitPattern, b.bitPattern, "\(target) frame \(frame)")
                compared += 1
            }
        }
        XCTAssertEqual(compared, 256)
    }

    func testMigrationThroughAScene() throws {
        let registry = try MigrationFixtures.registry()
        let document = SceneDocument(id: SceneFixtures.sceneID, name: "Old", bindings: [
            MigrationFixtures.multiply("audio.onset", "effect.glow.strength"),   // renamed once (v2)
            MigrationFixtures.multiply("audio.onset", "effect.glow.old"),        // renamed, then retired
            MigrationFixtures.multiply("audio.onset", "effect.glow.amount"),     // renamed twice: same target as binding 0
        ])
        let loaded = try document.liveState(registry: registry)
        XCTAssertEqual(loaded.modulationReport.entries.map { (e: SceneModulationReport.Entry) -> String in "\(e.outcome.rawValue) \(e.reason)" }, [
            "rewritten migrated to audio.onset → effect.bloom.intensity",
            "dropped \"effect.bloom.legacy\" is retired",
            "rejected \"effect.bloom.intensity\" is already bound by binding 0",
        ])
        let saved = try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Old")
        XCTAssertEqual(saved.bindings.map(\.edgeText), ["audio.onset → effect.bloom.intensity", "audio.onset → effect.glow.amount"])
        // Without the history, the old IDs are merely unknown: orphaned and kept, never applied.
        let plain = try document.liveState(registry: try SceneFixtures.registry())
        XCTAssertEqual(plain.modulationReport.entries.map(\.outcome), [.orphaned, .orphaned, .orphaned])
        XCTAssertEqual(plain.state.bindings, [])
    }

    func testMalformedIDsAreRejectedNeverOrphaned() throws {
        let registry = try MigrationFixtures.registry()
        let document = SceneDocument(id: SceneFixtures.sceneID, name: "Bad", bindings: [
            MigrationFixtures.multiply("audio.onset", "Bad"),
            MigrationFixtures.multiply("lfo.one", IDs.bloomIntensity),
        ], modulation: SceneModulation(generators: [MigrationFixtures.lfo], connections: [
            MigrationFixtures.connection(.audio("audio.a-b"), .generator("lfo.one"), "rate"),
            MigrationFixtures.connection(.generator("lfo.two"), .parameter(IDs.bloomKnee)),   // undeclared generator
        ]))
        let report = document.restoreModulation(registry: registry).report
        XCTAssertEqual(report.entries.map(\.outcome), [.rejected, .rejected, .rejected, .rejected])
        XCTAssertEqual(report.entries[1].reason, "the audio feature ID \"lfo.one\" is ill-formed")
    }
}
