// LissajousFixtures.swift — VIS-004-T04: interleaved stereo fixtures and the shape metric for the Lissajous
// acceptance (VIS-004-S1, S2).
import Foundation
@testable import VisualGenerators

enum LissajousFixture {
    static let sampleRate = 44_100.0
    /// Frames in a fixture history (the tap's stereo history).
    static let frames = 2_048

    enum Kind {
        /// L = R = A sin.
        case inPhase
        /// L = A sin, R = A sin shifted 90° (A cos).
        case quadrature
        /// R = −L.
        case antiPhase
        /// L = A sin, R = 0.
        case leftOnly
    }

    /// The interleaved history (oldest first) whose newest frame has absolute index `end − 1`.
    static func history(_ kind: Kind, frequency: Double = 440, amplitude: Double = 0.8, endingAt end: Int = 60_000) -> [Float] {
        var out = [Float](repeating: 0, count: 2 * frames)
        for i in 0..<frames {
            let n = Double(end - frames + i)
            let cycles: Double = n * frequency / sampleRate
            let phase: Double = 2 * Double.pi * (cycles - cycles.rounded(.down))
            let s: Double = amplitude * sin(phase)
            let left: Double = s
            let right: Double
            switch kind {
            case .inPhase: right = s
            case .quadrature: right = amplitude * cos(phase)
            case .antiPhase: right = -s
            case .leftOnly: right = 0
            }
            out[2 * i] = Float(left)
            out[2 * i + 1] = Float(right)
        }
        return out
    }

    static func silence() -> [Float] { [Float](repeating: 0, count: 2 * frames) }
}

/// Principal-axis metrics of a point set (covariance eigenvalues), used to tell a line from a circle.
struct ShapeMetrics: Equatable {
    var major: Double
    var minor: Double
    /// Direction of the major axis in radians (−π/2…π/2], in the normalized (u, v) plane.
    var angle: Double
    var meanRadius: Double
    var radiusSpread: Double

    /// sqrt(λmin / λmax): ≈ 0 for a line, ≈ 1 for a circle.
    var axisRatio: Double { major > 0 ? (minor / major).squareRoot() : 0 }

    init(points: [(u: Double, v: Double)]) {
        let n = Double(points.count)
        let mu: Double = points.reduce(0) { (s: Double, p: (u: Double, v: Double)) -> Double in s + p.u } / n
        let mv: Double = points.reduce(0) { (s: Double, p: (u: Double, v: Double)) -> Double in s + p.v } / n
        var suu = 0.0, svv = 0.0, suv = 0.0
        for p in points {
            let du: Double = p.u - mu, dv: Double = p.v - mv
            suu += du * du; svv += dv * dv; suv += du * dv
        }
        suu /= n; svv /= n; suv /= n
        let trace: Double = suu + svv
        let det: Double = suu * svv - suv * suv
        let disc: Double = max(trace * trace / 4 - det, 0).squareRoot()
        major = trace / 2 + disc
        minor = max(trace / 2 - disc, 0)
        angle = 0.5 * atan2(2 * suv, suu - svv)
        let radii: [Double] = points.map { (p: (u: Double, v: Double)) -> Double in ((p.u - mu) * (p.u - mu) + (p.v - mv) * (p.v - mv)).squareRoot() }
        let mean: Double = radii.reduce(0, +) / n
        let variance: Double = radii.reduce(0) { (s: Double, r: Double) -> Double in s + (r - mean) * (r - mean) } / n
        meanRadius = mean
        radiusSpread = mean > 0 ? variance.squareRoot() / mean : 0
    }

    init(layout: LissajousLayout) {
        self.init(points: (0..<layout.pointCount).map { (j: Int) -> (u: Double, v: Double) in layout.normalizedPoint(j) })
    }
}

extension LissajousLayout {
    func layout(_ history: [Float], frameDuration: Double = 1.0 / 60, width: Int = 256, height: Int = 192) {
        history.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            layout(stereo: b, frameDuration: frameDuration, width: width, height: height)
        }
    }

    func vertexCount() -> Int {
        let out = UnsafeMutablePointer<SpectrumVertex>.allocate(capacity: Self.maximumVertexCount)
        defer { out.deallocate() }
        return tessellate(into: out, capacity: Self.maximumVertexCount, gain: 1)
    }
}
