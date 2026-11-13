// SceneLiveAdapterTests.swift — live stack, parameters and bindings through a document and back
// (SCN-001-T13; SCN-001-S2; contract C6).
import CameraLayer
import Compositor
import GeneratorGraph
import ImageLayer
import ParameterGraph
import ProceduralMaterials
@testable import SceneFormat
import SpectrumLayers
import TextLayer
import VideoLayer
import VisualParameters
import XCTest

final class SceneLiveAdapterTests: XCTestCase {
    /// What the app's hosts hold: a stack built with `add`/`move`/`setSettings` (CMP-002…005), the
    /// contents of its media layers, a parameter store and a modulator.
    private func liveState() throws -> (SceneLiveState, ParameterStore, AudioFeatureModulator,
                                        camera: LayerInstanceID, bars: LayerInstanceID, ring: LayerInstanceID) {
        var stack = LayerStack()
        let camera = try stack.add(LayerDescriptor(kind: .camera))
        let ring = try stack.add(LayerDescriptor(kind: .circularSpectrum, parameters: ["glowBoost": 0.75]),
                                 settings: LayerCompositeSettings(opacity: 0.8))
        let photo = try stack.add(LayerDescriptor(kind: .photo), settings: LayerCompositeSettings(
            opacity: 0.5, transform: try LayerTransform(translation: LayerPoint(x: 0.1, y: -0.2), uniformScale: 1.5, rotation: 0.3)))
        let video = try stack.add(LayerDescriptor(kind: .video))
        let text = try stack.add(LayerDescriptor(kind: .text))
        let material = try stack.add(LayerDescriptor(kind: .material))
        let graph = try stack.add(LayerDescriptor(kind: .generatorGraph))
        try stack.remove(video)                      // IDs are not dense afterwards
        let bars = try stack.add(LayerDescriptor(kind: .linearSpectrum), at: 0)
        try stack.move(ring, to: 4)

        let registry = try SceneFixtures.registry()
        let store = ParameterStore(registry: registry)
        try store.set(.continuous(0.3), for: VisualParameterIDs.circularSpectrumGap)
        try store.set(.enumeration("horizontal"), for: VisualParameterIDs.linearSpectrumOrientation)
        try store.set(.color(ParameterColor(red: 0.2, green: 0.4, blue: 0.6)), for: "material.gradient.colorA")
        let modulator = AudioFeatureModulator(registry: registry)
        try modulator.bind(AudioFeatureBinding(source: .band(3), target: VisualParameterIDs.circularSpectrumGap, inputMaximum: 0.9,
                                               outputStart: 0.1, outputEnd: 0.6,
                                               envelope: AudioFeatureEnvelope(attackSeconds: 0.02, releaseSeconds: 0.4)))
        try modulator.bind(AudioFeatureBinding(source: .beatConfidence, target: VisualParameterIDs.bloomIntensity,
                                               outputStart: 1, outputEnd: 0.5, mixMode: .multiply))

        let state = SceneLiveState(
            stack: stack,
            contents: [photo: .photo(asset: "photo1"), text: .text(asset: "caption"), material: .material(id: "material.tunnel"),
                       graph: .generatorGraph(asset: "graph1")],
            parameters: store.snapshot(), bindings: modulator.bindings,
            expressions: [VisualParameterIDs.circularSpectrumGap: "audio.band.3 * 0.5"],
            assets: ["photo1": .photo(storeID: SceneFixtures.photoID), "caption": SceneAsset(.text(spec: try SceneFixtures.textSpec())),
                     "graph1": SceneAsset(.generatorGraph(document: try SceneFixtures.graphDocument()))])
        return (state, store, modulator, camera, bars, ring)
    }

