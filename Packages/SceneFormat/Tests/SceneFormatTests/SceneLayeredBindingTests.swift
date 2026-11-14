// SceneLayeredBindingTests.swift — MOD-011-T06 (MOD-011-R7, S5; contract mix-order O3): several bindings on one
// parameter restore as layers in document order, round-trip unchanged, and give the same values as the
// original modulator; a fifth is rejected and kept verbatim.
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneLayeredBindingTests: XCTestCase {
    static let intensity: ParameterID = VisualParameterIDs.bloomIntensity

    static func layers() -> [AudioFeatureBinding] {
        [AudioFeatureBinding(source: .band(0), target: intensity, outputStart: 0.2, outputEnd: 0.8, mixMode: .replace),
         AudioFeatureBinding(source: .lfo(0), target: intensity, outputStart: 0, outputEnd: 0.3, mixMode: .add),
         AudioFeatureBinding(source: .band(1), target: intensity, outputStart: 0.5, outputEnd: 1, mixMode: .multiply)]
    }

    func testLayersRoundTripInOrder() throws {
        let registry = try SceneFixtures.registry()
        let stored = SceneBinding.list(Self.layers(), expressions: [Self.intensity: "audio.onset * 2"])
        XCTAssertEqual(stored.map(\.expression), ["audio.onset * 2", nil, nil], "the expression is on the first layer only")
        let document = SceneDocument(id: SceneFixtures.sceneID, name: "Layers", bindings: stored)
        let loaded = try document.liveState(registry: registry)
        XCTAssertEqual(loaded.modulationReport.entries.map(\.outcome), [.restored, .restored, .restored])
        XCTAssertEqual(loaded.state.bindings, Self.layers())
        XCTAssertEqual(loaded.state.expressions, [Self.intensity: "audio.onset * 2"])
        let saved = try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Layers")
        XCTAssertEqual(saved.bindings, stored, "capture writes the layers back unchanged")
        // The restored layers evaluate exactly like the originals.
        let original = AudioFeatureModulator(registry: registry)
        let restored = AudioFeatureModulator(registry: registry)
        for b in Self.layers() { try original.addLayer(b) }
        for b in loaded.state.bindings { try restored.addLayer(b) }
        let bands: [Float] = [0.5, 0.5]
        let lfos: [Double] = [0.5]
        for m in [original, restored] {
            bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
                lfos.withUnsafeBufferPointer { (l: UnsafeBufferPointer<Double>) -> Void in
                    m.advance(frame: AudioFeatureFrame(bands: b, lfos: l), timeNanoseconds: 1_000)
                }
            }
        }
        let value: Double = restored.value(for: Self.intensity, manual: 0.4)
        XCTAssertEqual(value.bitPattern, original.value(for: Self.intensity, manual: 0.4).bitPattern)
        XCTAssertEqual(value, 0.4875, accuracy: 1e-12, "replace 0.5, + 0.15, × 0.75")
    }

    func testFifthLayerIsRejectedAndKept() throws {
        let registry = try SceneFixtures.registry()
        let layers = Self.layers() + [Self.layers()[1], Self.layers()[1]]   // five on one parameter
        let document = SceneDocument(id: SceneFixtures.sceneID, name: "Five", bindings: layers.map { (b: AudioFeatureBinding) -> SceneBinding in SceneBinding(b) })
        let loaded = try document.liveState(registry: registry)
        XCTAssertEqual(loaded.modulationReport.entries.map(\.outcome), [.restored, .restored, .restored, .restored, .rejected])
        XCTAssertEqual(loaded.state.bindings.count, 4)
        let saved = try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Five")
        XCTAssertEqual(saved.bindings.count, 5, "the rejected fifth binding is kept verbatim")
    }
}
