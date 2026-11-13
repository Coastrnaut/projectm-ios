// CircularSpectrumGeometryTests.swift — VIS-001-T10, the roadmap acceptance on the CPU: "Band
// impulse lights the correct angular segment" (VIS-001-R2, R3, R8; S1). For every bar count and
// every band, an impulse lights exactly one bar, at the angle the test computes itself
// (GeometryOracle), within 0.01°. Runs everywhere, including Linux and GPU-less CI.
import XCTest
@testable import VisualGenerators

final class CircularSpectrumGeometryTests: XCTestCase {
    private let width = 1179, height = 2556

    func testEveryImpulseLightsExactlyItsBarAtThePredictedAngle() {
        var cases = 0
        for n in GeometryOracle.barCounts {
            let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: SpectrumBarCount(rawValue: n)!))
            let config = layout.configuration
            let unit = Double(min(width, height)) / 2
            var worst = 0.0
            for k in 0..<n {
                layout.layout(GeometryOracle.impulse(at: k, count: n), width: width, height: height)
                let lit = (0..<n).filter { layout.bar($0).isLit }
                XCTAssertEqual(lit, [k], "N=\(n) k=\(k)")
                let bar = layout.bar(k)
                let error = GeometryOracle.distance(bar.centerDegrees, GeometryOracle.angle(bar: k, count: n))
                worst = max(worst, error)
                XCTAssertLessThan(error, 0.01, "N=\(n) k=\(k)")
                XCTAssertEqual(bar.halfWidthDegrees, (1 - 0.2) * 180 / Double(n), accuracy: 1e-9)
                XCTAssertEqual(bar.innerRadius, 0.3 * unit, accuracy: 1e-9)
                XCTAssertEqual(bar.outerRadius, (0.3 + config.lengthScale) * unit, accuracy: 1e-9)
                cases += 1
            }
            print("VIS-001 matrix: N=\(n) impulses=\(n) size=\(width)x\(height) worst angle error=\(worst)°")
        }
        XCTAssertEqual(cases, 240)
    }

    func testSilenceLightsNothing() {
        for n in GeometryOracle.barCounts {
            let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: SpectrumBarCount(rawValue: n)!))
            layout.layout([Float](repeating: 0, count: n), width: width, height: height)
            XCTAssertFalse((0..<n).contains { layout.bar($0).isLit })
        }
    }

    func testInputsAreSanitized() {
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b16))
        layout.layout([.nan, -1, 2, .infinity, 0.5, -.infinity], width: width, height: height)
        let unit = Double(min(width, height)) / 2
        let length = layout.configuration.lengthScale * unit
        let inner = layout.bar(0).innerRadius
        let expected: [Double] = [0, 0, 1, 1, 0.5, 0]
        for (k, v) in expected.enumerated() {
            XCTAssertEqual(layout.bar(k).outerRadius - inner, v * length, accuracy: 1e-9, "bar \(k)")
            XCTAssertEqual(layout.value(ofBar: k), Float(v))
        }
        for k in 6..<16 { XCTAssertFalse(layout.bar(k).isLit, "missing bands read 0") }
        // Extra values are ignored.
        layout.layout([Float](repeating: 1, count: 40), width: width, height: height)
        XCTAssertEqual(layout.barCount, 16)
        XCTAssertTrue((0..<16).allSatisfy { layout.bar($0).isLit })
    }

    func testDirectionAndStartAngle() {
        for n in GeometryOracle.barCounts {
            for clockwise in [true, false] {
                let c = CircularSpectrumConfiguration(barCount: SpectrumBarCount(rawValue: n)!, startAngleDegrees: 45,
                                                      direction: clockwise ? .clockwise : .counterClockwise)
                let layout = CircularSpectrumLayout(configuration: c)
                for k in [0, n / 3, n - 1] {
                    layout.layout(GeometryOracle.impulse(at: k, count: n), width: width, height: height)
                    XCTAssertLessThan(GeometryOracle.distance(layout.bar(k).centerDegrees,
                                                              GeometryOracle.angle(bar: k, count: n, start: 45, clockwise: clockwise)), 0.01)
                }
            }
        }
    }

    func testBarCountChangesTakeEffectAtTheNextLayout() {
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b128))
        layout.layout(GeometryOracle.impulse(at: 100, count: 128), width: width, height: height)
        layout.configuration.barCount = .b16
        layout.layout(GeometryOracle.impulse(at: 3, count: 16), width: width, height: height)
        XCTAssertEqual(layout.barCount, 16)
        XCTAssertEqual((0..<16).filter { layout.bar($0).isLit }, [3])
    }

    func testIdenticalInputsGiveIdenticalGeometry() {
        let values = (0..<64).map { Float($0 % 7) / 7 }
        let a = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration())
        let b = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration())
        a.layout(values, width: 800, height: 600)
        b.layout(values, width: 800, height: 600)
        for k in 0..<64 { XCTAssertEqual(a.bar(k), b.bar(k)) }
        var va = [SpectrumVertex](repeating: SpectrumVertex(), count: CircularSpectrumLayout.maximumVertexCount)
        var vb = va
        let na = va.withUnsafeMutableBufferPointer { a.tessellate(into: $0.baseAddress!, capacity: $0.count, gain: 1) }
        let nb = vb.withUnsafeMutableBufferPointer { b.tessellate(into: $0.baseAddress!, capacity: $0.count, gain: 1) }
        XCTAssertEqual(na, nb)
        XCTAssertEqual(va, vb)
    }
}
