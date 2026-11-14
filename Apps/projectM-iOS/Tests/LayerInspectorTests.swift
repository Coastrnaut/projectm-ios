// LayerInspectorTests.swift — CMP-015-T10, T12, T15, T17: the layer inspector's model, its undo through
// SCN-010, its saving through SCN-002, its help table and its transient solo/mute (CMP-015-S1, S3 to
// S5; contracts/layer-inspector.md L1 to L5). Plain values and a real SceneHistoryCoordinator over a
// fake world (`capture()` is called where the app's observation callback would run). No clock.
import Compositor
import Foundation
import SceneFormat
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class LayerInspectorTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures
    private typealias Seed = UITestLayerInspectorFixture

    /// The seeded three-layer Photo scene (contract L5).
    private static func seededInputs(_ composites: [String: SceneComposite] = Seed.composites) -> SceneInputs {
        var inputs = F.inputs(visual: .photo, bars: 32)
        inputs.photoID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")
        inputs.layerComposites = composites
        return inputs
    }

    private static var seededCarry: SceneAutosaveCarry {
        var carry = F.carry
        carry.layers = Seed.carriedLayers
        return carry
    }

    private static func document(_ inputs: SceneInputs) -> SceneDocument {
        SceneAutosaveCapture.document(inputs, carry: seededCarry, liveBindings: nil).document
    }

    /// The app's inputs and its inspector; the history applies states as AppCoordinator does.
    @MainActor
    private final class World {
        let layers = LayerInspectorCoordinator()
        var base = LayerInspectorTests.seededInputs([:])
        var inputs: SceneInputs {
            var current = base
            current.layerComposites = layers.composites
            return current
        }
    }

    private func make(_ world: World) -> SceneHistoryCoordinator {
        let history = SceneHistoryCoordinator()
        history.inputs = { () -> SceneInputs in world.inputs }
        history.carry = { () -> SceneAutosaveCarry in Self.seededCarry }
        history.apply = { (inputs: SceneInputs) -> Void in world.layers.restore(inputs.layerComposites ?? [:]) }
        world.layers.onEditEnded = { () -> Void in history.endCoalescing() }
        world.layers.restore(Seed.composites)
        history.start(observing: false)
        return history
    }

    private func text(_ parameter: LayerInspectorParameter, _ row: LayerInspectorRow) -> String {
        LayerCompositeEdit.text(parameter, of: row.composite)
    }

    // MARK: - US1: selecting each layer shows its values (CMP-015-S1)

    func testSelectingEachOfThreeLayersShowsThatLayersValues() {
        let rows = LayerInspectorScene.rows(document: Self.document(Self.seededInputs()), visual: .photo)
        XCTAssertEqual(rows.map(\.kind), ["material", "spectrum.circular", "photo"], "top first")
        XCTAssertEqual(rows.map(\.position), [3, 2, 1])
        XCTAssertEqual(rows.map(\.title), ["Material (plasma)", "Circular Spectrum", "Photo"])

        let material = rows[0], spectrum = rows[1], photo = rows[2]
        XCTAssertEqual([text(.opacity, material), text(.blendMode, material)], ["50%", "Add"])
        XCTAssertFalse(material.isEditable)
        XCTAssertEqual(material.readOnlyReason, LayerInspectorScene.notDrawnReason)

        XCTAssertEqual([text(.opacity, spectrum), text(.blendMode, spectrum), text(.positionX, spectrum), text(.scale, spectrum)],
                       ["60%", "Screen", "0.25", "1.00×"])
        XCTAssertTrue(spectrum.isEditable)
        XCTAssertEqual(spectrum.ownValues.map(\.title), ["Bars"])
        XCTAssertEqual(spectrum.ownValues.map(\.value), ["32"], "the layer's MOD-001 value, read-only")

        XCTAssertEqual([text(.opacity, photo), text(.blendMode, photo), text(.fitMode, photo), text(.maskShape, photo)],
                       ["80%", "Normal", "Fit", "None"])
        XCTAssertTrue(photo.isEditable)
        XCTAssertNil(photo.groupName)
        XCTAssertEqual(photo.accessibilityValue, "Layer 1 of 3, editable")

        // The detail of an editable row reads the inspector's live composite: the same values.
        let layers = LayerInspectorCoordinator()
        layers.restore(Seed.composites)
        for row in rows where row.isEditable { XCTAssertEqual(layers.composite(for: row.kind), row.composite, row.kind) }
    }

    func testNativeSpectrumAndProjectMScenesAreReadOnlyOrEmpty() {
        let circular = LayerInspectorScene.rows(document: F.document(bars: 64), visual: .circularSpectrum)
        XCTAssertEqual(circular.map(\.kind), ["spectrum.circular"])
        XCTAssertFalse(circular[0].isEditable)
        XCTAssertEqual(circular[0].readOnlyReason, LayerInspectorScene.directVisualReason)
        let linear = LayerInspectorScene.rows(document: F.document(bars: 64, visual: .linearSpectrum), visual: .linearSpectrum)
        XCTAssertEqual(linear[0].ownValues.map(\.title), ["Orientation", "Spacing (of the bar slot)"])
        XCTAssertTrue(LayerInspectorScene.rows(document: F.document(bars: 64, visual: .projectM), visual: .projectM).isEmpty)
    }

    // MARK: - US2: edits, undo and coalescing (CMP-015-S2, S3)

    func testOneSliderDragIsOneUndoStepAndUndoRestoresTheExactValue() {
        let world = World()
        let history = make(world)
        let before = world.layers.composite(for: "spectrum.circular")
        for value in [0.58, 0.55, 0.5, 0.47, 0.44, 0.4] {   // a drag: many values, one control
            world.layers.setValue(.opacity, value, kind: "spectrum.circular")
            history.capture()
        }
        world.layers.endEdit()   // the slider is released
        XCTAssertEqual(history.history?.undoSteps.count, 1, "one drag is one step")
        XCTAssertEqual(history.undoLabel, "Circular Spectrum Opacity 40%")

        history.undo()
        XCTAssertEqual(world.layers.composite(for: "spectrum.circular"), before, "the prior composite exactly")
        XCTAssertEqual(world.layers.composite(for: "spectrum.circular").opacity, 0.6)
        history.redo()
        XCTAssertEqual(world.layers.composite(for: "spectrum.circular").opacity, 0.4, accuracy: 1e-9)
    }

    func testOpacityAndTransformEditsOnLayerTwoUndoToThePriorValues() {
        let world = World()
        let history = make(world)
        let kind = "spectrum.circular"
        let before = world.layers.composite(for: kind)
        world.layers.setValue(.opacity, 0.3, kind: kind)
        history.capture()
        world.layers.endEdit()
        world.layers.setValue(.positionY, -0.4, kind: kind)
        history.capture()
        world.layers.setValue(.rotation, 30, kind: kind)
        history.capture()
        world.layers.endEdit()
        XCTAssertEqual(history.history?.undoSteps.count, 3, "three controls, three steps")
        XCTAssertEqual(LayerCompositeEdit.text(.rotation, of: world.layers.composite(for: kind)), "30°")

        history.undo()
        history.undo()
        history.undo()
        XCTAssertEqual(world.layers.composite(for: kind), before)
        XCTAssertEqual(Self.document(world.inputs).encoded(), Self.document(Self.seededInputs()).encoded(), "byte-equal scene")
    }

    func testPickersAndResetAreOneStepEach() {
        let world = World()
        let history = make(world)
        world.layers.setBlend("difference", kind: "photo")
        history.capture()
        world.layers.setMask("ellipse", kind: "photo")
        history.capture()
        world.layers.setFit(nil, kind: "photo")
        history.capture()
        XCTAssertEqual(history.history?.undoSteps.map(\.label), ["Photo Blend Mode Difference", "Photo Mask Ellipse", "Photo Fit Default"])
        world.layers.reset(kind: "photo")
        history.capture()
        XCTAssertEqual(history.undoLabel, "Reset Photo")
        XCTAssertEqual(world.layers.composites["photo"], nil, "the default composite is not stored")
        history.undo()
        XCTAssertEqual(LayerCompositeEdit.text(.maskShape, of: world.layers.composite(for: "photo")), "Ellipse")
    }

    func testAnAnchorDragOnTheDefaultFitIsOneStep() {
        let world = World()
        let history = make(world)
        world.layers.setFit(nil, kind: "photo")
        history.capture()
        world.layers.endEdit()
        for value in [0.4, 0.3, 0.2] {
            world.layers.setValue(.fitAnchorX, value, kind: "photo")
            history.capture()
        }
        world.layers.endEdit()
        XCTAssertEqual(history.history?.undoSteps.count, 2)
        XCTAssertEqual(history.undoLabel, "Photo Fit Anchor X 0.20")
    }

    // MARK: - Saving (CMP-015-R5, R9)

    func testCompositesAreSavedAndRestoredAndUnknownNamesSurvive() throws {
        let registry = try F.registry()
        var composites = Seed.composites
        var future = composites["photo"]!
        future.blendMode = "future.blend"
        composites["photo"] = future
        let document = Self.document(Self.seededInputs(composites))
        let decoded = try SceneDocument.decode(document.encoded()).document
        let live = try decoded.liveState(registry: registry).state
        let restored = SceneAutosaveCapture.restoredValues(decoded, live: live, registry: registry)
        XCTAssertEqual(restored.layerComposites, composites, "every drawn layer's composite comes back")

        let layers = LayerInspectorCoordinator()
        layers.restore(restored.layerComposites)
        XCTAssertEqual(LayerCompositeEdit.text(.blendMode, of: layers.composite(for: "photo")), "Other (future.blend)")
        layers.setValue(.opacity, 0.5, kind: "photo")   // an unrelated edit
        XCTAssertEqual(layers.composite(for: "photo").blendMode, "future.blend", "the unknown name is kept")
        XCTAssertEqual(LayerCompositeMapping.settings(layers.composite(for: "photo")).blendMode, .normal, "and drawn as normal")
    }

    func testAuthoritativeCompositesWriteTheDefaultForAMissingKind() {
        var inputs = Self.seededInputs([:])
        let document = Self.document(inputs)
        XCTAssertEqual(document.layers.first { $0.kind == "photo" }?.composite, SceneComposite(), "reset to default is saved")
        inputs.layerComposites = nil
        XCTAssertEqual(Self.document(inputs).layers.first { $0.kind == "photo" }?.composite, SceneComposite(),
                       "nil keeps the carried composite (here the default)")
        XCTAssertEqual(Self.document(inputs).layers.first { $0.kind == "material" }?.composite.opacity, 0.5, "carried layers keep theirs")
    }

    // MARK: - US3: help (CMP-015-S4)

    func testEveryParameterHasHelpFromTheOneTable() {
        XCTAssertEqual(Set(LayerInspectorHelp.entries.keys), Set(LayerInspectorParameter.allCases), "one entry per parameter")
        for parameter in LayerInspectorParameter.allCases {
            XCTAssertFalse(parameter.title.isEmpty, parameter.rawValue)
            XCTAssertGreaterThan(parameter.help.count, 20, "\(parameter.rawValue) has a real explanation")
        }
    }

    // MARK: - US4: solo and mute are transient (CMP-015-S5)

    func testSoloAndMuteNeverEnterTheHistoryOrTheSavedScene() {
        let world = World()
        let history = make(world)
        var spoken: [String] = []
        world.layers.announce = { (text: String) -> Void in spoken.append(text) }
        let bytes = Self.document(world.inputs).encoded()
        world.layers.toggleSolo(kind: "photo", title: "Photo")
        world.layers.toggleMute(kind: "spectrum.circular", title: "Circular Spectrum")
        history.capture()
        XCTAssertFalse(history.canUndo, "nothing to undo")
        XCTAssertEqual(Self.document(world.inputs).encoded(), bytes, "the saved scene is byte-identical")
        XCTAssertEqual(spoken, ["Photo soloed", "Circular Spectrum muted"])

        world.layers.visualShown(.photo)
        XCTAssertTrue(world.layers.isSoloed("photo"))
        world.layers.visualShown(.text)
        XCTAssertFalse(world.layers.isSoloed("photo"), "another visual clears solo")
        XCTAssertFalse(world.layers.isMuted("spectrum.circular"), "and mute")
    }
}
