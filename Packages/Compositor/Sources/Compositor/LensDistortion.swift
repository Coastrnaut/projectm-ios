// LensDistortion.swift — FX-016 "Lens distortion": the value, its ranges, the shader block and the CPU reference
// (specs/306-fx-016-lens-distortion, contracts/lens-distortion.md C2, research FX-016-D2 to D6; ADR-0117). Plain Swift
// (builds on Linux). The compositor's `cmp_lens_distortion` pass does the same per pixel on the GPU:
//   p = the pixel centre (x + ½, y + ½); d = p − centre (the frame's middle); r² = |d|² × 4 ÷ (W² + H²) (corners at 1);
//   f = (1 + k r²) × inverseZoom, k = 0.3 × strength, inverseZoom = 1 ÷ (1 + k) with zoom to fill and k > 0, else 1;
//   s = centre + d × f. Outside 0…W × 0…H (or not finite) → (0, 0, 0, 0); inside → bilinear of the four nearest pixels,
//   each tap clamped to the frame, and exactly the pixel when s is on its centre.
// |k| ≤ 0.3 < 1⁄3 keeps r ↦ r (1 + k r²) strictly increasing on 0…1 (no fold). At k = 0, f = 1 exactly, s = p and the
// output is the input bit for bit. Inactive (off, strength 0, or a frame under 2 pixels) runs no pass.
import Foundation

public struct LensDistortion: Sendable, Equatable, Codable {
    /// Signed amount: positive barrel, negative pincushion, 0 none.
    public static let strengthRange: ClosedRange<Double> = -1...1
    public static let defaultStrength = 0.3
    /// VoiceOver step (1 %).
    public static let strengthStep = 0.01
    /// The radial coefficient at strength ±1 (below the 1⁄3 at which pincushion would fold).
    public static let maxCoefficient = 0.3
    public static let defaultZoomToFill = true

    /// Off (the default; output bit-identical to before FX-016).
    public static let off = LensDistortion()

    public var isEnabled: Bool
    public var strength: Double
    /// Enlarges a barrel warp so every sample stays inside the picture (no effect on pincushion).
    public var zoomToFill: Bool

    public init(isEnabled: Bool = false, strength: Double = LensDistortion.defaultStrength,
                zoomToFill: Bool = LensDistortion.defaultZoomToFill) {
        self.isEnabled = isEnabled
        self.strength = strength
        self.zoomToFill = zoomToFill
    }

    /// A user value made valid.
    public var clamped: LensDistortion {
        LensDistortion(isEnabled: isEnabled, strength: Self.clampStrength(strength), zoomToFill: zoomToFill)
    }

    /// NaN → the default; out of range (±Inf) → the nearest bound.
    public static func clampStrength(_ value: Double) -> Double {
        if value.isNaN { return defaultStrength }
        return min(max(value, strengthRange.lowerBound), strengthRange.upperBound)
    }

    /// k = 0.3 × strength (0 when off).
    public var coefficient: Float {
        isEnabled ? Float(Self.maxCoefficient * Self.clampStrength(strength)) : 0
    }

    /// The compositor runs the pass: on, a non-zero coefficient, and at least 2 × 2 pixels.
    public func isActive(width: Int, height: Int) -> Bool {
        width >= 2 && height >= 2 && coefficient != 0
    }

    /// The shader block for a frame (`CMPLensDistortion`, 32 bytes).
    public func block(width: Int, height: Int) -> Block {
        let w = Float(max(width, 1)), h = Float(max(height, 1))
        let k: Float = coefficient
        let inverseZoom: Float = zoomToFill && k > 0 ? 1 / (1 + k) : 1
        return Block(centre: SIMD2<Float>(w / 2, h / 2), size: SIMD2<Float>(w, h),
                     inverseRadiusSquared: 4 / (w * w + h * h), coefficient: k, inverseZoom: inverseZoom, pad: 0)
    }

    /// `CMPLensDistortion` in the shader.
    public struct Block: Sendable, Equatable {
        public var centre: SIMD2<Float>
        public var size: SIMD2<Float>
        public var inverseRadiusSquared: Float
        public var coefficient: Float
        public var inverseZoom: Float
        public var pad: Float
    }

    // MARK: - CPU reference (contract C2)

    /// The picture radius shown at output radius r (both in half diagonals).
    public static func radialMap(_ r: Float, block: Block) -> Float {
        r * (1 + block.coefficient * r * r) * block.inverseZoom
    }

    /// Where output pixel (x, y) samples the picture (pixel units, pixel centres at i + ½), and whether that is inside
    /// the picture (0…W × 0…H, finite).
    public static func sample(x: Int, y: Int, block b: Block) -> (position: SIMD2<Float>, inside: Bool) {
        let d: SIMD2<Float> = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5) - b.centre
        let r2: Float = (d.x * d.x + d.y * d.y) * b.inverseRadiusSquared
        let f: Float = (1 + b.coefficient * r2) * b.inverseZoom
        let s: SIMD2<Float> = b.centre + d * f
        let inside: Bool = s.x >= 0 && s.x <= b.size.x && s.y >= 0 && s.y <= b.size.y
        return (s, inside)
    }

    /// The bilinear taps of an inside sample: (x0, y0), (x1, y1) clamped to the frame and the weights (fx, fy).
    public static func taps(_ s: SIMD2<Float>, width: Int, height: Int)
        -> (x0: Int, y0: Int, x1: Int, y1: Int, fx: Float, fy: Float) {
        let qx: Float = s.x - 0.5, qy: Float = s.y - 0.5
        let bx: Float = qx.rounded(.down), by: Float = qy.rounded(.down)
        let ix = Int(bx), iy = Int(by)
        return (min(max(ix, 0), width - 1), min(max(iy, 0), height - 1),
                min(max(ix + 1, 0), width - 1), min(max(iy + 1, 0), height - 1), qx - bx, qy - by)
    }

    private static func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
        a + (b - a) * t
    }

    /// One output pixel.
    public static func referencePixel(_ pixels: [SIMD4<Float>], width: Int, height: Int, x: Int, y: Int,
                                      block: Block) -> SIMD4<Float> {
        let (s, inside) = sample(x: x, y: y, block: block)
        guard inside else { return SIMD4<Float>(0, 0, 0, 0) }
        let t = taps(s, width: width, height: height)
        if t.fx == 0 && t.fy == 0 { return pixels[t.y0 * width + t.x0] }
        let top: SIMD4<Float> = mix(pixels[t.y0 * width + t.x0], pixels[t.y0 * width + t.x1], t.fx)
        let bottom: SIMD4<Float> = mix(pixels[t.y1 * width + t.x0], pixels[t.y1 * width + t.x1], t.fx)
        return mix(top, bottom, t.fy)
    }

    /// The whole frame through the warp (the input itself when inactive).
    public func reference(_ pixels: [SIMD4<Float>], width: Int, height: Int) -> [SIMD4<Float>] {
        guard isActive(width: width, height: height) else { return pixels }
        return Self.referenceAlways(pixels, width: width, height: height, block: block(width: width, height: height))
    }

    /// The whole frame through the warp with `block`, whatever the strength (tests: the warp at k = 0 is the identity).
    public static func referenceAlways(_ pixels: [SIMD4<Float>], width: Int, height: Int, block: Block) -> [SIMD4<Float>] {
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                out.append(referencePixel(pixels, width: width, height: height, x: x, y: y, block: block))
            }
        }
        return out
    }
}
