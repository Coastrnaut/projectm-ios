// ToneMap.swift — the plain-Swift reference of the FX-002 output tone map (FX-002-R2 to R5, R8;
// specs/122-fx-002-tone-mapping/contracts/tone-map.md; research FX-002-D1, D2; ADR-0047). CPU only, builds
// on Linux. The compositor's `cmp_tone_map` shader follows the same steps in float; tests compare the two.
//
// Per pixel (linear premultiplied in, display range out):
//   1. sanitise: a colour channel that is NaN, ±Inf or negative becomes 0; alpha NaN/±Inf becomes 0, then
//      alpha is clamped to 0…1;
//   2. m = max(r, g, b) ≤ 1: unchanged (every in-range pixel is bit-identical);
//   3. Y = 0.2126 r + 0.7152 g + 0.0722 b ≥ 1: white;
//   4. otherwise s = (1 − Y) / (m − Y) and rgb = clamp(Y + s·(c − Y), 0, 1): the line from the pixel's grey
//      toward the pixel, cut where the largest channel reaches 1. Luminance (weights sum to 1) and hue are
//      kept; only saturation drops. m > 1 > Y, so m − Y > 0. Computed as the equal 1 − s·(m − c), which is
//      exactly 1 for the largest channel, so rounding never dips below the identity branch's 1.
// Monotonic along every ray of finite colours, output luminance = min(Y, 1) (proof: research FX-002-D2).
// Every expression is split into typed steps (the type checker on Linux and Xcode 26).

public enum ToneMap {
    /// Linear premultiplied RGBA (any values on input).
    public typealias Pixel = SIMD4<Double>

    /// Rec. 709 / WCAG relative luminance weights (as FX-019's flash guard).
    public static let luminanceWeights: SIMD3<Double> = SIMD3<Double>(0.2126, 0.7152, 0.0722)

    /// Whether any channel is NaN or infinite (what the screen output pass counts, FX-002-R7).
    public static func isNonFinite(_ p: Pixel) -> Bool {
        for c in 0..<4 where !p[c].isFinite { return true }
        return false
    }

    /// Step 1: non-finite or negative colour channels → 0; alpha non-finite → 0, then clamped to 0…1.
    public static func sanitize(_ p: Pixel) -> Pixel {
        var out: Pixel = .zero
        for c in 0..<3 {
            let v: Double = p[c]
            out[c] = v.isFinite && v > 0 ? v : 0
        }
        let a: Double = p[3].isFinite ? p[3] : 0
        out[3] = min(max(a, 0), 1)
        return out
    }

    /// The luminance of the colour channels.
    public static func luminance(_ p: Pixel) -> Double {
        let r: Double = luminanceWeights.x * p.x
        let g: Double = luminanceWeights.y * p.y
        let b: Double = luminanceWeights.z * p.z
        return r + g + b
    }

    /// The display pixel for a composite pixel (steps 1-4). Colour and alpha in 0…1, never NaN.
    public static func map(_ input: Pixel) -> Pixel {
        let s: Pixel = sanitize(input)
        let m: Double = max(s.x, max(s.y, s.z))
        if m <= 1 { return s }
        let y: Double = luminance(s)
        if y >= 1 { return Pixel(1, 1, 1, s.w) }
        let room: Double = 1 - y
        let spread: Double = m - y
        let k: Double = room / spread
        var out: Pixel = s
        for c in 0..<3 {
            // y + k·(c − y) = 1 − k·(m − c): exactly 1 for the largest channel (as the shader computes it).
            let gap: Double = m - s[c]
            let v: Double = 1 - k * gap
            out[c] = min(max(v, 0), 1)
        }
        return out
    }
}
