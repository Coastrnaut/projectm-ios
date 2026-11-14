// MappingCurveTests.swift — MOD-004-T02, T04: the roadmap acceptance ("Monotonic curve fixtures remain
// bounded and deterministic"), shape values, validation of invalid curves and the MIDI-004 text form
// (contract specs/129-mod-004-curve-mapping/contracts/mapping-curve.md K1-K6). Deterministic: no clock.
import Foundation
import ParameterGraph
import XCTest

final class MappingCurveTests: XCTestCase {
    // MARK: Fixtures

    /// Every kind with several parameters, the allowed extremes included (MOD-004-S1: at least 20).
    static let validFixtures: [MappingCurve] = {
        var curves: [MappingCurve] = [.linear]
        let exponents: [Double] = [1.000001, 1.5, 2, 3, 8]
        for p in exponents {
            curves.append(.easeIn(exponent: p))
            curves.append(.easeOut(exponent: p))
            curves.append(.easeInOut(exponent: p))
        }
        let strengths: [Double] = [1e-9, 0.01, 1, 9, 1000]
        for k in strengths {
            curves.append(.logarithmic(strength: k))
            curves.append(.exponential(strength: k))
        }
        curves.append(.piecewise([]))
        curves.append(.piecewise([CurvePoint(x: 0.5, y: 0.8)]))
        curves.append(.piecewise([CurvePoint(x: 0.25, y: 0.5), CurvePoint(x: 0.5, y: 0.5), CurvePoint(x: 0.75, y: 1)]))
        curves.append(.piecewise([CurvePoint(x: 1e-9, y: 1), CurvePoint(x: 0.999999, y: 1)]))
        curves.append(.piecewise([CurvePoint(x: 0.5, y: 0), CurvePoint(x: 0.9999999999999999, y: 0)]))
        let eight: [CurvePoint] = (1...8).map { (i: Int) -> CurvePoint in
            let x: Double = Double(i) / 9
            return CurvePoint(x: x, y: x * x)
        }
        curves.append(.piecewise(eight))
        return curves
    }()

    /// Invalid curves (MOD-004-S2): every fault of contract K5, at least 7 piecewise faults.
    static let invalidFixtures: [(curve: MappingCurve, mentions: String)] = {
        let p = { (x: Double, y: Double) -> CurvePoint in CurvePoint(x: x, y: y) }
        var nine: [CurvePoint] = []
        for i in 1...9 { nine.append(p(Double(i) / 10, Double(i) / 10)) }
        return [
            (.piecewise([p(0.6, 0.5), p(0.4, 0.7)]), "increasing"),
            (.piecewise([p(0.5, 0.2), p(0.5, 0.4)]), "increasing"),
            (.piecewise([p(0, 0.2)]), "inside"),
            (.piecewise([p(1, 0.2)]), "inside"),
            (.piecewise([p(-0.1, 0.2)]), "inside"),
            (.piecewise([p(0.5, 1.2)]), "0…1"),
            (.piecewise([p(0.5, -0.2)]), "0…1"),
            (.piecewise([p(0.3, 0.7), p(0.6, 0.4)]), "decrease"),
            (.piecewise([p(Double.nan, 0.5)]), "finite"),
            (.piecewise([p(0.5, Double.infinity)]), "finite"),
            (.piecewise(nine), "8"),
            (.easeIn(exponent: 1), "exponent"),
            (.easeOut(exponent: 0.5), "exponent"),
            (.easeInOut(exponent: 9), "exponent"),
            (.easeIn(exponent: Double.nan), "exponent"),
            (.easeOut(exponent: -Double.infinity), "exponent"),
            (.logarithmic(strength: 0), "strength"),
            (.logarithmic(strength: -1), "strength"),
            (.exponential(strength: 1001), "strength"),
            (.exponential(strength: Double.infinity), "strength"),
            (.logarithmic(strength: Double.nan), "strength"),
        ]
    }()

