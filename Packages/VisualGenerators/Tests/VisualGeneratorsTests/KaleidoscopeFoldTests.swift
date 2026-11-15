// KaleidoscopeFoldTests.swift — VIS-014-T02 (VIS-014-R3, R4, R6; contract K1-K3; research VIS-014-D2): the shared fold
// on the CPU. Below 2 wedges it is the identity; it never moves two nearby points apart (1-Lipschitz), in particular
// across every wedge boundary, every centre line and atan2's ±π cut, so no seam can come from it; rotating by 2π/N or
// mirroring across a wedge axis gives the same folded point; the shader text is the same operations. Pure Swift.
import XCTest
@testable import VisualGenerators

final class KaleidoscopeFoldTests: XCTestCase {
    private static let counts: [Int] = [2, 5, 6, 24]

    private static func point(_ r: Float, _ angle: Float) -> SIMD2<Float> { SIMD2(r * cos(angle), r * sin(angle)) }

    private static func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let d: SIMD2<Float> = a - b
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    func testBelowTwoWedgesTheFoldIsTheIdentity() {
        let p = SIMD2<Float>(0.3, -0.2)
        XCTAssertEqual(KaleidoscopeFold(wedges: 0, rotation: 1).fold(p), p)
        XCTAssertEqual(KaleidoscopeFold(wedges: 1).fold(p), p)
        XCTAssertEqual(KaleidoscopeFold(wedges: 6).fold(.zero), .zero, "the centre maps to itself")
    }

    func testTheFoldIsContinuousAcrossEveryBoundaryAxisAndTheAngleCut() {
        let epsilon: Float = 1e-3
        for n in Self.counts {
            for rotation: Float in [0, 0.37, -2.1] {
                let fold = KaleidoscopeFold(wedges: n, rotation: rotation)
                var angles: [Float] = (0..<(2 * n)).map { (k: Int) -> Float in rotation + Float(k) * Float.pi / Float(n) }
                angles += [Float.pi, -Float.pi + 1e-4]
                for alpha in angles {
                    for r: Float in [0.01, 0.2, 0.5] {
                        let a: SIMD2<Float> = Self.point(r, alpha - epsilon / r), b: SIMD2<Float> = Self.point(r, alpha + epsilon / r)
                        let moved: Float = Self.distance(fold.fold(a), fold.fold(b))
                        XCTAssertLessThanOrEqual(moved, Self.distance(a, b) + 1e-5, "N \(n), rotation \(rotation), angle \(alpha), r \(r)")
                    }
                }
            }
        }
    }

    func testRotationByAWedgeAndMirrorsAcrossItsAxesGiveTheSameFoldedPoint() {
        for n in Self.counts {
            let rotation: Float = 0.61
            let fold = KaleidoscopeFold(wedges: n, rotation: rotation)
            let w: Float = 2 * Float.pi / Float(n)
            for (r, theta) in [(Float(0.31), Float(0.2)), (0.12, 2.9), (0.47, -1.3)] {
                let base: SIMD2<Float> = fold.fold(Self.point(r, theta))
                XCTAssertLessThan(Self.distance(fold.fold(Self.point(r, theta + w)), base), 1e-4, "N \(n): rotation")
                for axis: Float in [rotation, rotation + w / 2, rotation + 3 * w / 2] {
                    XCTAssertLessThan(Self.distance(fold.fold(Self.point(r, 2 * axis - theta)), base), 1e-4, "N \(n): mirror at \(axis)")
                }
                XCTAssertEqual(Self.distance(base, .zero), r, accuracy: 1e-5, "the fold keeps the radius")
                let phi: Float = atan2(base.y, base.x)
                XCTAssertTrue(phi >= -1e-5 && phi <= w / 2 + 1e-5, "N \(n): into the first half-wedge")
            }
        }
        // A different count is a different symmetry.
        let six = KaleidoscopeFold(wedges: 6), p: SIMD2<Float> = Self.point(0.3, 0.2)
        XCTAssertGreaterThan(Self.distance(six.fold(Self.point(0.3, 0.2 + 2 * Float.pi / 5)), six.fold(p)), 0.01)
    }

    func testTheShaderTextIsTheSameOperations() {
        let text: String = KaleidoscopeFoldShader.function
        for fragment in ["float2 vis_kfold(float2 p, float wedges, float rotation)", "if (wedges < 1.5) return p;",
                         "atan2(p.y, p.x) - rotation", "theta - w * floor(theta / w)", "abs(a - 0.5 * w)",
                         "r * float2(cos(phi), sin(phi))"] {
            XCTAssertTrue(text.contains(fragment), fragment)
        }
        #if canImport(Metal) && !VISUAL_NO_METAL
        XCTAssertTrue(NoiseFieldGenerator.shaderSource.contains(text), "the generator's shader is built from the shared text")
        #endif
    }

    func testConfigurationClampsWedges() {
        XCTAssertEqual(NoiseFieldConfiguration().wedges, 0)
        XCTAssertFalse(NoiseFieldConfiguration().isKaleidoscope)
        XCTAssertEqual(NoiseFieldConfiguration(wedges: 1).wedges, 0)
        XCTAssertEqual(NoiseFieldConfiguration(wedges: 40).wedges, 24)
        XCTAssertEqual(NoiseFieldConfiguration.kaleidoscope(wedges: 0).wedges, 2)
        XCTAssertEqual(NoiseFieldConfiguration.kaleidoscope().wedges, 6)
        let k = NoiseFieldConfiguration.kaleidoscope(wedges: 9)
        XCTAssertEqual(k.frequency, 4)
        XCTAssertEqual(k.octaves, 4)
        XCTAssertEqual(k.seed, 1301)
        XCTAssertTrue(k.isKaleidoscope)
    }
}
