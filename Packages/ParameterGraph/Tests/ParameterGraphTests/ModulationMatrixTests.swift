// ModulationMatrixTests.swift — MOD-012-T02: the roadmap acceptance "Disabling one row affects only its destination
// route" (contract modulation-matrix M1), reordering (M2), and the plain-list edits. Deterministic: frames and
// timestamps are passed in; no clock, no sleep.
import ParameterGraph
import XCTest

final class ModulationMatrixTests: XCTestCase {
    static let intensity: ParameterID = "test.glow.intensity"   // continuous 0…1
    static let radius: ParameterID = "test.glow.radius"         // continuous 0…0.1
    static let count: ParameterID = "test.glow.count"           // integer 0…10, step 2
    static let group = ParameterGroup(id: "test.glow", displayName: "Glow")

    static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: intensity, displayName: "Intensity", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault),
            ParameterDescriptor(id: radius, displayName: "Radius", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 0.1, defaultValue: 0.02), modulation: .continuousDefault),
            ParameterDescriptor(id: count, displayName: "Count", group: group, unit: .count,
                                kind: .integer(minimum: 0, maximum: 10, defaultValue: 4, step: 2), modulation: .continuousDefault),
        ])
    }

    /// A: kick → intensity 0.2…0.9 (replace), with an envelope so its signal has state worth preserving.
    static let routeA = AudioFeatureBinding(source: .kick, target: intensity, outputStart: 0.2, outputEnd: 0.9, mixMode: .replace,
                                            envelope: AudioFeatureEnvelope(attackSeconds: 0.05, releaseSeconds: 0.2))
    /// B: LFO 1 → intensity ×0.25…×1 (multiply), the second layer.
    static let routeB = AudioFeatureBinding(source: .lfo(0), target: intensity, outputStart: 0.25, outputEnd: 1, mixMode: .multiply)
    /// C: band 3 → radius 0.01…0.08 (replace).
    static let routeC = AudioFeatureBinding(source: .band(3), target: radius, outputStart: 0.01, outputEnd: 0.08, mixMode: .replace)

    /// Kick, band 3 and LFO 1 values per frame (varying, so signals move).
    static func advance(_ m: AudioFeatureModulator, frame n: Int) {
        let bands: [Float] = [0, 0, 0, Float(n % 7) / 7]
        let lfos: [Double] = [Double(n % 5) / 4]
        let kick: Float = Float(n % 3) / 2
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            lfos.withUnsafeBufferPointer { (l: UnsafeBufferPointer<Double>) -> Void in
                m.advance(frame: AudioFeatureFrame(bands: b, kick: kick, lfos: l), timeNanoseconds: UInt64(n) * 16_666_667)
            }
        }
    }

    private func makeABC() throws -> AudioFeatureModulator {
        let m = AudioFeatureModulator(registry: try Self.registry())
        try m.addLayer(Self.routeA)
        try m.addLayer(Self.routeC)   // C sits between A and B in the list: other targets keep their place
        try m.addLayer(Self.routeB)
        return m
    }

    /// The documented fold of only the given layers, from their current signals (contract M1 via ModulationMixOrder).
    private func fold(_ m: AudioFeatureModulator, manual: Double, layers: [(Int, AudioFeatureBinding)]) -> Double {
        var running: Double = manual
        for (layer, b) in layers {
            let s: Double = m.signal(for: Self.intensity, layer: layer) ?? .nan
            let mapped: Double = b.mapping.interpolate(b.curve.apply(s))
            running = ModulationMixOrder.step(running, mapped: mapped, mode: b.mixMode, minimum: 0, maximum: 1)
        }
        return running
    }

    // Roadmap acceptance (MOD-012-S1).
    func testDisablingOneRowAffectsOnlyItsDestinationRoute() throws {
        let m = try makeABC()
        let manual = 0.4
        let radiusManual = 0.03
        for n in 1...7 { Self.advance(m, frame: n) }
        let twoLayer: Double = m.value(for: Self.intensity, manual: manual)
        XCTAssertEqual(twoLayer, fold(m, manual: manual, layers: [(0, Self.routeA), (1, Self.routeB)]), "both layers fold")
        let radiusBefore: Double = m.value(for: Self.radius, manual: radiusManual)
        let signalA: Double = try XCTUnwrap(m.signal(for: Self.intensity, layer: 0))

        try m.setEnabled(false, for: Self.intensity, layer: 1)
        let aOnly: Double = m.value(for: Self.intensity, manual: manual)
        let reference = AudioFeatureModulator(registry: try Self.registry())   // A alone, same frames
        try reference.addLayer(Self.routeA)
        for n in 1...7 { Self.advance(reference, frame: n) }
        XCTAssertEqual(aOnly.bitPattern, reference.value(for: Self.intensity, manual: manual).bitPattern, "intensity == A only, exactly")
        XCTAssertNotEqual(aOnly, twoLayer, "the setup makes B matter")
        XCTAssertEqual(m.value(for: Self.radius, manual: radiusManual).bitPattern, radiusBefore.bitPattern, "radius bit-identical")
        XCTAssertEqual(m.signal(for: Self.intensity, layer: 0)?.bitPattern, signalA.bitPattern, "A's signal unchanged")
        XCTAssertEqual(m.layerCount(for: Self.intensity), 2, "the row is kept")
        XCTAssertFalse(m.bindings(for: Self.intensity)[1].isEnabled)

        // B keeps advancing while off; re-enabled, the two-layer fold of the current signals.
        let signalB: Double = try XCTUnwrap(m.signal(for: Self.intensity, layer: 1))
        Self.advance(m, frame: 8)
        Self.advance(reference, frame: 8)
        XCTAssertNotEqual(m.signal(for: Self.intensity, layer: 1), signalB, "a disabled layer keeps advancing")
        XCTAssertEqual(m.value(for: Self.intensity, manual: manual).bitPattern, reference.value(for: Self.intensity, manual: manual).bitPattern)
        try m.setEnabled(true, for: Self.intensity, layer: 1)
        XCTAssertEqual(m.value(for: Self.intensity, manual: manual),
                       fold(m, manual: manual, layers: [(0, Self.routeA), (1, Self.routeB)]), "re-enabled: the two-layer fold")
    }

    func testEveryLayerOffGivesTheBaseExactly() throws {
        let m = try makeABC()
        for n in 1...5 { Self.advance(m, frame: n) }
        try m.setEnabled(false, for: Self.intensity, layer: 0)
        try m.setEnabled(false, for: Self.intensity, layer: 1)
        let manual = 0.123456789
        XCTAssertEqual(m.value(for: Self.intensity, manual: manual).bitPattern, manual.bitPattern)
        XCTAssertEqual(m.value(for: Self.intensity, manual: 1.7), 1.7, "not even clamped, as unbound")
        // Integer: base returned without a snap; one enabled layer snaps as before.
        try m.addLayer(AudioFeatureBinding(source: .kick, target: Self.count, outputStart: 6.4, outputEnd: 6.4, mixMode: .replace, isEnabled: false))
        XCTAssertEqual(m.value(for: Self.count, manual: 5), 5)
        try m.setEnabled(true, for: Self.count, layer: 0)
        XCTAssertEqual(m.value(for: Self.count, manual: 5), 6, "6.4 rounds to 6 (on the step) once at the end")
        XCTAssertThrowsError(try m.setEnabled(false, for: Self.intensity, layer: 2))
    }

    // MOD-012-S2: reordering changes the fold as documented; other targets keep their positions.
    func testReorderChangesTheFoldAsDocumented() throws {
        let m = AudioFeatureModulator(registry: try Self.registry())
        let add = AudioFeatureBinding(source: .band(0), target: Self.intensity, outputStart: 0.3, outputEnd: 0.3, mixMode: .add)
        let multiply = AudioFeatureBinding(source: .band(1), target: Self.intensity, outputStart: 0.5, outputEnd: 0.5, mixMode: .multiply)
        try m.addLayer(add)
        try m.addLayer(Self.routeC)
        try m.addLayer(multiply)
        XCTAssertEqual(m.value(for: Self.intensity, manual: 0.4), 0.35, accuracy: 1e-15, "(0.4 + 0.3) × 0.5")
        try m.moveLayer(of: Self.intensity, from: 1, to: 0)
        XCTAssertEqual(m.value(for: Self.intensity, manual: 0.4), 0.5, accuracy: 1e-15, "0.4 × 0.5 + 0.3")
        XCTAssertEqual(m.bindings.map(\.target), [Self.intensity, Self.radius, Self.intensity], "C keeps its list position")
        XCTAssertEqual(m.bindings(for: Self.intensity), [multiply, add])
        XCTAssertThrowsError(try m.moveLayer(of: Self.intensity, from: 0, to: 2), "out of range")
        XCTAssertThrowsError(try m.moveLayer(of: Self.radius, from: 0, to: 1), "a destination has only its own layers")
        XCTAssertEqual(m.bindings(for: Self.intensity), [multiply, add], "nothing changed")
    }

    func testMoveKeepsSignalsWithTheirBindings() throws {
        let m = try makeABC()
        for n in 1...6 { Self.advance(m, frame: n) }
        let a: Double? = m.signal(for: Self.intensity, layer: 0)
        let b: Double? = m.signal(for: Self.intensity, layer: 1)
        try m.moveLayer(of: Self.intensity, from: 0, to: 1)
        XCTAssertEqual(m.signal(for: Self.intensity, layer: 0), b)
        XCTAssertEqual(m.signal(for: Self.intensity, layer: 1), a)
    }

    func testListEditsMatchTheModulator() throws {
        let list: [AudioFeatureBinding] = [Self.routeA, Self.routeC, Self.routeB]
        let off = try XCTUnwrap(ModulationRouteList.settingEnabled(false, in: list, target: Self.intensity, layer: 1))
        XCTAssertEqual(off.map(\.isEnabled), [true, true, false])
        let moved = try XCTUnwrap(ModulationRouteList.moving(in: list, target: Self.intensity, from: 1, to: 0))
        XCTAssertEqual(moved, [Self.routeB, Self.routeC, Self.routeA])
        let m = try makeABC()
        try m.moveLayer(of: Self.intensity, from: 1, to: 0)
        XCTAssertEqual(m.bindings, moved)
        XCTAssertNil(ModulationRouteList.moving(in: list, target: Self.radius, from: 0, to: 1))
        XCTAssertNil(ModulationRouteList.settingEnabled(false, in: list, target: Self.count, layer: 0))
        let groups = ModulationRouteList.groups(list)
        XCTAssertEqual(groups.map(\.target), [Self.intensity, Self.radius], "first-appearance order")
        XCTAssertEqual(groups[0].layers, [Self.routeA, Self.routeB], "fold order")
    }

    func testReplaceBindingsIsAllOrNothing() throws {
        let m = try makeABC()
        let bad = AudioFeatureBinding(source: .kick, target: "test.unknown", outputStart: 0, outputEnd: 1)
        XCTAssertThrowsError(try m.replaceBindings([Self.routeC, bad]))
        XCTAssertEqual(m.bindings, [Self.routeA, Self.routeC, Self.routeB], "unchanged after a refusal")
        var offB = Self.routeB
        offB.isEnabled = false
        try m.replaceBindings([offB, Self.routeA])
        XCTAssertEqual(m.bindings, [offB, Self.routeA])
        XCTAssertEqual(m.value(for: Self.intensity, manual: 0.4), 0.2, accuracy: 1e-15, "only A applies (signal 0 → 0.2)")
    }
}
