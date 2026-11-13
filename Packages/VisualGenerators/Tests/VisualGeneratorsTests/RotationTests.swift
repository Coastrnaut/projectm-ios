// RotationTests.swift — VIS-001-T17, the acceptance's second half on the CPU: "survives rotation"
// (User Story 3; VIS-001-R3, R5; S1, S2). Both meanings: the output turning between portrait and
// landscape (and iPad sizes), and the configurable rotation offset. 240 impulses × 5 sizes × 6
// offsets = 7,200 layouts; every lit vertex is checked in pixels with the test's own inverse mapping.
import XCTest
@testable import VisualGenerators

final class RotationTests: XCTestCase {
    func testImpulseAngleSurvivesEverySizeAndOffset() {
        var layouts = 0
        var vertexChecks = 0
        var worstAngle = 0.0
        var worstIsotropy = 0.0
        var out = [SpectrumVertex](repeating: SpectrumVertex(), count: CircularSpectrumLayout.maximumVertexCount)
        for n in GeometryOracle.barCounts {
            for offset in GeometryOracle.offsets {
                let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(
                    barCount: SpectrumBarCount(rawValue: n)!, rotationOffsetDegrees: offset))
                for size in GeometryOracle.sizes {
                    let unit = Double(min(size.width, size.height)) / 2
                    for k in 0..<n {
                        layout.layout(GeometryOracle.impulse(at: k, count: n), width: size.width, height: size.height)
                        XCTAssertEqual(layout.radiusUnit, unit)
                        let lit = (0..<n).filter { layout.bar($0).isLit }
                        XCTAssertEqual(lit, [k], "N=\(n) k=\(k) offset=\(offset) \(size)")
                        let expected = GeometryOracle.angle(bar: k, count: n, offset: offset)
                        let bar = layout.bar(k)
                        let error = GeometryOracle.distance(bar.centerDegrees, expected)
                        worstAngle = max(worstAngle, error)
                        XCTAssertLessThan(error, 0.01, "N=\(n) k=\(k) offset=\(offset) \(size)")
                        // The offset turns the bar by exactly φ.
                        let unrotated = GeometryOracle.angle(bar: k, count: n)
                        XCTAssertLessThan(GeometryOracle.distance(bar.centerDegrees - offset, unrotated), 0.01)
                        let count = out.withUnsafeMutableBufferPointer { layout.tessellate(into: $0.baseAddress!, capacity: $0.count, gain: 1) }
                        XCTAssertEqual(count, 24)
                        for vertex in out[0..<count] {
                            let p = GeometryOracle.pixel(ndcX: vertex.x, ndcY: vertex.y, width: size.width, height: size.height)
                            // Inside the output: nothing cut off.
                            XCTAssertTrue(p.x >= -1e-6 && p.x <= Double(size.width) + 1e-6 && p.y >= -1e-6 && p.y <= Double(size.height) + 1e-6,
                                          "vertex outside the output: N=\(n) k=\(k) \(size)")
                            let polar = GeometryOracle.polar(x: p.x, y: p.y, width: size.width, height: size.height)
                            // Isotropy: the pixel distance from the centre is a valid radius of the bar,
                            // whatever the direction (a stretched ring would break this on one axis).
                            let radiusError = max(0, bar.innerRadius - polar.radius, polar.radius - bar.outerRadius)
                            worstIsotropy = max(worstIsotropy, radiusError)
                            XCTAssertLessThan(radiusError, 0.01)
                            XCTAssertLessThanOrEqual(GeometryOracle.distance(polar.angle, expected), bar.halfWidthDegrees + 1e-3)
                            XCTAssertLessThanOrEqual(polar.radius, unit + 1e-6, "inside the ring's circle")
                            vertexChecks += 1
                        }
                        layouts += 1
                    }
                }
            }
        }
        XCTAssertEqual(layouts, 7_200)
        print("VIS-001 rotation matrix: \(layouts) layouts, \(vertexChecks) vertices, worst angle error \(worstAngle)°, worst radius error \(worstIsotropy) px")
    }

    func testPortraitAndLandscapeGiveTheSameAngles() {
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b32, rotationOffsetDegrees: 37.5))
        for k in 0..<32 {
            layout.layout(GeometryOracle.impulse(at: k, count: 32), width: 1179, height: 2556)
            let portrait = layout.bar(k)
            layout.layout(GeometryOracle.impulse(at: k, count: 32), width: 2556, height: 1179)
            let landscape = layout.bar(k)
            XCTAssertEqual(portrait, landscape, "same angle, same radii: the shorter side is the same")
        }
    }
}
