// GeometryTestSupport.swift — test-only oracle for VIS-001 (VIS-001-T03): the bar angle formula of
// VIS-001-R3 and the screen mapping of VIS-001-R5, recomputed in Double without calling
// `CircularSpectrumLayout`, plus the output sizes and rotation offsets of the acceptance matrix.
// No Metal, Accelerate or UIKit here (runs on Linux).
import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum GeometryOracle {
    /// Portrait iPhone, landscape iPhone, portrait and landscape iPad Pro 13", portrait iPad 11"
    /// (VIS-001 User Story 3).
    static let sizes: [(width: Int, height: Int)] = [(1179, 2556), (2556, 1179), (2064, 2752), (2752, 2064), (1640, 2360)]
    static let offsets: [Double] = [-90, 0, 37.5, 90, 180, 450]
    static let barCounts = [16, 32, 64, 128]

    /// θ(k) = start + d·(k + 0.5)·360/N + offset, reduced to [0, 360).
    static func angle(bar k: Int, count n: Int, start: Double = 0, clockwise: Bool = true, offset: Double = 0) -> Double {
        let d: Double = clockwise ? 1 : -1
        return normalized(start + d * (Double(k) + 0.5) * 360 / Double(n) + offset)
    }

    static func normalized(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Smallest absolute difference between two angles, in degrees (0…180).
    static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(normalized(a) - normalized(b))
        return min(d, 360 - d)
    }

    /// Angle (clockwise from up, degrees) and radius (pixels) of a pixel position relative to the
    /// output's centre (y grows downward).
    static func polar(x: Double, y: Double, width: Int, height: Int) -> (angle: Double, radius: Double) {
        let dx = x - Double(width) / 2
        let dy = Double(height) / 2 - y
        return (normalized(atan2(dx, dy) * 180 / .pi), (dx * dx + dy * dy).squareRoot())
    }

    /// NDC (x right, y up, −1…1) back to pixels (y down).
    static func pixel(ndcX: Float, ndcY: Float, width: Int, height: Int) -> (x: Double, y: Double) {
        ((Double(ndcX) + 1) / 2 * Double(width), (1 - Double(ndcY)) / 2 * Double(height))
    }

    static func impulse(at k: Int, count n: Int, value: Float = 1) -> [Float] {
        var v = [Float](repeating: 0, count: n)
        v[k] = value
        return v
    }
}
