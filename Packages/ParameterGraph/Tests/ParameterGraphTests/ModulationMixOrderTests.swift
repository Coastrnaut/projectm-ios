// ModulationMixOrderTests.swift — MOD-011-T03, T04: the documented mix order (contract mix-order O1, roadmap
// acceptance "Order and clamping are documented and unit-tested"), single-binding bit identity with MOD-002,
// layer limits and determinism. Deterministic: frames and timestamps are passed in; no clock, no sleep.
import ParameterGraph
import XCTest

final class ModulationMixOrderTests: XCTestCase {
    static let opacity: ParameterID = "test.layer.opacity"   // continuous 0…1
    static let count: ParameterID = "test.layer.count"       // integer 0…10, step 2
    static let group = ParameterGroup(id: "test.layer", displayName: "Layer")

    static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: opacity, displayName: "Opacity", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.25), modulation: .continuousDefault),
            ParameterDescriptor(id: count, displayName: "Count", group: group, unit: .count,
                                kind: .integer(minimum: 0, maximum: 10, defaultValue: 4, step: 2), modulation: .continuousDefault),
        ])
    }

    /// The sources of the acceptance table, by name.
    enum Layer: String {
        /// audio band 0 → 0.2…0.8, replace
        case audioReplace
        /// LFO 0 → 0…0.3, add
        case lfoAdd
        /// audio band 1 → 0.5…1, multiply
        case audioMultiply
        /// audio band 2 → −0.6…0, add (pulls down)
        case audioSubtract

        func binding(_ target: ParameterID = ModulationMixOrderTests.opacity) -> AudioFeatureBinding {
            switch self {
            case .audioReplace: AudioFeatureBinding(source: .band(0), target: target, outputStart: 0.2, outputEnd: 0.8, mixMode: .replace)
            case .lfoAdd: AudioFeatureBinding(source: .lfo(0), target: target, outputStart: 0, outputEnd: 0.3, mixMode: .add)
            case .audioMultiply: AudioFeatureBinding(source: .band(1), target: target, outputStart: 0.5, outputEnd: 1, mixMode: .multiply)
            case .audioSubtract: AudioFeatureBinding(source: .band(2), target: target, outputStart: -0.6, outputEnd: 0, mixMode: .add)
            }
        }
    }

    struct Row {
        let name: String
        let manual: Double
        let layers: [Layer]
        /// bands 0, 1, 2 and LFO 0
        let sources: (Float, Float, Float, Double)
        let expected: Double
    }

    static func advance(_ modulator: AudioFeatureModulator, bands: [Float], lfo: Double, at time: UInt64) {
        let lfos: [Double] = [lfo]
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            lfos.withUnsafeBufferPointer { (l: UnsafeBufferPointer<Double>) -> Void in
                modulator.advance(frame: AudioFeatureFrame(bands: b, lfos: l), timeNanoseconds: time)
            }
        }
    }

    // MOD-011-T03: the acceptance table. Mapped values at the table's sources: replace 0.5 (band 0 = 0.5),
    // add 0.15 (LFO 0.5) or 0.3 (LFO 1), multiply 0.75 (band 1 = 0.5) or 0.5 (band 1 = 0), subtract −0.6 (band 2 = 0).
    func testDocumentedOrderTable() throws {
        let rows: [Row] = [
            Row(name: "manual only", manual: 0.4, layers: [], sources: (0.5, 0.5, 0, 0.5), expected: 0.4),
            Row(name: "manual + audio replace", manual: 0.4, layers: [.audioReplace], sources: (0.5, 0.5, 0, 0.5), expected: 0.5),
            // 0.5 → 0.5 + 0.15 = 0.65 → 0.65 × 0.75 = 0.4875
            Row(name: "replace, add, multiply", manual: 0.4, layers: [.audioReplace, .lfoAdd, .audioMultiply],
                sources: (0.5, 0.5, 0, 0.5), expected: 0.4875),
            // 0.4 × 0.75 = 0.3 → 0.45 → replace discards both: 0.5
            Row(name: "multiply, add, replace", manual: 0.4, layers: [.audioMultiply, .lfoAdd, .audioReplace],
                sources: (0.5, 0.5, 0, 0.5), expected: 0.5),
            // the two orders of add and multiply differ: 0.3 + 0.15 = 0.45 vs (0.4 + 0.15) × 0.75 = 0.4125
            Row(name: "multiply then add", manual: 0.4, layers: [.audioMultiply, .lfoAdd], sources: (0.5, 0.5, 0, 0.5), expected: 0.45),
            Row(name: "add then multiply", manual: 0.4, layers: [.lfoAdd, .audioMultiply], sources: (0.5, 0.5, 0, 0.5), expected: 0.4125),
            // upper bound: 0.9 + 0.3 = 1.2 → clamped 1 → × 0.5 = 0.5 (clamping only at the end would give 0.6)
            Row(name: "clamp at maximum between steps", manual: 0.9, layers: [.lfoAdd, .audioMultiply],
                sources: (0, 0, 0, 1), expected: 0.5),
            // lower bound: 0.2 − 0.6 = −0.4 → clamped 0 → + 0.15 = 0.15 (clamping only at the end would give 0)
            Row(name: "clamp at minimum between steps", manual: 0.2, layers: [.audioSubtract, .lfoAdd],
                sources: (0, 0, 0, 0.5), expected: 0.15),
            // a manual value outside the range is clamped by the first step
            Row(name: "out-of-range manual, multiply", manual: 1.6, layers: [.audioMultiply], sources: (0, 0.5, 0, 0), expected: 1),
        ]
        let registry = try Self.registry()
        for row in rows {
            let modulator = AudioFeatureModulator(registry: registry)
            for layer in row.layers { try modulator.addLayer(layer.binding()) }
            Self.advance(modulator, bands: [row.sources.0, row.sources.1, row.sources.2], lfo: row.sources.3, at: 1_000)
            let value: Double = modulator.value(for: Self.opacity, manual: row.manual)
            XCTAssertEqual(value, row.expected, accuracy: 1e-12, row.name)
            XCTAssertEqual(modulator.layerCount(for: Self.opacity), row.layers.count, row.name)
        }
    }

    // Integer parameters: intermediate values are clamped, not rounded; rounding and the step snap happen once.
    func testIntegerRoundsOnceAtTheEnd() throws {
        let registry = try Self.registry()
        let modulator = AudioFeatureModulator(registry: registry)
        // Two add layers of 0.4 each (band 0 = 0.4 over 0…1): 4 + 0.4 + 0.4 = 4.8 → 5 → step 2 → 6.
        // Rounding each step would give 4 + 0 + 0 = 4.
        for _ in 0..<2 {
            try modulator.addLayer(AudioFeatureBinding(source: .band(0), target: Self.count, outputStart: 0, outputEnd: 1, mixMode: .add))
        }
        Self.advance(modulator, bands: [0.4], lfo: 0, at: 1_000)
        XCTAssertEqual(modulator.value(for: Self.count, manual: ParameterValue.integer(4)), .integer(6))
        // Upper clamp between steps on an integer: 9 + 4 = 13 → 10 → × 0.5 = 5 → 5 → step 2 → 6.
        let clamped = AudioFeatureModulator(registry: registry)
        try clamped.addLayer(AudioFeatureBinding(source: .band(0), target: Self.count, outputStart: 0, outputEnd: 10, mixMode: .add))
        try clamped.addLayer(AudioFeatureBinding(source: .band(1), target: Self.count, outputStart: 0, outputEnd: 1, mixMode: .multiply))
        Self.advance(clamped, bands: [0.4, 0.5], lfo: 0, at: 1_000)
        XCTAssertEqual(clamped.value(for: Self.count, manual: ParameterValue.integer(9)), .integer(6))
    }

    func testPureFoldMatchesTheContract() {
        XCTAssertEqual(ModulationMixOrder.fold(base: 0.4, layers: [(0.5, .replace), (0.15, .add), (0.75, .multiply)],
                                               minimum: 0, maximum: 1), 0.4875, accuracy: 1e-12)
        XCTAssertEqual(ModulationMixOrder.fold(base: 0.9, layers: [(0.3, .add), (0.5, .multiply)], minimum: 0, maximum: 1), 0.5)
        XCTAssertEqual(ModulationMixOrder.fold(base: 1.5, layers: [], minimum: 0, maximum: 1), 1.5, "no layers: base unchanged")
        XCTAssertEqual(ModulationMixOrder.step(0.3, mapped: .infinity, mode: .multiply, minimum: 0, maximum: 1), 0.3,
                       "a non-finite result keeps the running value")
        XCTAssertEqual(ModulationMixOrder.step(0.3, mapped: .nan, mode: .replace, minimum: 0, maximum: 1), 0.3)
    }

    // Layer semantics: order, limits, bind replaces all layers in place, unbind removes all.
    func testLayerLimitsBindAndUnbind() throws {
        let registry = try Self.registry()
        let modulator = AudioFeatureModulator(registry: registry)
        try modulator.bind(AudioFeatureBinding(source: .band(0), target: Self.count, outputStart: 0, outputEnd: 10))
        for _ in 0..<AudioFeatureModulator.maximumBindingsPerTarget {
            try modulator.addLayer(Layer.lfoAdd.binding())
        }
        XCTAssertEqual(modulator.layerCount(for: Self.opacity), 4)
        XCTAssertThrowsError(try modulator.addLayer(Layer.audioMultiply.binding())) { (error: Error) -> Void in
            XCTAssertEqual(error as? AudioFeatureBindingError, .tooManyLayers(Self.opacity, limit: 4))
        }
        XCTAssertEqual(modulator.bindings.count, 5, "a refused layer changes nothing")
        // bind (MOD-002) replaces every layer with one, in the first one's place.
        try modulator.bind(Layer.audioReplace.binding())
        XCTAssertEqual(modulator.bindings.map(\.target), [Self.count, Self.opacity])
        XCTAssertEqual(modulator.bindings(for: Self.opacity), [Layer.audioReplace.binding()])
        try modulator.addLayer(Layer.audioMultiply.binding())
        try modulator.setEnvelope(AudioFeatureEnvelope(attackSeconds: 1, releaseSeconds: 2), for: Self.opacity, layer: 1)
        XCTAssertEqual(modulator.bindings(for: Self.opacity)[1].envelope.releaseSeconds, 2)
        XCTAssertEqual(modulator.bindings(for: Self.opacity)[0].envelope, .none)
        XCTAssertThrowsError(try modulator.setEnvelope(.none, for: Self.opacity, layer: 2))
        XCTAssertNotNil(modulator.signal(for: Self.opacity, layer: 1))
        XCTAssertNil(modulator.signal(for: Self.opacity, layer: 2))
        XCTAssertTrue(modulator.unbind(Self.opacity))
        XCTAssertEqual(modulator.layerCount(for: Self.opacity), 0)
        XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.3), 0.3, "unbinding returns to the base at once")
        // The 32-binding total still holds across layers.
        let full = AudioFeatureModulator(registry: registry)
        for _ in 0..<4 { try full.addLayer(Layer.lfoAdd.binding()) }
        XCTAssertThrowsError(try full.addLayer(Layer.lfoAdd.binding()))
        XCTAssertEqual(AudioFeatureModulator.maximumBindings, 32)
    }

    // MOD-011-T04: one binding is bit-identical to MOD-002's formula over a grid (MOD-011-S2).
    func testSingleBindingIsBitIdenticalToMOD002() throws {
        let registry = try Self.registry()
        let manuals: [Double] = [-0.5, 0, 0.25, 0.7, 1, 1.5]
        let levels: [Float] = [0, 0.1, 0.5, 0.9, 1]
        let curves: [MappingCurve] = [.linear, .easeIn(exponent: 2), .logarithmic(strength: 9)]
        let ranges: [ModulationMixMode: [(Double, Double)]] = [
            .replace: [(0, 1), (0.9, 0.1)], .add: [(-1, 1), (0.3, -0.2)], .multiply: [(0, 1), (1, 0.25)],
        ]
        var compared = 0
        for mode in ModulationMixMode.allCases {
            for range in ranges[mode] ?? [] {
                for curve in curves {
                    let binding = AudioFeatureBinding(source: .band(0), target: Self.opacity, outputStart: range.0,
                                                      outputEnd: range.1, mixMode: mode, curve: curve)
                    let modulator = AudioFeatureModulator(registry: registry)
                    try modulator.bind(binding)
                    for level in levels {
                        Self.advance(modulator, bands: [level], lfo: 0, at: 1_000)
                        for manual in manuals {
                            let value: Double = modulator.value(for: Self.opacity, manual: manual)
                            let reference: Double = Self.mod002(binding, level: level, manual: manual, minimum: 0, maximum: 1)
                            XCTAssertEqual(value.bitPattern, reference.bitPattern, "\(mode) \(range) \(curve) \(level) \(manual)")
                            compared += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(compared, 540)
        // Integers: the same formula, then MOD-002's rounding and step snap.
        for mode in ModulationMixMode.allCases {
            let end: Double = mode == .multiply ? 1 : 10
            let binding = AudioFeatureBinding(source: .band(0), target: Self.count, outputStart: 0, outputEnd: end, mixMode: mode)
            let modulator = AudioFeatureModulator(registry: registry)
            try modulator.bind(binding)
            for level in levels {
                Self.advance(modulator, bands: [level], lfo: 0, at: 1_000)
                for manual in [0, 3, 4, 10] {
                    let raw: Double = Self.mod002(binding, level: level, manual: Double(manual), minimum: 0, maximum: 10)
                    let rounded = Int(raw.rounded(.toNearestOrAwayFromZero))
                    // MOD-001's step snap for 0…10 step 2: nearest step from the minimum, ties toward the maximum.
                    let clamped: Int = min(max(rounded, 0), 10)
                    let snapped: Int = min((clamped + 1) / 2, 5) * 2
                    XCTAssertEqual(modulator.value(for: Self.count, manual: ParameterValue.integer(manual)), .integer(snapped),
                                   "\(mode) \(level) \(manual)")
                }
            }
        }
    }

    /// MOD-002's `effective` as it was before MOD-011 (commit 3b2d21b8), with no envelope.
    static func mod002(_ binding: AudioFeatureBinding, level: Float, manual: Double, minimum: Double, maximum: Double) -> Double {
        let s: Double = binding.mapping.position(of: Double(level))
        let shaped: Double = binding.curve.apply(s)
        let mapped: Double = binding.mapping.interpolate(shaped)
        let combined: Double = switch binding.mixMode {
        case .replace: mapped
        case .add: manual + mapped
        case .multiply: manual * mapped
        }
        return min(max(combined.isFinite ? combined : manual, minimum), maximum)
    }

    // MOD-011-S3: the same frames give the same bits in two fresh modulators (envelopes included).
    func testDeterminism() throws {
        let registry = try Self.registry()
        func run() throws -> [UInt64] {
            let modulator = AudioFeatureModulator(registry: registry)
            var smoothed = Layer.audioReplace.binding()
            smoothed.envelope = AudioFeatureEnvelope(attackSeconds: 0.05, releaseSeconds: 0.3)
            try modulator.addLayer(smoothed)
            try modulator.addLayer(Layer.lfoAdd.binding())
            try modulator.addLayer(Layer.audioMultiply.binding())
            var out: [UInt64] = []
            var time: UInt64 = 1_000
            for k in 0..<120 {
                let phase = Float(k % 17) / 16
                Self.advance(modulator, bands: [phase, 1 - phase, 0], lfo: Double(k % 9) / 8, at: time)
                time += 16_666_667
                out.append(modulator.value(for: Self.opacity, manual: 0.35).bitPattern)
            }
            return out
        }
        XCTAssertEqual(try run(), try run())
    }
}
