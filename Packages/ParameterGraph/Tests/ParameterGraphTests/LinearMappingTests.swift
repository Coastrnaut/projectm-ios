// LinearMappingTests.swift — MOD-003-T02, T04, T05: zero and one map to the configured ends exactly
// (roadmap acceptance), results stay bounded and monotonic, input is clamped, and existing MOD-002
// bindings keep their values (MOD-003-R1 to R8; contract L1 to L5).
// Deterministic and small: fixed positions only, no clock, no randomness.
import ParameterGraph
import XCTest

final class LinearMappingTests: XCTestCase {
    /// Representative output ranges: increasing, inverted, negative, tiny, huge, constant.
    static let ranges: [(start: Double, end: Double)] = [
        (0, 1), (0.2, 0.9), (0.9, 0.1), (-3, 7), (7, -3), (-5, -1),
        (1e-9, 2e-9), (-1e300, 1e300), (1e300, 1.5e300), (0.1, 0.1),
    ]

    /// MOD-002's inline formula, the regression reference.
    static func modulationTwo(_ start: Double, _ end: Double, _ s: Double) -> Double {
        (1 - s) * start + s * end
    }

    // MARK: US1 (T02)

    // (a) The roadmap acceptance.
    func testZeroAndOneMapToConfiguredEndpointsExactly() {
        for (start, end) in Self.ranges {
            let mapping = LinearMapping(outputStart: start, outputEnd: end)
            XCTAssertEqual(mapping.interpolate(0), start, "\(start)…\(end) at 0")
            XCTAssertEqual(mapping.interpolate(1), end, "\(start)…\(end) at 1")
            XCTAssertEqual(LinearMapping.interpolate(from: start, to: end, at: 0), start)
            XCTAssertEqual(LinearMapping.interpolate(from: start, to: end, at: 1), end)
            XCTAssertEqual(mapping.map(0), start)
            XCTAssertEqual(mapping.map(1), end)
        }
    }

    // (b) Input outside the input range, or not finite, maps exactly to an end.
    func testInputIsClampedToTheEnds() {
        let mapping = LinearMapping(inputMinimum: 0.25, inputMaximum: 0.75, outputStart: 0.9, outputEnd: 0.1)
        // A non-finite input gives a non-finite position, which reads 0 (MOD-002 semantics).
        let toStart: [Double] = [0.25, 0, -1, -.infinity, .infinity, .nan, Double(Float(0.25))]
        let toEnd: [Double] = [0.75, 1, 2, Double(Float(0.75))]
        for input in toStart { XCTAssertEqual(mapping.map(input), 0.9, "input \(input)") }
        for input in toEnd { XCTAssertEqual(mapping.map(input), 0.1, "input \(input)") }
        XCTAssertEqual(mapping.position(of: 0.5), 0.5)
        XCTAssertEqual(mapping.map(0.5), 0.5, accuracy: 1e-15)
        for input in [0.3, 0.6, 0.7] as [Double] {
            XCTAssertEqual(mapping.map(input), mapping.interpolate(mapping.position(of: input)), "contract L4")
        }
    }

    // (c) Validity, inversion, constant mappings, and invalid mappings never trap.
    func testValidityAndInvalidMappingsDoNotTrap() {
        XCTAssertEqual(LinearMapping.identity, LinearMapping(inputMinimum: 0, inputMaximum: 1, outputStart: 0, outputEnd: 1))
        XCTAssertTrue(LinearMapping.identity.isValid)
        XCTAssertFalse(LinearMapping.identity.isInverted)
        XCTAssertTrue(LinearMapping(outputStart: 0.9, outputEnd: 0.1).isInverted)
        XCTAssertTrue(LinearMapping(outputStart: 0.1, outputEnd: 0.1).isConstant)
        let invalid: [LinearMapping] = [
            LinearMapping(inputMinimum: 1, inputMaximum: 1, outputStart: 0, outputEnd: 1),
            LinearMapping(inputMinimum: 1, inputMaximum: 0, outputStart: 0, outputEnd: 1),
            LinearMapping(inputMinimum: .nan, inputMaximum: 1, outputStart: 0, outputEnd: 1),
            LinearMapping(inputMinimum: 0, inputMaximum: .infinity, outputStart: 0, outputEnd: 1),
            LinearMapping(outputStart: 0, outputEnd: .infinity),
            LinearMapping(outputStart: .nan, outputEnd: 1),
        ]
        for mapping in invalid {
            XCTAssertFalse(mapping.isValid, "\(mapping)")
            for input in [-1, 0, 0.5, 1, 2, .nan] as [Double] {
                let position = mapping.position(of: input)
                XCTAssertTrue(position >= 0 && position <= 1, "\(mapping) position of \(input)")
                _ = mapping.map(input)   // must not trap
            }
        }
    }

