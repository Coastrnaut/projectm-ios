// MIDICCScalingTests.swift — MIDI-004-T05, T07, T12: CC scaling with curve and inversion (specs/140-midi-004-cc-scaling,
// contract C1-C3). The acceptance: CC 0 and 127 map to the range's endpoints for every curve kind and range, and
// inverted mode swaps them. Representative cases (3 ranges × 7 curve kinds), no sweep; deterministic.
import Foundation
import ParameterGraph
import PerformanceControl
import XCTest

final class MIDICCScalingTests: XCTestCase {
    private static let group = ParameterGroup(id: "test.scale", displayName: "Scale")
    private static let unit: ParameterID = "test.scale.unit"          // 0…1
    private static let small: ParameterID = "test.scale.small"        // 0.005…0.06
    private static let signed: ParameterID = "test.scale.signed"      // −12…48
    private static let ids: [ParameterID] = [unit, small, signed]

    private static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: unit, displayName: "Unit", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault),
            ParameterDescriptor(id: small, displayName: "Small", group: group, unit: .fractionOfOutput,
                                kind: .continuous(minimum: 0.005, maximum: 0.06, defaultValue: 0.02), modulation: .continuousDefault),
            ParameterDescriptor(id: signed, displayName: "Signed", group: group, unit: .normalized,
                                kind: .continuous(minimum: -12, maximum: 48, defaultValue: 0), modulation: .continuousDefault),
        ])
    }

    /// One curve of every kind (MOD-004), all valid.
    private static let curves: [MappingCurve] = [
        .linear, .easeIn(exponent: 2), .easeOut(exponent: 3), .easeInOut(exponent: 2.5), .logarithmic(strength: 9),
        .exponential(strength: 4), .piecewise([CurvePoint(x: 0.25, y: 0.6), CurvePoint(x: 0.75, y: 0.7)]),
    ]

    private static func range(_ descriptor: ParameterDescriptor) -> (minimum: Double, maximum: Double) {
        guard case let .continuous(minimum, maximum, _, _, _) = descriptor.kind else { return (0, 0) }
        return (minimum, maximum)
    }

    private static func cc(_ value: UInt32, number: UInt8 = 7) -> MIDIEvent {
        MIDIEvent(kind: .controlChange, channel: 0, number: number, value: value)
    }

    private static func key(_ number: UInt8) -> MIDIControlKey {
        MIDIControlKey(kind: .controlChange, channel: 0, number: number)
    }

    // MARK: The acceptance (S1)

    func testCC0And127MapToTheEndpointsAndInvertedSwapsThemForEveryCurveAndRange() throws {
        let registry = try Self.registry()
        XCTAssertEqual(Self.curves.map(\.kindName).count, 7)
        for id in Self.ids {
            let descriptor = try XCTUnwrap(registry.descriptor(for: id))
            let (minimum, maximum) = Self.range(descriptor)
            for curve in Self.curves {
                XCTAssertTrue(curve.isValid, curve.textForm)
                for inverted in [false, true] {
                    var list = MIDIBindingList()
                    list.bind(Self.key(7), to: id)
                    list.setOptions(MIDIMappingOptions(curve: curve, inverted: inverted), for: id)
                    let low = MIDIBindingValues.values(for: [Self.cc(0)], bindings: list, registry: registry)[id]
                    let high = MIDIBindingValues.values(for: [Self.cc(127)], bindings: list, registry: registry)[id]
                    let label: String = id.rawValue + " " + curve.textForm + (inverted ? " inverted" : "")
                    XCTAssertEqual(low, inverted ? maximum : minimum, "CC 0, " + label)
                    XCTAssertEqual(high, inverted ? minimum : maximum, "CC 127, " + label)
                }
            }
        }
    }

    func testInvertedIsTheKnobRunningTheOtherWayAndValuesStayInRange() throws {
        let registry = try Self.registry()
        let descriptor = try XCTUnwrap(registry.descriptor(for: Self.signed))
        let (minimum, maximum) = Self.range(descriptor)
        let span: Double = maximum - minimum
        for curve in Self.curves {
            let normal = MIDIMappingOptions(curve: curve, inverted: false)
            let inverted = MIDIMappingOptions(curve: curve, inverted: true)
            for v in [1, 32, 63, 64, 96, 126] {
                let a = try XCTUnwrap(MIDIBindingValues.value(normalized: Double(v) / 127, for: descriptor, options: inverted))
                let b = try XCTUnwrap(MIDIBindingValues.value(normalized: Double(127 - v) / 127, for: descriptor, options: normal))
                XCTAssertEqual(a, b, accuracy: span * 1e-12, curve.textForm + " at " + String(v))
                XCTAssertTrue(a >= minimum && a <= maximum)
            }
        }
        let plain = MIDIMappingOptions.default
        XCTAssertEqual(MIDIBindingValues.value(normalized: -3, for: descriptor, options: plain), minimum)
        XCTAssertEqual(MIDIBindingValues.value(normalized: 9, for: descriptor, options: plain), maximum)
        XCTAssertNil(MIDIBindingValues.value(normalized: .nan, for: descriptor, options: plain))
    }

    // MARK: Midpoints follow the curve (S2)

    func testMidpointsMatchTheCurve() throws {
        let registry = try Self.registry()
        let descriptor = try XCTUnwrap(registry.descriptor(for: Self.signed))
        let (minimum, maximum) = Self.range(descriptor)
        let span: Double = maximum - minimum
        for v in [32.0, 64.0, 96.0] {
            let x: Double = v / 127
            let easeIn = try XCTUnwrap(MIDIBindingValues.value(normalized: x, for: descriptor,
                                                               options: MIDIMappingOptions(curve: .easeIn(exponent: 2))))
            XCTAssertEqual(easeIn, minimum + x * x * span, accuracy: 1e-9)
            let logShaped: Double = log1p(9 * x) / log1p(9)
            let logarithmic = try XCTUnwrap(MIDIBindingValues.value(normalized: x, for: descriptor,
                                                                    options: MIDIMappingOptions(curve: .logarithmic(strength: 9))))
            XCTAssertEqual(logarithmic, minimum + logShaped * span, accuracy: 1e-9)
            let invertedEaseIn = try XCTUnwrap(MIDIBindingValues.value(normalized: x, for: descriptor,
                                                                       options: MIDIMappingOptions(curve: .easeIn(exponent: 2), inverted: true)))
            XCTAssertEqual(invertedEaseIn, minimum + (1 - x) * (1 - x) * span, accuracy: 1e-9)
        }
        XCTAssertLessThan(try XCTUnwrap(MIDIBindingValues.value(normalized: 64.0 / 127, for: descriptor,
                                                                options: MIDIMappingOptions(curve: .easeIn(exponent: 2)))),
                          try XCTUnwrap(MIDIBindingValues.value(normalized: 64.0 / 127, for: descriptor)), "ease in starts slow")
    }

    func testPresetsAndSummaries() {
        XCTAssertEqual(MIDICurvePreset.allCases.map(\.title), ["Linear", "Ease in", "Ease out", "Logarithmic"])
        XCTAssertEqual(MIDICurvePreset.easeIn.curve, .easeIn(exponent: 2))
        XCTAssertEqual(MIDICurvePreset.easeOut.curve, .easeOut(exponent: 2))
        XCTAssertEqual(MIDICurvePreset.logarithmic.curve, .logarithmic(strength: 9))
        for preset in MIDICurvePreset.allCases {
            XCTAssertTrue(preset.curve.isValid)
            XCTAssertEqual(MIDICurvePreset.preset(for: preset.curve), preset)
        }
        XCTAssertNil(MIDICurvePreset.preset(for: .exponential(strength: 4)), "another curve is Custom")
        XCTAssertEqual(MIDIMappingOptions.default.summary, "Linear")
        XCTAssertEqual(MIDIMappingOptions(curve: .easeIn(exponent: 2), inverted: true).summary, "Ease in, inverted")
        XCTAssertEqual(MIDIMappingOptions(curve: .exponential(strength: 4)).summary, "Custom")
        XCTAssertEqual(MIDIMappingOptions(segments: ["curve=wobble:3"]).summary, "Linear (curve not readable)")
    }

    // MARK: Stored form (S3)

    func testMIDI003LinesReadAsDefaultAndWriteBackUnchanged() throws {
        let line: String = "cc:0:7=effect.bloom.intensity"
        let binding = try XCTUnwrap(MIDIControlBinding(storageLine: line))
        XCTAssertEqual(binding.options, .default)
        XCTAssertTrue(binding.options.isDefault)
        XCTAssertEqual(binding.storageLine, line)
        XCTAssertEqual(MIDIControlBinding(key: Self.key(7), target: "effect.bloom.intensity").storageLine, line)
    }

    func testOptionsRoundTripAndUnknownSegmentsAreKept() throws {
        let line: String = "cc:0:7=effect.bloom.intensity;curve=log:9.0;invert=1;min=0.2;pickup"
        let binding = try XCTUnwrap(MIDIControlBinding(storageLine: line))
        XCTAssertEqual(binding.target, "effect.bloom.intensity")
        XCTAssertEqual(binding.options.curve, .logarithmic(strength: 9))
        XCTAssertTrue(binding.options.inverted)
        XCTAssertEqual(binding.options.extraSegments, ["min=0.2", "pickup"])
        XCTAssertEqual(binding.storageLine, line)

        let reordered = try XCTUnwrap(MIDIControlBinding(storageLine: "cc:0:7=a;min=0.2;invert=1;curve=easeIn:2.0"))
        XCTAssertEqual(reordered.storageLine, "cc:0:7=a;curve=easeIn:2.0;invert=1;min=0.2", "known keys first, unknown in order")

        for preset in MIDICurvePreset.allCases {
            for inverted in [false, true] {
                let original = MIDIControlBinding(key: Self.key(9), target: "p", options: MIDIMappingOptions(curve: preset.curve, inverted: inverted))
                let restored = try XCTUnwrap(MIDIControlBinding(storageLine: original.storageLine))
                XCTAssertEqual(restored, original, original.storageLine)
                XCTAssertFalse(original.storageLine.contains(" "))
            }
        }
    }

    func testUnreadableCurveTextActsLinearIsFlaggedAndKept() throws {
        for text in ["wobble:3", "easeIn:50", "log:-1", "piecewise:0.5", ""] {
            let line: String = "cc:0:7=a;curve=" + text + ";invert=1"
            let binding = try XCTUnwrap(MIDIControlBinding(storageLine: line), text)
            XCTAssertEqual(binding.options.curve, .linear, text)
            XCTAssertTrue(binding.options.hasUnreadableCurve, text)
            XCTAssertEqual(binding.options.unreadableCurveText, text)
            XCTAssertEqual(binding.storageLine, line, "kept verbatim: " + text)
            XCTAssertEqual(binding.options.position(normalized: 0.25), 0.75, "linear, inverted")
            var chosen = binding.options
            chosen.setCurve(MIDICurvePreset.easeOut.curve)
            XCTAssertFalse(chosen.hasUnreadableCurve)
            XCTAssertEqual(chosen.segments, ["curve=easeOut:2.0", "invert=1"])
        }
        XCTAssertEqual(MIDIMappingOptions(curve: .easeIn(exponent: 99)).curve, .linear, "an invalid curve is never used")
    }

    func testEmptyRepeatedAndOddSegments() throws {
        let binding = try XCTUnwrap(MIDIControlBinding(storageLine: "cc:0:7=a;;curve=easeIn:2.0;curve=log:9.0;invert=1;invert=0;invert;x=y=z"))
        XCTAssertEqual(binding.options.curve, .easeIn(exponent: 2), "the first curve wins")
        XCTAssertTrue(binding.options.inverted, "the first invert wins")
        XCTAssertEqual(binding.options.extraSegments, ["invert", "x=y=z"], "a bare key is unknown and kept")
        XCTAssertEqual(binding.storageLine, "cc:0:7=a;curve=easeIn:2.0;invert=1;invert;x=y=z")
        XCTAssertFalse(try XCTUnwrap(MIDIControlBinding(storageLine: "cc:0:7=a;invert=yes")).options.inverted)
        XCTAssertNil(MIDIControlBinding(storageLine: "cc:0:7=;curve=log:9.0"), "the parameter ID is still required")
    }

    // MARK: List (C3)

    func testOptionsFollowTheParameter() {
        var list = MIDIBindingList()
        list.bind(Self.key(7), to: Self.unit)
        let shaped = MIDIMappingOptions(curve: .logarithmic(strength: 9), inverted: true)
        XCTAssertTrue(list.setOptions(shaped, for: Self.unit))
        XCTAssertFalse(list.setOptions(shaped, for: Self.small), "unmapped")

        XCTAssertEqual(list.bind(Self.key(9), to: Self.unit), .replaced(previous: Self.key(7)))
        XCTAssertEqual(list.binding(for: Self.unit)?.options, shaped, "relearning a parameter keeps its options")
        XCTAssertEqual(list.binding(forKey: Self.key(9))?.target, Self.unit)

        XCTAssertEqual(list.bind(Self.key(9), to: Self.small), .moved(from: Self.unit))
        XCTAssertEqual(list.binding(for: Self.small)?.options, .default, "a moved control takes the new parameter's options")

        list.bind(Self.key(1), to: Self.signed)
        list.setOptions(MIDIMappingOptions(inverted: true), for: Self.signed)
        XCTAssertEqual(list.binding(for: Self.small)?.options, .default, "setOptions changes only its binding")
        let restored = MIDIBindingList(storageLines: list.storageLines, allowedTargets: Set(Self.ids))
        XCTAssertEqual(restored, list)
        XCTAssertEqual(list.storageLines, ["cc:0:9=test.scale.small", "cc:0:1=test.scale.signed;invert=1"])
    }
}
