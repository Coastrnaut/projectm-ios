// CurvedBindingTests.swift — MOD-004-T06, T09: a binding's curve shapes its smoothed signal before
// MOD-003's interpolation, an invalid curve is refused, and the default linear curve is bit-identical to
// the pipeline before this row (MOD-004-R6, R7; contract K5, K7; research MOD-004-D4). Deterministic:
// frames and timestamps are passed in.
import Foundation
import ParameterGraph
import XCTest

final class CurvedBindingTests: XCTestCase {
    static let opacity: ParameterID = "test.layer.opacity"
    static let group = ParameterGroup(id: "test.layer", displayName: "Layer")
    static let frame: UInt64 = 16_666_667

    static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: opacity, displayName: "Opacity", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.25), modulation: .continuousDefault),
        ])
    }

    private func advance(_ modulator: AudioFeatureModulator, band: Float, at time: UInt64) {
        let bands: [Float] = [band]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            modulator.advance(frame: AudioFeatureFrame(bands: buffer), timeNanoseconds: time)
        }
    }

    private func binding(_ curve: MappingCurve, output: (Double, Double) = (0, 1),
                         envelope: AudioFeatureEnvelope = .none) -> AudioFeatureBinding {
        AudioFeatureBinding(source: .band(0), target: Self.opacity, outputStart: output.0, outputEnd: output.1,
                            envelope: envelope, curve: curve)
    }

    // MARK: T06 — curves drive the value

    func testEaseInBindingResolvesTheCurvedValue() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        try modulator.bind(binding(.easeIn(exponent: 2)))
        XCTAssertEqual(modulator.bindings.first?.curve, .easeIn(exponent: 2))
        var time: UInt64 = 1_000
        let expected: [(band: Float, value: Double)] = [(0, 0), (0.5, 0.25), (1, 1)]
        for row in expected {
            advance(modulator, band: row.band, at: time)
            time += Self.frame
            XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.25), row.value, "band \(row.band)")
            XCTAssertEqual(modulator.signal(for: Self.opacity), Double(row.band), "the stored signal stays linear")
        }
    }

    func testCurveFollowsAnInvertedRange() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        try modulator.bind(binding(.easeOut(exponent: 2), output: (0.9, 0.1)))
        advance(modulator, band: 0.5, at: 1_000)
        // easeOut(0.5) = 0.75 → 0.9 + 0.75·(0.1 − 0.9) = 0.3
        XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.25), 0.3, accuracy: 1e-12)
        advance(modulator, band: 0, at: 1_000 + Self.frame)
        XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.25), 0.9, "position 0 is the start exactly")
    }

    func testCurveShapesTheSmoothedSignal() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        let curve = MappingCurve.logarithmic(strength: 9)
        try modulator.bind(binding(curve, envelope: AudioFeatureEnvelope(attackSeconds: 0.1, releaseSeconds: 0.1)))
        var time: UInt64 = 1_000
        for _ in 0..<5 {
            advance(modulator, band: 1, at: time)
            time += Self.frame
            let signal: Double = try XCTUnwrap(modulator.signal(for: Self.opacity))
            let expected: Double = LinearMapping(outputStart: 0, outputEnd: 1).interpolate(curve.apply(signal))
            XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.25), expected)
        }
        let signal: Double = try XCTUnwrap(modulator.signal(for: Self.opacity))
        XCTAssertGreaterThan(signal, 0)
        XCTAssertLessThan(signal, 1, "the envelope is still rising")
    }

    // MARK: T06 — invalid curves are refused (contract K5)

    func testInvalidCurveIsRefused() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        try modulator.bind(binding(.easeIn(exponent: 3)))
        let bad = MappingCurve.piecewise([CurvePoint(x: 0.6, y: 0.5), CurvePoint(x: 0.4, y: 0.7)])
        XCTAssertThrowsError(try modulator.bind(binding(bad))) { (error: Error) -> Void in
            guard case let .invalidCurve(id, reason)? = error as? AudioFeatureBindingError else {
                return XCTFail("expected invalidCurve, got \(error)")
            }
            XCTAssertEqual(id, Self.opacity)
            XCTAssertEqual(reason, bad.validationProblem)
            let text: String = (error as? AudioFeatureBindingError)?.description ?? ""
            XCTAssertTrue(text.hasPrefix("the curve bound to \"test.layer.opacity\" is invalid: "), text)
        }
        XCTAssertEqual(modulator.bindings.map(\.curve), [.easeIn(exponent: 3)], "the previous binding stays")
        XCTAssertThrowsError(try modulator.bind(binding(.logarithmic(strength: 0))))
    }

    // MARK: T09 — linear is bit-identical (MOD-004-R7)

    static let ranges: [(Double, Double)] = [(0, 1), (-3, 7), (0.2, 0.9), (0.9, 0.1), (-5, -1), (0.1, 0.1), (1e300, 1.5e300)]

    func testLinearCurveIsBitIdentical() {
        var signals: [Double] = (0...10_000).map { (i: Int) -> Double in Double(i) / 10_000 }
        signals += [-0.0, -1, 2, Double.nan, Double.infinity, -Double.infinity, 0.5.nextUp, 1.0.nextDown]
        for (start, end) in Self.ranges {
            let mapping = LinearMapping(outputStart: start, outputEnd: end)
            for s in signals {
                let before: Double = mapping.interpolate(s)
                let after: Double = mapping.interpolate(MappingCurve.linear.apply(s))
                XCTAssertEqual(after.bitPattern, before.bitPattern, "\(start)…\(end) at \(s)")
            }
        }
    }

    func testDefaultBindingResolvesLikeAnExplicitLinearOne() throws {
        let registry = try Self.registry()
        let implicit = AudioFeatureModulator(registry: registry)
        let explicit = AudioFeatureModulator(registry: registry)
        try implicit.bind(AudioFeatureBinding(source: .band(0), target: Self.opacity, outputStart: 0.2, outputEnd: 0.9))
        try explicit.bind(binding(.linear, output: (0.2, 0.9)))
        XCTAssertEqual(implicit.bindings.first?.curve, .linear, "the default curve is linear")
        var time: UInt64 = 1_000
        for i in 0...1000 {
            let band: Float = Float(i) / 1000
            advance(implicit, band: band, at: time)
            advance(explicit, band: band, at: time)
            time += Self.frame
            let a: Double = implicit.value(for: Self.opacity, manual: 0.25)
            let b: Double = explicit.value(for: Self.opacity, manual: 0.25)
            let unshaped: Double = LinearMapping(outputStart: 0.2, outputEnd: 0.9).interpolate(Double(band))
            XCTAssertEqual(a.bitPattern, b.bitPattern)
            XCTAssertEqual(a.bitPattern, unshaped.bitPattern, "band \(band)")
        }
    }
}