    // MARK: US2 (T04)

    func testInterpolationIsBoundedAndMonotonic() {
        for (start, end) in Self.ranges {
            let mapping = LinearMapping(outputStart: start, outputEnd: end)
            let low = min(start, end), high = max(start, end)
            var positions: [Double] = (0...1000).map { (i: Int) -> Double in Double(i) / 1000 }
            for seed in [0.1, 0.3, 0.5, 0.7, 0.9] as [Double] {
                var p = seed
                for _ in 0..<200 { positions.append(p); p = p.nextUp }
            }
            positions.sort()
            var previous = mapping.interpolate(positions[0])
            for p in positions {
                let value = mapping.interpolate(p)
                XCTAssertTrue(value >= low && value <= high, "\(start)…\(end) at \(p) gave \(value)")
                if end >= start {
                    XCTAssertGreaterThanOrEqual(value, previous, "\(start)…\(end) reversed at \(p)")
                } else {
                    XCTAssertLessThanOrEqual(value, previous, "\(start)…\(end) reversed at \(p)")
                }
                previous = value
            }
            for p in [-1, 2, .nan, -.infinity, .infinity] as [Double] {
                let clamped = LinearMapping.clampedPosition(p)
                XCTAssertEqual(mapping.interpolate(p), mapping.interpolate(clamped), "\(start)…\(end) at \(p)")
                XCTAssertEqual(clamped, p == 2 ? 1 : 0, "out-of-range \(p)")
            }
        }
        let constant = LinearMapping(outputStart: 0.1, outputEnd: 0.1)
        for i in 0...1000 { XCTAssertEqual(constant.interpolate(Double(i) / 1000), 0.1) }
    }

    // MARK: US3 (T05)

    func testMatchesModulationTwoFormula() {
        let identical: [(Double, Double)] = [(0, 1), (-0.2, 0.2), (0, 10), (0.9, 0), (-3, 7), (-1e300, 1e300)]
        let close: [(Double, Double)] = [(0.2, 0.9), (0.9, 0.1), (0.5, 1), (-5, -1), (1e300, 1.5e300)]
        for i in 0...1000 {
            let s = Double(i) / 1000
            for (start, end) in identical {
                let value = LinearMapping.interpolate(from: start, to: end, at: s)
                XCTAssertEqual(value.bitPattern, Self.modulationTwo(start, end, s).bitPattern, "\(start)…\(end) at \(s)")
            }
            for (start, end) in close {
                let value = LinearMapping.interpolate(from: start, to: end, at: s)
                let ulp = max(abs(start), abs(end)).ulp
                XCTAssertLessThanOrEqual(abs(value - Self.modulationTwo(start, end, s)), 2 * ulp, "\(start)…\(end) at \(s)")
            }
        }
    }

    func testBindingExposesItsMapping() {
        var binding = AudioFeatureBinding(source: .band(0), target: "test.layer.opacity", inputMinimum: 0.25,
                                          inputMaximum: 0.75, outputStart: 0.9, outputEnd: 0.1)
        XCTAssertEqual(binding.mapping, LinearMapping(inputMinimum: 0.25, inputMaximum: 0.75, outputStart: 0.9, outputEnd: 0.1))
        binding.mapping = LinearMapping(inputMinimum: -1, inputMaximum: 2, outputStart: 0.3, outputEnd: 0.6)
        XCTAssertEqual(binding.inputMinimum, -1)
        XCTAssertEqual(binding.inputMaximum, 2)
        XCTAssertEqual(binding.outputStart, 0.3)
        XCTAssertEqual(binding.outputEnd, 0.6)
    }
}
