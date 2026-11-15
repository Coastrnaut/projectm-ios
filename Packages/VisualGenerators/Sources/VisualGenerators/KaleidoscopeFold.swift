// KaleidoscopeFold.swift — the kaleidoscope's wedge fold, shared by the noise field's shader and its flash estimate
// (VIS-014-R3, R4, R6; specs/259-vis-014-kaleidoscope-field, research VIS-014-D2, D3; contract K1-K3).
//
// A point p (relative to the frame centre) is folded into the first half-wedge: θ = atan2(p) − rotation,
// w = 2π / N, a = θ − w · floor(θ / w) ∈ [0, w), φ = |a − w / 2| ∈ [0, w / 2], folded = |p| · (cos φ, sin φ).
// φ is continuous in θ (both ends of a wedge map to w / 2, its centre line to 0), 2π is a whole number of wedges so
// atan2's ±π cut never shows, and the origin maps to itself: no seam anywhere. Rotating by w or mirroring across a
// wedge boundary or centre line leaves φ unchanged, so the picture has N rotations and N mirror axes for every N ≥ 2.
// `KaleidoscopeFoldShader.function` is the same operations in Metal. Plain Swift; builds on Linux.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public struct KaleidoscopeFold: Sendable, Equatable {
    /// Wedge counts offered (VIS-014-R4); below 2 the fold is the identity.
    public static let wedgeRange: ClosedRange<Int> = 2...24
    public static let defaultWedges = 6
    /// Turning, rad/s: base plus `bassSpin` × the low group, never above `maximumSpin` (VIS-014-R5).
    public static let baseSpin = 0.1
    public static let bassSpin = 0.3
    public static let maximumSpin = 0.4
    /// ACC-001: turning factor under Reduce Motion (VIS-014-R8).
    public static let reduceMotionScale = 0.5

    public var wedges: Int
    /// Radians, counter-clockwise in the shader's pixel frame.
    public var rotation: Float

    public init(wedges: Int, rotation: Float = 0) {
        self.wedges = wedges
        self.rotation = rotation
    }

    /// The turning speed target (rad/s) for a low group `low` (0…1; anything else clamped, non-finite → 0).
    public static func spinTarget(low: Double, reduceMotion: Bool) -> Double {
        let l: Double = low.isFinite ? min(max(low, 0), 1) : 0
        let spin: Double = min(baseSpin + bassSpin * l, maximumSpin)
        return reduceMotion ? spin * reduceMotionScale : spin
    }

    /// The folded point of `p` (`vis_kfold`).
    public func fold(_ p: SIMD2<Float>) -> SIMD2<Float> {
        guard wedges >= 2 else { return p }
        let w: Float = 2 * Float.pi / Float(wedges)
        let r: Float = (p.x * p.x + p.y * p.y).squareRoot()
        let theta: Float = atan2f(p.y, p.x) - rotation
        let a: Float = theta - w * (theta / w).rounded(.down)
        let phi: Float = abs(a - 0.5 * w)
        return SIMD2<Float>(r * cosf(phi), r * sinf(phi))
    }
}

/// The GPU side of `KaleidoscopeFold`: Metal Shading Language authored in this module (no external code; SHD-011).
public enum KaleidoscopeFoldShader {
    /// `vis_kfold(p, wedges, rotation)`, operation for operation as `KaleidoscopeFold.fold`.
    public static let function = """
    static float2 vis_kfold(float2 p, float wedges, float rotation) {
        if (wedges < 1.5) return p;
        float w = 6.28318530717958647692 / wedges;
        float r = length(p);
        float theta = atan2(p.y, p.x) - rotation;
        float a = theta - w * floor(theta / w);
        float phi = abs(a - 0.5 * w);
        return r * float2(cos(phi), sin(phi));
    }

    """
}
