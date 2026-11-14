// ParameterMacroTests.swift — MOD-010-T02 (US1; MOD-010-R1 to R5, S1 to S3; contract M1, M2): one macro value
// drives several parameters through their own curves and ranges. Expected values are the closed forms written
// out here (not the implementation's helpers). CPU only, runs on Linux.
import Foundation
import ParameterGraph
import XCTest

final class ParameterMacroTests: XCTestCase {
    static let intensity: ParameterID = "test.glow.intensity"
    static let radius: ParameterID = "test.glow.radius"
    static let bars: ParameterID = "test.spectrum.bars"
    static let count: ParameterID = "test.spectrum.count"
    static let enabled: ParameterID = "test.glow.enabled"
    static let tint: ParameterID = "test.glow.tint"
    static let group = ParameterGroup(id: "test.glow", displayName: "Glow")

    static func registry() throws -> ParameterRegistry {
        let barCases: [ParameterEnumCase] = ["16", "32", "64", "128"].map { (id: String) -> ParameterEnumCase in
            ParameterEnumCase(id: id, displayName: id)
        }
        return try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: intensity, displayName: "Intensity", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault),
            ParameterDescriptor(id: radius, displayName: "Radius", group: group, unit: .fractionOfOutput,
                                kind: .continuous(minimum: 0.005, maximum: 0.06, defaultValue: 0.02), modulation: .continuousDefault),
            ParameterDescriptor(id: bars, displayName: "Bars", group: group, unit: .count,
                                kind: .enumeration(cases: barCases, defaultValue: "64"), modulation: .discreteManual),
            ParameterDescriptor(id: count, displayName: "Count", group: group, unit: .count,
                                kind: .integer(minimum: 0, maximum: 12, defaultValue: 4, step: 4), modulation: .discreteManual),
            ParameterDescriptor(id: enabled, displayName: "Glow", group: group, unit: .none,
                                kind: .boolean(defaultValue: true), modulation: .discreteManual),
            ParameterDescriptor(id: tint, displayName: "Tint", group: group, unit: .none,
                                kind: .color(defaultValue: ParameterColor(red: 1, green: 1, blue: 1)), modulation: .discreteManual),
        ])
    }

    /// The acceptance macro: intensity easeIn 2 over 0.1…0.9, radius log 9 inverted over 0.01…0.05, bars linear.
    static let acceptance = ParameterMacro(name: "Glow sweep", value: 0, targets: [
        MacroTarget(parameter: intensity, curve: .easeIn(exponent: 2), outputMinimum: 0.1, outputMaximum: 0.9),
        MacroTarget(parameter: radius, curve: .logarithmic(strength: 9), outputMinimum: 0.01, outputMaximum: 0.05, inverted: true),
        MacroTarget(parameter: bars),
    ])

    private func values(_ evaluation: MacroEvaluation) -> [ParameterID: ParameterValue] {
        var result: [ParameterID: ParameterValue] = [:]
        for assignment in evaluation.assignments { result[assignment.parameter] = assignment.value }
        return result
    }

    // MARK: Acceptance (MOD-010-S1)

    func testAcceptanceEveryTargetFollowsItsOwnCurveAndRange() throws {
        let registry = try Self.registry()
        let expectedBars: [Double: String] = [0: "16", 0.25: "32", 0.5: "64", 1: "128"]
        for m: Double in [0, 0.25, 0.5, 1] {
            var macro = Self.acceptance
            macro.value = m
            let evaluation = macro.evaluate(registry: registry)
            XCTAssertTrue(evaluation.skipped.isEmpty, "\(evaluation.skipped)")
            let v = values(evaluation)
            let intensity: Double = try XCTUnwrap(v[Self.intensity]?.doubleValue)
            let radius: Double = try XCTUnwrap(v[Self.radius]?.doubleValue)
            let expectedIntensity: Double = 0.1 + pow(m, 2) * 0.8
            let logPosition: Double = log(1 + 9 * (1 - m)) / log(10)
            let expectedRadius: Double = 0.01 + logPosition * 0.04
            XCTAssertEqual(intensity, expectedIntensity, accuracy: 1e-9, "m = \(m)")
            XCTAssertEqual(radius, expectedRadius, accuracy: 1e-9, "m = \(m)")
            XCTAssertEqual(v[Self.bars], .enumeration(expectedBars[m]!), "m = \(m)")
        }
        // Exactly at the ends.
        let low = values(Self.acceptance.evaluate(at: 0, registry: registry))
        XCTAssertEqual(low[Self.intensity], .continuous(0.1))
        XCTAssertEqual(low[Self.radius], .continuous(0.05))
        let high = values(Self.acceptance.evaluate(at: 1, registry: registry))
        XCTAssertEqual(high[Self.intensity], .continuous(0.9))
        XCTAssertEqual(high[Self.radius], .continuous(0.01))
    }

    func testInvertReadsTheMacroReversed() throws {
        let registry = try Self.registry()
        let plain = ParameterMacro(name: "m", targets: [MacroTarget(parameter: Self.intensity, curve: .easeOut(exponent: 3))])
        var reversed = plain
        reversed.targets[0].inverted = true
        for m: Double in [0, 0.2, 0.7, 1] {
            let a = values(plain.evaluate(at: 1 - m, registry: registry))[Self.intensity]
            let b = values(reversed.evaluate(at: m, registry: registry))[Self.intensity]
            XCTAssertEqual(a, b, "m = \(m)")
        }
        XCTAssertEqual(values(reversed.evaluate(at: 0, registry: registry))[Self.intensity], .continuous(1))
        XCTAssertEqual(values(reversed.evaluate(at: 1, registry: registry))[Self.intensity], .continuous(0))
    }

    // MARK: Clamp (MOD-010-S2)

    func testRangeBeyondTheRegistryIsLimitedToIt() throws {
        let registry = try Self.registry()
        let macro = ParameterMacro(name: "wide", targets: [
            MacroTarget(parameter: Self.radius, outputMinimum: -1, outputMaximum: 2),
            MacroTarget(parameter: Self.bars, outputMinimum: -3, outputMaximum: 9),
        ])
        for m: Double in [0, 0.1, 0.5, 0.9, 1] {
            let v = values(macro.evaluate(at: m, registry: registry))
            let r: Double = try XCTUnwrap(v[Self.radius]?.doubleValue)
            XCTAssertGreaterThanOrEqual(r, 0.005)
            XCTAssertLessThanOrEqual(r, 0.06)
            XCTAssertNotNil(v[Self.bars])
        }
        XCTAssertEqual(values(macro.evaluate(at: 0, registry: registry))[Self.radius], .continuous(0.005))
        XCTAssertEqual(values(macro.evaluate(at: 1, registry: registry))[Self.bars], .enumeration("128"))
        XCTAssertEqual(values(macro.evaluate(at: 0, registry: registry))[Self.bars], .enumeration("16"))
    }

    func testMacroValueOutsideZeroToOneIsLimitedAndNonFiniteReadsZero() throws {
        let registry = try Self.registry()
        let macro = ParameterMacro(name: "m", targets: [MacroTarget(parameter: Self.intensity)])
        XCTAssertEqual(values(macro.evaluate(at: 3, registry: registry))[Self.intensity], .continuous(1))
        XCTAssertEqual(values(macro.evaluate(at: -2, registry: registry))[Self.intensity], .continuous(0))
        XCTAssertEqual(values(macro.evaluate(at: .nan, registry: registry))[Self.intensity], .continuous(0))
        XCTAssertEqual(ParameterMacro(name: "m", value: .infinity).normalizedValue, 0)
    }

    func testIntegerTargetsSnapToTheNearestStep() throws {
        let registry = try Self.registry()
        let macro = ParameterMacro(name: "m", targets: [MacroTarget(parameter: Self.count)])
        let expected: [(Double, Int)] = [(0, 0), (0.1, 0), (0.2, 4), (0.5, 8), (0.9, 12), (1, 12)]
        for (m, value) in expected {
            XCTAssertEqual(values(macro.evaluate(at: m, registry: registry))[Self.count], .integer(value), "m = \(m)")
        }
    }

    // MARK: Skips (MOD-010-R5, S3)

    func testUnknownAndInvalidTargetsAreSkippedAndReportedOthersApply() throws {
        let registry = try Self.registry()
        let macro = ParameterMacro(name: "m", value: 1, targets: [
            MacroTarget(parameter: "test.future.knob"),
            MacroTarget(parameter: Self.intensity),
            MacroTarget(parameter: Self.enabled),
            MacroTarget(parameter: Self.tint),
            MacroTarget(parameter: Self.radius, curve: .easeIn(exponent: 0.5)),
            MacroTarget(parameter: Self.radius, outputMinimum: 0.05, outputMaximum: 0.01),
            MacroTarget(parameter: Self.radius, outputMinimum: .nan),
            MacroTarget(parameter: Self.intensity, outputMaximum: 0.2),
        ])
        let evaluation = macro.evaluate(registry: registry)
        XCTAssertEqual(evaluation.assignments, [MacroAssignment(parameter: Self.intensity, value: .continuous(1))])
        XCTAssertEqual(evaluation.skipped.map(\.index), [0, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(evaluation.skipped[0].problem, .unknownParameter)
        XCTAssertEqual(evaluation.skipped[1].problem, .unsupportedKind("boolean"))
        XCTAssertEqual(evaluation.skipped[2].problem, .unsupportedKind("color"))
        guard case .invalidCurve = evaluation.skipped[3].problem else { return XCTFail("\(evaluation.skipped[3])") }
        XCTAssertEqual(evaluation.skipped[4].problem, .invalidRange)
        XCTAssertEqual(evaluation.skipped[5].problem, .invalidRange)
        XCTAssertEqual(evaluation.skipped[6].problem, .duplicateParameter)
        XCTAssertFalse(evaluation.skipped[0].problem.description.isEmpty)
    }

    func testTargetsBeyondTheLimitAreSkipped() throws {
        let registry = try Self.registry()
        let filler: [MacroTarget] = [Self.intensity, Self.radius, Self.bars, Self.count].map { (id: ParameterID) -> MacroTarget in
            MacroTarget(parameter: id)
        }
        let unknown: [MacroTarget] = (0..<4).map { (i: Int) -> MacroTarget in MacroTarget(parameter: ParameterID("test.u\(i)")) }
        let macro = ParameterMacro(name: "m", targets: filler + unknown + [MacroTarget(parameter: "test.ninth")])
        let evaluation = macro.evaluate(at: 0.5, registry: registry)
        XCTAssertEqual(evaluation.assignments.count, 4)
        XCTAssertEqual(evaluation.skipped.last, MacroSkip(index: 8, parameter: "test.ninth", problem: .beyondLimit))
    }
}
