// SceneMotionSourceTests.swift — CAM-011-T04 (CAM-011-R1; contract motion-sources M1): a binding from a motion source
// round-trips through the scene document by its stable source ID (`audio.motion.pitch`) and is restored (MOD-013 path).
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneMotionSourceTests: XCTestCase {
    func testMotionBindingRoundTripsAndRestores() throws {
        let registry = try SceneFixtures.registry()
        let binding = AudioFeatureBinding(source: .motion(.pitch), target: VisualParameterIDs.bloomIntensity,
                                          outputStart: 0, outputEnd: 1)
        let document = SceneDocument(id: SceneFixtures.sceneID, name: "Tilt",
                                     bindings: SceneBinding.list([binding], expressions: [:]))
        let json = try SceneJSON.parse(document.encoded())
        let stored: [SceneJSON] = try XCTUnwrap(json.objectValue?["bindings"]?.arrayValue)
        XCTAssertEqual(stored.first?.objectValue?["source"], .string("audio.motion.pitch"))
        let loaded = try SceneDocument.decode(document.encoded()).document.liveState(registry: registry)
        XCTAssertEqual(loaded.modulationReport.entries.map(\.outcome), [.restored])
        XCTAssertEqual(loaded.state.bindings, [binding])
    }
}