    func testLiveStateRoundTripsThroughCanonicalBytes() throws {
        let (live, store, modulator, camera, bars, ring) = try liveState()
        let document = try SceneDocument(capturing: live, id: SceneFixtures.sceneID, name: "Live")
        let bytes = document.encoded()
        let decoded = try SceneDocument.decode(bytes)
        XCTAssertEqual(decoded.warnings, [])
        let loaded = try decoded.document.liveState(registry: try SceneFixtures.registry(), assets: FakeAvailability())
        XCTAssertEqual(loaded.warnings, [])
        // The loaded contents name every entry's kind, camera and spectra included.
        var expected = live
        expected.contents[camera] = .camera
        expected.contents[bars] = .linearSpectrum
        expected.contents[ring] = .circularSpectrum
        XCTAssertEqual(loaded.state, expected)
        XCTAssertEqual(loaded.state.stack.ids, live.stack.ids)
        XCTAssertEqual(loaded.state.stack.entries.map(\.descriptor.kind.identifier),
                       ["spectrum.linear", "camera", "photo", "text", "spectrum.circular", "material", "generator.graph"])

        // The next new layer continues after the largest saved ID; restored IDs are never reused.
        var restoredStack = loaded.state.stack
        let next = try restoredStack.add(LayerDescriptor(kind: .linearSpectrum))
        XCTAssertEqual(next.rawValue, (live.stack.ids.map(\.rawValue).max() ?? 0) + 1)

        // Applying the restored parameters and bindings reproduces the live values.
        let fresh = ParameterStore(registry: store.registry)
        let report = fresh.restore(loaded.state.parameters)
        XCTAssertEqual(report.orphaned, [])
        XCTAssertEqual(report.rejected, [])
        XCTAssertEqual(fresh.snapshot(), store.snapshot())
        let freshModulator = AudioFeatureModulator(registry: store.registry)
        for b in loaded.state.bindings { try freshModulator.bind(b) }
        XCTAssertEqual(freshModulator.bindings, modulator.bindings)
        XCTAssertEqual(loaded.state.expressions, live.expressions)

        // Capturing the restored state gives the same document again.
        XCTAssertEqual(try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Live"), document)
    }

    func testUnknownKindsStayInTheDocumentButNotInTheLiveStack() throws {
        let fixture = try SceneFixtures.allKinds()
        let loaded = try fixture.liveState(registry: try SceneFixtures.registry(), assets: FakeAvailability())
        XCTAssertEqual(loaded.state.stack.ids.map(\.rawValue), [1, 2, 9, 10, 11, 12, 13])
        XCTAssertEqual(loaded.warnings.map(\.code), [.unknownLayerKind])
        XCTAssertNil(loaded.state.contents[LayerInstanceID(rawValue: 40)])
        let photo = try XCTUnwrap(loaded.state.stack.entry(LayerInstanceID(rawValue: 9)))
        XCTAssertEqual(photo.settings.opacity, 0.5)
        XCTAssertEqual(photo.settings.transform, fixture.layers[2].composite.transform)
    }

    func testCaptureRefusesEntriesWithoutContentOfTheirKind() throws {
        var stack = LayerStack()
        let photo = try stack.add(LayerDescriptor(kind: .photo))
        XCTAssertThrowsError(try SceneDocument(capturing: SceneLiveState(stack: stack), id: SceneFixtures.sceneID, name: "x")) {
            XCTAssertEqual($0 as? SceneCaptureError, .missingContent(instance: photo.rawValue))
            XCTAssertEqual("\($0)", "Layer \(photo.rawValue) has no scene content.")
        }
        let wrong = SceneLiveState(stack: stack, contents: [photo: .video(asset: "a")])
        XCTAssertThrowsError(try SceneDocument(capturing: wrong, id: SceneFixtures.sceneID, name: "x")) {
            XCTAssertEqual($0 as? SceneCaptureError, .contentMismatch(instance: photo.rawValue, stackKind: "photo", contentKind: "video"))
        }
    }

    func testErrorsRefuseTheLiveStateWithEveryError() throws {
        var document = try SceneFixtures.allKinds()
        document.layers[1].instance = 1                   // duplicate of the camera
        document.parameters["not.registered"] = .continuous(1) // a warning only
        XCTAssertThrowsError(try document.liveState(registry: try SceneFixtures.registry())) {
            guard case let .invalid(issues)? = $0 as? SceneLoadError else { return XCTFail("\($0)") }
            XCTAssertEqual(issues.map(\.code), [.duplicateInstance])
            XCTAssertEqual("\($0)", "The scene cannot be opened (1 problem):\n- Layer 1 uses instance ID 1, already used by layer 0.")
        }
    }
}
