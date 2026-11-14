// SceneEnvelopeTests.swift — MOD-005-T06: a binding's attack and release times survive save and
// reopen with a bit-identical step response, scenes without them (or with only one) read the MOD-002
// defaults, and an invalid time rejects its binding, keeps it for re-save and is reported at the
// envelope's path (MOD-005-R9, R10, S3; contract E7; research MOD-005-D5).
import Foundation
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneEnvelopeTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    private func document(_ envelope: AudioFeatureEnvelope) -> SceneDocument {
        let binding = SceneBinding(sourceID: "audio.band.0", target: IDs.bloomIntensity,
                                   mapping: LinearMapping(outputStart: 0, outputEnd: 1), envelope: envelope)
        return SceneDocument(id: SceneFixtures.sceneID, name: "Envelopes", bindings: [binding])
    }

    /// `bytes` with the first binding's `envelope` field replaced by `transform` of it (nil removes it).
    private func rewritingEnvelope(_ bytes: [UInt8], _ transform: (SceneJSON?) -> SceneJSON?) throws -> [UInt8] {
        var root = try XCTUnwrap(SceneJSONParser.parse(bytes, maximumDepth: 32).objectValue)
        var bindings = try XCTUnwrap(root["bindings"]?.arrayValue)
        var first = try XCTUnwrap(bindings.first?.objectValue)
        first["envelope"] = transform(first["envelope"])
        bindings[0] = .object(first)
        root["bindings"] = .array(bindings)
        return SceneJSONWriter.write(.object(root))
    }

    /// The signal of `binding` after a 0→1→0 step at 60 fps.
    private func stepResponse(_ binding: AudioFeatureBinding, registry: ParameterRegistry) throws -> [Double] {
        let modulator = AudioFeatureModulator(registry: registry)
        try modulator.bind(binding)
        var trace: [Double] = []
        var time: UInt64 = 2_000_000_000
        for frame in 0..<120 {
            let bands: [Float] = [frame < 60 ? 1 : 0]
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                modulator.advance(frame: AudioFeatureFrame(bands: buffer), timeNanoseconds: time)
            }
            trace.append(modulator.signal(for: binding.target) ?? .nan)
            time += 16_666_667
        }
        return trace
    }

    // MOD-005-S3: exact times and a bit-identical step response after save and reopen.
    func testTimesSurviveSaveAndReopenWithIdenticalStepResponse() throws {
        let registry = try SceneFixtures.registry()
        let envelope = AudioFeatureEnvelope(attackSeconds: 0.08, releaseSeconds: 1.5)
        let original = document(envelope)
        let bytes: [UInt8] = original.encoded()
        let reopened = try SceneDocument.decode(bytes)
        XCTAssertEqual(reopened.warnings, [])
        XCTAssertEqual(reopened.document.bindings.first?.envelope, envelope)
        let loaded = try reopened.document.liveState(registry: registry)
        XCTAssertEqual(loaded.warnings, [])
        let restored = try XCTUnwrap(loaded.state.bindings.first)
        XCTAssertEqual(restored.envelope, envelope)
        let authored = try XCTUnwrap(original.bindings.first).audioFeatureBinding(source: .band(0), target: IDs.bloomIntensity)
        let expected = try stepResponse(authored, registry: registry)
        XCTAssertEqual(try stepResponse(restored, registry: registry), expected, "bit-identical motion after reopening")
        XCTAssertGreaterThan(expected[59], 0.99, "the fast attack has risen")
        XCTAssertGreaterThan(expected[119], 0.5, "the slow release is still falling")
        let saved = try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Envelopes")
        XCTAssertEqual(saved.encoded(), bytes, "capture → encode is byte-identical")
    }

    // MOD-005-R9: scenes stored without the field, or with one time, read the MOD-002 defaults.
    func testMissingTimesReadZero() throws {
        let bytes: [UInt8] = document(AudioFeatureEnvelope(attackSeconds: 0.08, releaseSeconds: 1.5)).encoded()
        let noEnvelope = try rewritingEnvelope(bytes) { (_: SceneJSON?) -> SceneJSON? in nil }
        XCTAssertEqual(try SceneDocument.decode(noEnvelope).document.bindings.first?.envelope, AudioFeatureEnvelope.none)
        let attackOnly = try rewritingEnvelope(bytes) { (_: SceneJSON?) -> SceneJSON? in .object(["attack": .double(0.2)]) }
        let decoded = try SceneDocument.decode(attackOnly)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.document.bindings.first?.envelope, AudioFeatureEnvelope(attackSeconds: 0.2, releaseSeconds: 0))
        let loaded = try decoded.document.liveState(registry: try SceneFixtures.registry())
        XCTAssertEqual(loaded.warnings, [])
        XCTAssertEqual(loaded.state.bindings.first?.envelope, AudioFeatureEnvelope(attackSeconds: 0.2, releaseSeconds: 0))
    }

    // MOD-005-R10: an invalid time is reported at the envelope, and the binding is kept for re-save.
    func testInvalidTimeRejectsTheBindingAtTheEnvelopePath() throws {
        let registry = try SceneFixtures.registry()
        for envelope in [AudioFeatureEnvelope(attackSeconds: -1, releaseSeconds: 0.1),
                         AudioFeatureEnvelope(attackSeconds: 0.1, releaseSeconds: 61)] {
            let bytes: [UInt8] = document(envelope).encoded()
            let reopened = try SceneDocument.decode(bytes)
            XCTAssertEqual(reopened.document.bindings.first?.envelope, envelope, "read as written, not repaired")
            let loaded = try reopened.document.liveState(registry: registry)   // the scene still opens
            let error = AudioFeatureBindingError.invalidEnvelope(IDs.bloomIntensity)
            XCTAssertEqual(loaded.warnings, [SceneIssue(.invalidBinding, path: "$.bindings[0].envelope", "Binding 0: \(error.description).")])
            XCTAssertEqual(loaded.modulationReport.entries.map(\.outcome), [.rejected])
            XCTAssertEqual(loaded.state.bindings, [], "not applied")
            let saved = try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Envelopes")
            XCTAssertEqual(saved.encoded(), bytes, "kept verbatim for re-save")
        }
    }
}
