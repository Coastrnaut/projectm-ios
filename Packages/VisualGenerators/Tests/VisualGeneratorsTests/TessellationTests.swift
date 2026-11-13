// TessellationTests.swift — VIS-001-T10: the vertex data the GPU draws matches the bar geometry
// (research VIS-001-D2). Vertices are mapped back from NDC to pixels with the test's own inverse.
import XCTest
@testable import VisualGenerators

final class TessellationTests: XCTestCase {
    private func vertices(_ layout: CircularSpectrumLayout, gain: Float = 1) -> [SpectrumVertex] {
        var out = [SpectrumVertex](repeating: SpectrumVertex(), count: CircularSpectrumLayout.maximumVertexCount)
        let n = out.withUnsafeMutableBufferPointer { layout.tessellate(into: $0.baseAddress!, capacity: $0.count, gain: gain) }
        return Array(out[0..<n])
    }

    func testVertexLayoutIs24Bytes() {
        XCTAssertEqual(MemoryLayout<SpectrumVertex>.stride, 24)
        XCTAssertEqual(CircularSpectrumLayout.verticesPerBar, 24)
        XCTAssertEqual(CircularSpectrumLayout.maximumVertexCount, 128 * 24)
    }

    func testOnlyLitBarsProduceVerticesAndTheyStayInsideTheirSector() {
        let (w, h) = (1640, 2360)
        for n in GeometryOracle.barCounts {
            let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: SpectrumBarCount(rawValue: n)!))
            for k in [0, n / 4, n / 2, n - 1] {
                layout.layout(GeometryOracle.impulse(at: k, count: n), width: w, height: h)
                let v = vertices(layout)
                XCTAssertEqual(v.count, 24, "N=\(n) k=\(k)")
                let bar = layout.bar(k)
                let theta = GeometryOracle.angle(bar: k, count: n)
                for vertex in v {
                    let p = GeometryOracle.pixel(ndcX: vertex.x, ndcY: vertex.y, width: w, height: h)
                    let polar = GeometryOracle.polar(x: p.x, y: p.y, width: w, height: h)
                    XCTAssertLessThanOrEqual(GeometryOracle.distance(polar.angle, theta), bar.halfWidthDegrees + 1e-3, "N=\(n) k=\(k)")
                    XCTAssertGreaterThanOrEqual(polar.radius, bar.innerRadius - 1e-2)
                    XCTAssertLessThanOrEqual(polar.radius, bar.outerRadius + 1e-2)
                }
            }
            layout.layout([Float](repeating: 0, count: n), width: w, height: h)
            XCTAssertEqual(vertices(layout).count, 0, "silence: no vertices")
        }
    }

    func testColorsArePremultipliedAndScaledByTheGain() {
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b16, palette: .mono))
        layout.layout(GeometryOracle.impulse(at: 5, count: 16), width: 400, height: 400)
        for vertex in vertices(layout, gain: 0.25) {
            XCTAssertEqual(vertex.r, 0.25, accuracy: 1e-6)
            XCTAssertEqual(vertex.g, 0.25, accuracy: 1e-6)
            XCTAssertEqual(vertex.b, 0.25, accuracy: 1e-6)
            XCTAssertEqual(vertex.a, 1)
        }
    }

    func testAllBarsFitTheCapacityAndASmallCapacityIsNeverOverrun() {
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b128))
        layout.layout([Float](repeating: 1, count: 128), width: 1000, height: 700)
        XCTAssertEqual(vertices(layout).count, 3_072)
        var small = [SpectrumVertex](repeating: SpectrumVertex(), count: 50)
        let n = small.withUnsafeMutableBufferPointer { layout.tessellate(into: $0.baseAddress!, capacity: $0.count, gain: 1) }
        XCTAssertEqual(n, 48, "whole bars only, never past the capacity")
    }

    func testTinyAndEmptyOutputs() {
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b16))
        layout.layout([Float](repeating: 1, count: 16), width: 0, height: 0)
        XCTAssertEqual(vertices(layout).count, 0, "zero size draws nothing")
        layout.layout([Float](repeating: 1, count: 16), width: 1, height: 1)
        for v in vertices(layout) {
            XCTAssertTrue(v.x.isFinite && v.y.isFinite)
            XCTAssertTrue((-1...1).contains(v.x) && (-1...1).contains(v.y))
        }
    }
}
