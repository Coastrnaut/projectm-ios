// ConfigurationTests.swift — VIS-001-T03: defaults and clamping of the circular spectrum's
// configuration (VIS-001-R4; data-model.md).
import XCTest
@testable import VisualGenerators

final class ConfigurationTests: XCTestCase {
    func testDefaults() {
        let c = CircularSpectrumConfiguration()
        XCTAssertEqual(c.barCount, .b64)
        XCTAssertEqual(c.innerRadius, 0.3)
        XCTAssertEqual(c.lengthScale, 0.65)
        XCTAssertEqual(c.gap, 0.2)
        XCTAssertEqual(c.rotationOffsetDegrees, 0)
        XCTAssertEqual(c.startAngleDegrees, 0)
        XCTAssertEqual(c.direction, .clockwise)
        XCTAssertEqual(c.palette, .spectrum)
        XCTAssertEqual(c.background, .opaqueBlack)
    }

    func testBarCountsAreTheANL002Counts() {
        XCTAssertEqual(SpectrumBarCount.allCases.map(\.rawValue), [16, 32, 64, 128])
        XCTAssertNil(SpectrumBarCount(rawValue: 24))
        XCTAssertEqual(SpectrumBarCount.maximum, 128)
    }

    func testOutOfRangeValuesAreClamped() {
        var c = CircularSpectrumConfiguration(innerRadius: 2, lengthScale: 5, gap: 3)
        XCTAssertEqual(c.innerRadius, 0.9)
        XCTAssertEqual(c.lengthScale, 0.1, accuracy: 1e-12, "lengthScale 0…(1 − innerRadius)")
        XCTAssertEqual(c.gap, 0.9)
        c = CircularSpectrumConfiguration(innerRadius: -1, lengthScale: -1, gap: -1)
        XCTAssertEqual(c.innerRadius, 0.05)
        XCTAssertEqual(c.lengthScale, 0)
        XCTAssertEqual(c.gap, 0)
        c = CircularSpectrumConfiguration(innerRadius: .nan, lengthScale: .nan, gap: .nan,
                                          rotationOffsetDegrees: .infinity, startAngleDegrees: .nan)
        XCTAssertEqual(c.innerRadius, 0.3, "non-finite → default")
        XCTAssertEqual(c.lengthScale, 0.65)
        XCTAssertEqual(c.gap, 0.2)
        XCTAssertEqual(c.rotationOffsetDegrees, 0)
        XCTAssertEqual(c.startAngleDegrees, 0)
        // Values set after init are clamped by `clamped()`, which every consumer applies.
        var raw = CircularSpectrumConfiguration()
        raw.innerRadius = 0.95
        raw.lengthScale = 0.5
        let clamped = raw.clamped()
        XCTAssertEqual(clamped.innerRadius, 0.9)
        XCTAssertEqual(clamped.lengthScale, 0.1, accuracy: 1e-12)
        XCTAssertEqual(clamped.clamped(), clamped, "idempotent")
    }

    func testAnglesFollowTheFormula() {
        for n in GeometryOracle.barCounts {
            let count = SpectrumBarCount(rawValue: n)!
            for direction in [RingDirection.clockwise, .counterClockwise] {
                let c = CircularSpectrumConfiguration(barCount: count, gap: 0.25, rotationOffsetDegrees: 37.5,
                                                      startAngleDegrees: 45, direction: direction)
                XCTAssertEqual(c.pitchDegrees, 360 / Double(n), accuracy: 1e-12)
                XCTAssertEqual(c.halfWidthDegrees, 0.75 * 180 / Double(n), accuracy: 1e-12)
                for k in 0..<n {
                    let expected = GeometryOracle.angle(bar: k, count: n, start: 45, clockwise: direction == .clockwise, offset: 37.5)
                    XCTAssertLessThan(GeometryOracle.distance(c.centerDegrees(ofBar: k), expected), 1e-9)
                    XCTAssertTrue((0..<360).contains(c.centerDegrees(ofBar: k)))
                }
            }
        }
    }
}