    /// 1,001 grid inputs plus 200 adjacent representable inputs after 0, around 0.5 and before 1.
    static let grid: [Double] = {
        var xs: [Double] = (0...1000).map { (i: Int) -> Double in Double(i) / 1000 }
        var x: Double = 0
        for _ in 0..<200 { x = x.nextUp; xs.append(x) }
        x = 0.5
        for _ in 0..<100 { x = x.nextDown }
        for _ in 0..<200 { x = x.nextUp; xs.append(x) }
        x = 1
        for _ in 0..<200 { x = x.nextDown; xs.append(x) }
        return xs.sorted()
    }()

    static let edgeInputs: [Double] = [-1, -0.0, 2, Double.nan, -Double.infinity, Double.infinity,
                                       -Double.leastNonzeroMagnitude, 1.0.nextUp, Double.greatestFiniteMagnitude]

    // MARK: Helpers

    /// Problems found sweeping `curve` over the grid: out of range, decreasing, inexact ends.
    private func sweepProblems(_ curve: MappingCurve) -> [String] {
        var problems: [String] = []
        var previous: Double = -1
        for x in Self.grid {
            let y: Double = curve.apply(x)
            if !(y >= 0 && y <= 1) { problems.append("\(curve): f(\(x)) = \(y) is outside 0…1") }
            if y < previous { problems.append("\(curve): f(\(x)) = \(y) decreases from \(previous)") }
            previous = y
            if problems.count > 3 { break }
        }
        if curve.apply(0) != 0 { problems.append("\(curve): f(0) = \(curve.apply(0))") }
        if curve.apply(1) != 1 { problems.append("\(curve): f(1) = \(curve.apply(1))") }
        return problems
    }

    private func outputs(_ curve: MappingCurve) -> [UInt64] {
        (Self.grid + Self.edgeInputs).map { (x: Double) -> UInt64 in curve.apply(x).bitPattern }
    }

    // MARK: Acceptance (MOD-004-S1)

    func testMonotonicCurveFixturesRemainBoundedAndDeterministic() {
        XCTAssertGreaterThanOrEqual(Self.validFixtures.count, 20)
        for curve in Self.validFixtures {
            XCTAssertNil(curve.validationProblem, "\(curve) is a valid fixture")
            XCTAssertEqual(sweepProblems(curve), [])
            XCTAssertEqual(outputs(curve), outputs(curve), "\(curve): two runs are bit-identical")
        }
    }

    func testEdgeInputsAreReadAsPositions() {
        for curve in Self.validFixtures {
            for x in [Double.nan, -Double.infinity, Double.infinity, -1, -0.0, -Double.leastNonzeroMagnitude] {
                XCTAssertEqual(curve.apply(x), 0, "\(curve): \(x) reads 0 (non-finite → 0, negative → 0)")
            }
            for x in [2, 1.0.nextUp, Double.greatestFiniteMagnitude] {
                XCTAssertEqual(curve.apply(x), 1, "\(curve): \(x) reads 1")
            }
        }
    }

    // MARK: Shapes (contract K4)

    func testShapeValues() {
        XCTAssertEqual(MappingCurve.linear.apply(0.3), 0.3)
        XCTAssertEqual(MappingCurve.easeIn(exponent: 2).apply(0.5), 0.25)
        XCTAssertEqual(MappingCurve.easeOut(exponent: 2).apply(0.5), 0.75)
        XCTAssertEqual(MappingCurve.easeInOut(exponent: 2).apply(0.25), 0.125)
        XCTAssertEqual(MappingCurve.easeInOut(exponent: 2).apply(0.5), 0.5)
        XCTAssertEqual(MappingCurve.easeInOut(exponent: 2).apply(0.75), 0.875)
        let expected: Double = log(5.5) / log(10)
        XCTAssertEqual(MappingCurve.logarithmic(strength: 9).apply(0.5), expected, accuracy: 1e-15)
        let piecewise = MappingCurve.piecewise([CurvePoint(x: 0.5, y: 0.8)])
        XCTAssertEqual(piecewise.apply(0.25), 0.4, accuracy: 1e-15)
        XCTAssertEqual(piecewise.apply(0.5), 0.8)
        XCTAssertEqual(piecewise.apply(0.75), 0.9, accuracy: 1e-15)
        XCTAssertEqual(MappingCurve.piecewise([]).apply(0.3), 0.3, "an empty piecewise curve is linear")
    }

