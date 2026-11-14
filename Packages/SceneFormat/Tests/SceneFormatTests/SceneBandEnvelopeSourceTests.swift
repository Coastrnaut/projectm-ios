// SceneBandEnvelopeSourceTests.swift — MOD-015-T07 (MOD-015-R5, S4; contract band-envelopes B7): a binding from a
// band envelope round-trips through the scene document by its stable source ID and is restored.
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneBandEnvelopeSourceTests: XCTestCase {
    func testBandEnvelopeBindingRoundTripsAndRestores() throws {
        let registry = try SceneFixtures.registry()
        let binding = AudioFeatureBinding(source: .bandEnvelope(0, .slow), target: VisualParameterIDs.bloomIntensity,
                                          outputStart: 0, outputEnd: 1)
        let document = SceneDocument(id: SceneFixtures.sceneID, name: "Envelope",
                                     bindings: SceneBinding.list([binding], expressions: [:]))
        let json = try SceneJSON.parse(document.encoded())
        let stored: [SceneJSON] = try XCTUnwrap(json.objectValue?["bindings"]?.arrayValue)
        XCTAssertEqual(stored.first?.objectValue?["source"], .string("audio.bandEnvelope.slow.0"))
        let loaded = try SceneDocument.decode(document.encoded()).document.liveState(registry: registry)
        XCTAssertEqual(loaded.modulationReport.entries.map(\.outcome), [.restored])
        XCTAssertEqual(loaded.state.bindings, [binding])
    }
}
