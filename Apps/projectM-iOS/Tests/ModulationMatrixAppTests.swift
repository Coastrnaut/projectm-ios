// ModulationMatrixAppTests.swift — MOD-012-T07: in the app's native spectrum host, disabling one layer of the glow
// intensity affects only that destination (MOD-012-S1); matrix edits are one SCN-010 undo step each and undo restores
// the list (S4); capture writes `enabled: false` (S3); the inspector marks a layer "(off)" (R7). Deterministic:
// features and frame times are passed in. The host test needs a Metal device and skips without one.
import Metal
import ParameterGraph
import SceneFormat
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ModulationMatrixAppTests: XCTestCase {
    static let intensity: ParameterID = VisualParameterIDs.bloomIntensity
    static let radius: ParameterID = VisualParameterIDs.bloomRadius
    /// A: kick → 0.2…0.9 replace; B: LFO 1 → ×0.25…×1 multiply (no oscillator: LFO reads 0 → ×0.25); C: band 3 → radius.
    static let routeA = AudioFeatureBinding(source: .kick, target: intensity, outputStart: 0.2, outputEnd: 0.9, mixMode: .replace)
    static let routeB = AudioFeatureBinding(source: .lfo(0), target: intensity, outputStart: 0.25, outputEnd: 1, mixMode: .multiply)
    static let routeC = AudioFeatureBinding(source: .band(3), target: radius, outputStart: 0.01, outputEnd: 0.05, mixMode: .replace)

    private func apply(_ host: NativeSpectrumHost, at time: UInt64) {
        let bands: [Float] = [0, 0, 0, 0.5]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            host.applyModulation(bands: buffer, kick: 1, timeNanoseconds: time)
        }
    }

    func testDisablingOneLayerAffectsOnlyItsDestinationInTheHost() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.1))
        for route in [Self.routeA, Self.routeC, Self.routeB] { try host.addLayer(route) }
        apply(host, at: 1_000_000)
        XCTAssertEqual(host.effectiveGlow.intensity, 0.225, accuracy: 1e-6, "0.9 × 0.25: both layers")
        let radiusBefore: Double? = host.modulatorValue(for: Self.radius, manual: 0.02)
        let signalA: Double? = host.layerSignal(for: Self.intensity, layer: 0)

        try host.setLayerEnabled(false, for: Self.intensity, layer: 1)
        XCTAssertEqual(host.effectiveGlow.intensity, 0.9, accuracy: 1e-6, "A alone, at once")
        XCTAssertEqual(host.modulatorValue(for: Self.radius, manual: 0.02)?.bitPattern, radiusBefore?.bitPattern, "radius untouched")
        XCTAssertEqual(host.layerSignal(for: Self.intensity, layer: 0), signalA, "A's signal untouched")
        apply(host, at: 2_000_000)
        XCTAssertEqual(host.effectiveGlow.intensity, 0.9, accuracy: 1e-6)
        try host.setLayerEnabled(true, for: Self.intensity, layer: 1)
        XCTAssertEqual(host.effectiveGlow.intensity, 0.225, accuracy: 1e-6, "re-enabled: the two-layer fold")
        try host.moveLayer(of: Self.intensity, from: 1, to: 0)
        XCTAssertEqual(host.effectiveGlow.intensity, 0.9, accuracy: 1e-6, "multiply first, then replace wins")
    }

    /// A fake world: the live list, the matrix, and the history over SceneInputs carrying the matrix's routes.
    private final class World {
        var live: [AudioFeatureBinding]
        init(_ live: [AudioFeatureBinding]) { self.live = live }
    }

    private func make(_ world: World) -> (ModulationMatrixCoordinator, SceneHistoryCoordinator) {
        let matrix = ModulationMatrixCoordinator()
        let history = SceneHistoryCoordinator()
        matrix.live = { () -> [AudioFeatureBinding] in world.live }
        matrix.store = { (edit: ModulationRouteEdit) -> Bool in
            guard let next = edit.applied(to: world.live) else { return false }
            world.live = next
            return true
        }
        matrix.didEdit = { () -> Void in history.endCoalescing() }
        matrix.refresh()
        history.inputs = { () -> SceneInputs in
            var inputs = SceneAutosaveFixtures.inputs(visual: .circularSpectrum)
            inputs.bindings = matrix.routes
            return inputs
        }
        history.carry = { () -> SceneAutosaveCarry in SceneAutosaveFixtures.carry }
        history.apply = { (inputs: SceneInputs) -> Void in matrix.restore(inputs.bindings) }
        history.start(observing: false)
        return (matrix, history)
    }

    func testEachEditIsOneUndoStepAndUndoRestoresTheList() {
        let world = World([Self.routeA, Self.routeC, Self.routeB])
        let (matrix, history) = make(world)
        let original: [AudioFeatureBinding] = world.live
        XCTAssertEqual(matrix.groups.map(\.target), [Self.intensity, Self.radius])
        XCTAssertEqual(matrix.countText, "3 routes")

        matrix.setEnabled(false, target: Self.intensity, layer: 1)
        XCTAssertEqual(world.live.map(\.isEnabled), [true, true, false])
        XCTAssertEqual(history.undoLabel, "Turn Off LFO 1 → Glow Intensity")
        matrix.move(target: Self.intensity, from: 1, to: 0)
        XCTAssertEqual(world.live.map(\.source), [.lfo(0), .band(3), .kick], "C keeps its position")
        XCTAssertEqual(history.undoLabel, "Reorder Glow Intensity")

        history.undo()
        XCTAssertEqual(history.undoLabel, "Turn Off LFO 1 → Glow Intensity", "the move was its own step")
        XCTAssertEqual(world.live.map(\.source), [.kick, .band(3), .lfo(0)])
        history.undo()
        XCTAssertEqual(world.live, original, "both steps undone")
        XCTAssertEqual(matrix.routes, original)
        XCTAssertFalse(history.canUndo)
        history.redo()
        XCTAssertEqual(world.live.map(\.isEnabled), [true, true, false], "redo turns it off again")

        // A refused edit changes nothing and records nothing.
        matrix.move(target: Self.radius, from: 0, to: 1)
        XCTAssertEqual(history.undoLabel, "Turn Off LFO 1 → Glow Intensity")
    }

    func testCaptureWritesTheFlagAndTheInspectorMarksTheLayerOff() throws {
        var inputs = SceneAutosaveFixtures.inputs(visual: .circularSpectrum)
        var off = Self.routeB
        off.isEnabled = false
        inputs.bindings = [Self.routeA, off]
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: [Self.routeC]).document
        XCTAssertEqual(document.bindings.map(\.isEnabled), [true, false], "the matrix mirror wins over the live list")
        let descriptor = try XCTUnwrap(ParameterInspectorCatalog.descriptor(Self.intensity))
        let reading = try XCTUnwrap(ParameterModulationReader.reading(descriptor, manual: 0.1, bindings: [Self.routeA, off],
                                                                      external: nil, modulated: nil, rendered: nil))
        XCTAssertTrue(reading.sources[1].hasSuffix(" (off)"), reading.sources[1])
        XCTAssertFalse(reading.sources[0].hasSuffix(" (off)"))
    }
}