    func testExponentialIsTheInverseOfLogarithmic() {
        for k in [0.01, 1, 9, 1000] {
            let log = MappingCurve.logarithmic(strength: k)
            let exp = MappingCurve.exponential(strength: k)
            for i in 0...100 {
                let x: Double = Double(i) / 100
                XCTAssertEqual(exp.apply(log.apply(x)), x, accuracy: 1e-12, "k \(k), x \(x)")
            }
        }
    }

    func testCurvesBendTheExpectedWay() {
        for x in [0.1, 0.3, 0.7, 0.9] {
            XCTAssertLessThan(MappingCurve.easeIn(exponent: 2).apply(x), x)
            XCTAssertGreaterThan(MappingCurve.easeOut(exponent: 2).apply(x), x)
            XCTAssertGreaterThan(MappingCurve.logarithmic(strength: 9).apply(x), x)
            XCTAssertLessThan(MappingCurve.exponential(strength: 9).apply(x), x)
        }
        XCTAssertTrue(MappingCurve.linear.isLinear)
        XCTAssertTrue(MappingCurve.piecewise([]).isLinear)
        XCTAssertFalse(MappingCurve.easeIn(exponent: 2).isLinear)
    }

    // MARK: Validation (MOD-004-S2, contract K5)

    func testInvalidPiecewiseCurvesAreReportedAndStillSafe() {
        for (curve, word) in Self.invalidFixtures {
            let problem: String? = curve.validationProblem
            XCTAssertNotNil(problem, "\(curve) is invalid")
            XCTAssertFalse(curve.isValid)
            XCTAssertTrue(problem?.contains(word) ?? false, "\(curve): \"\(problem ?? "")\" mentions \"\(word)\"")
            XCTAssertEqual(sweepProblems(curve), [], "an invalid curve used anyway stays bounded, monotonic, exact at the ends")
            XCTAssertEqual(outputs(curve), outputs(curve))
            for x in Self.edgeInputs {
                let y: Double = curve.apply(x)
                XCTAssertTrue(y >= 0 && y <= 1, "\(curve): f(\(x)) = \(y)")
            }
        }
    }

    // MARK: Text form (contract K6)

    func testTextFormRoundTrips() {
        let fixtures: [MappingCurve] = Self.validFixtures + Self.invalidFixtures.map(\.curve)
            .filter { (c: MappingCurve) -> Bool in !c.textForm.contains("nan") }
        for curve in fixtures {
            let text: String = curve.textForm
            XCTAssertFalse(text.contains(";") || text.contains("=") || text.contains(" "), text)
            XCTAssertEqual(MappingCurve(textForm: text), curve, text)
        }
        XCTAssertEqual(MappingCurve.linear.textForm, "linear")
        XCTAssertEqual(MappingCurve.easeIn(exponent: 2).textForm, "easeIn:2.0")
        XCTAssertEqual(MappingCurve.logarithmic(strength: 9).textForm, "log:9.0")
        XCTAssertEqual(MappingCurve.piecewise([CurvePoint(x: 0.25, y: 0.5)]).textForm, "piecewise:0.25,0.5")
        XCTAssertEqual(MappingCurve.piecewise([]).textForm, "piecewise:")
    }

    func testMalformedTextReadsAsNothing() {
        let texts: [String] = ["", "bezier:1", "easeIn:", "easeIn:x", "easeIn", "easeIn:2:3", "log:1:2", "exp:",
                               "piecewise:0.5", "piecewise:0.5,0.5,0.5", "piecewise:0.5,0.5/", "linear:1", "LINEAR",
                               "easeIn:2;x", " easeIn:2"]
        for text in texts { XCTAssertNil(MappingCurve(textForm: text), "\"\(text)\"") }
    }
}
