// SceneAutosaveCaptureTests.swift — SCN-002-T08, T13: capture → save → load → restore round trip,
// layers per visual, settings applied, and content the app does not own kept (SCN-002-R1, R8, R9; S5).
import Compositor
import Foundation
import ParameterGraph
import SceneFormat
import TextLayer
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

final class SceneAutosaveCaptureTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures

    /// S5: capture → save → load gives the same document; the restored values are the captured ones;
    /// capturing again over the restored carry is byte-identical (a fixed point).
    func testRoundTripRestoresTheCapturedScene() throws {
        let folder = F.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let registry = try F.registry()
        var inputs = F.inputs(visual: .text, bars: 16, message: "Hello 👋🏽 مرحبا")
        inputs.glowEnabled = true
        inputs.glowIntensity = 0.8
        inputs.orientation = .horizontal
        let binding = AudioFeatureBinding(source: .bandMean, target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1)
        let captured = SceneAutosaveCapture.document(inputs, carry: F.carry, liveBindings: [binding]).document
        let store = SceneAutosaveStore(directory: folder)
        try store.save(captured.encoded())

        let load = SceneAutosaveStore(directory: folder).load(registry: registry, assets: nil)
        let document = try XCTUnwrap(load.document)
        let live = try XCTUnwrap(load.result).state
        XCTAssertEqual(document, captured)
        XCTAssertEqual(live.stack.entries.map(\.descriptor.kind.identifier), ["spectrum.circular", "text"])
        let values = SceneAutosaveCapture.restoredValues(document, live: live, registry: registry)
        XCTAssertEqual(values.parameters, SceneAutosaveCapture.parameterValues(inputs))
        XCTAssertEqual(values.text, inputs.text)
        XCTAssertEqual(values.bindings, [binding])

        let carry = SceneAutosaveCarry(document: document, live: live)
        XCTAssertEqual(SceneAutosaveCapture.document(inputs, carry: carry, liveBindings: nil).document.encoded(), captured.encoded())
    }

    func testLayersPerVisual() {
        func kinds(_ inputs: SceneInputs) -> [String] {
            SceneAutosaveCapture.document(inputs, carry: F.carry, liveBindings: nil).document.layers.map(\.kind)
        }
        XCTAssertEqual(kinds(F.inputs(visual: .projectM)), [])
        XCTAssertEqual(kinds(F.inputs(visual: .circularSpectrum)), ["spectrum.circular"])
        XCTAssertEqual(kinds(F.inputs(visual: .linearSpectrum)), ["spectrum.linear"])
        XCTAssertEqual(kinds(F.inputs(visual: .photo)), ["spectrum.circular"], "no stored photo: no photo layer")
        var photo = F.inputs(visual: .photo)
        photo.photoID = UUID()
        XCTAssertEqual(kinds(photo), ["photo", "spectrum.circular"])
        let document = SceneAutosaveCapture.document(photo, carry: F.carry, liveBindings: nil).document
        XCTAssertEqual(document.assets["photo"], .photo(storeID: photo.photoID!.uuidString))
        var video = F.inputs(visual: .video)
        video.videoID = UUID()
        XCTAssertEqual(kinds(video), ["video", "spectrum.circular"])
        XCTAssertEqual(kinds(F.inputs(visual: .text)), ["spectrum.circular", "text"])
        // CAM-001-R11: Camera is never recorded.
        XCTAssertEqual(SceneAutosaveCapture.recordedVisual(.camera, beforeCamera: .text), .text)
        XCTAssertEqual(SceneAutosaveCapture.recordedVisual(.camera, beforeCamera: .camera), .projectM)
        XCTAssertEqual(SceneAutosaveCapture.recordedVisual(.photo, beforeCamera: .text), .photo)
    }

    /// R9: unknown layers (at their index), document fields, unknown assets, orphaned bindings,
    /// matched layers' composites, foreign parameter values, the scene ID and name survive a capture.
    func testContentTheAppDoesNotOwnIsKept() throws {
        let registry = try F.registry()
        let orphan = SceneBinding(sourceID: "audio.future.feature", target: VisualParameterIDs.bloomRadius,
                                  mapping: LinearMapping(outputStart: 0, outputEnd: 1))
        let unknownLayer = SceneLayer(instance: 7, content: .unknown(kind: "future.layer"), extra: ["shape": .string("star")])
        let spectrum = SceneLayer(instance: 3, content: .circularSpectrum, composite: SceneComposite(opacity: 0.5))
        let original = SceneDocument(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "My Look",
                                     layers: [unknownLayer, spectrum],
                                     parameters: [ParameterID("future.thing.size"): .continuous(3)],
                                     bindings: [orphan], assets: ["blob": SceneAsset(.unknown(type: "future"))],
                                     extra: ["futureField": .string("kept")])
        let decoded = try SceneDocument.decode(original.encoded()).document
        let live = try decoded.liveState(registry: registry).state
        let carry = SceneAutosaveCarry(document: decoded, live: live)

        let captured = SceneAutosaveCapture.document(F.inputs(visual: .circularSpectrum, bars: 32), carry: carry, liveBindings: nil)
        let document = captured.document
        XCTAssertEqual(captured.events, [])
        XCTAssertEqual(document.id, original.id)
        XCTAssertEqual(document.name, "My Look")
        XCTAssertEqual(document.layers.map(\.kind), ["future.layer", "spectrum.circular"], "the unknown layer keeps its place")
        XCTAssertEqual(document.layers[0], unknownLayer)
        XCTAssertEqual(document.layers[1].instance, 3, "the matched layer keeps its instance")
        XCTAssertEqual(document.layers[1].composite.opacity, 0.5, "and its composite")
        XCTAssertEqual(document.extra["futureField"], .string("kept"))
        XCTAssertEqual(document.assets["blob"], SceneAsset(.unknown(type: "future")))
        XCTAssertEqual(document.parameters[ParameterID("future.thing.size")], .continuous(3))
        XCTAssertEqual(F.bars(document), "32")
        XCTAssertEqual(document.bindings, [orphan], "the orphaned binding is preserved")
        XCTAssertTrue(document.validate(registry: registry).filter(\.isError).isEmpty)
    }

    /// At most 8 layers: carried layers beyond the limit are dropped with an event.
    func testCarriedLayersBeyondTheLimitAreDropped() {
        var carry = F.carry
        carry.layers = (1...8).map { (i: Int) -> SceneLayer in SceneLayer(instance: UInt64(i), content: .unknown(kind: "future.\(i)")) }
        var inputs = F.inputs(visual: .photo)
        inputs.photoID = UUID()
        let captured = SceneAutosaveCapture.document(inputs, carry: carry, liveBindings: nil)
        XCTAssertEqual(captured.document.layers.count, SceneLimits.maximumLayers)
        XCTAssertEqual(captured.events, [.droppedLayers(2)])
        XCTAssertEqual(Set(captured.document.layers.map(\.instance)).count, SceneLimits.maximumLayers, "instances stay unique")
    }

    /// Restored values reach the settings through their own setters.
    @MainActor
    func testRestoredValuesApplyToTheSettings() throws {
        let suite = "SCN002-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        var inputs = F.inputs(bars: 128)
        inputs.orientation = .horizontal
        inputs.spacing = 0.5
        inputs.glowEnabled = true
        inputs.glowThreshold = 0.4
        let values = SceneRestoredValues(parameters: SceneAutosaveCapture.parameterValues(inputs), text: nil, bindings: [])
        SceneAutosaveCapture.apply(values, to: settings)
        XCTAssertEqual(settings.circularSpectrumBars, 128)
        XCTAssertEqual(settings.linearSpectrumOrientation, .horizontal)
        XCTAssertEqual(settings.linearSpectrumSpacing, 0.5)
        XCTAssertTrue(settings.glowEnabled)
        XCTAssertEqual(settings.glowThreshold, 0.4, accuracy: 1e-9)
        XCTAssertEqual(defaults.integer(forKey: AppSettings.circularSpectrumBarsKey), 128, "written through like a user's change")
    }
}
