// BloomPlan.swift — the bloom's working sizes and blur kernel for one output size (FX-001-R7 a, R14,
// R15; research FX-001-D3 steps 2-3; data-model.md).
//
// r = radius · min(W, H) pixels. The thresholded image is reduced by D, the smallest of 2, 4, 8 with
// ⌈r / D⌉ ≤ 16 (else 8); the blur radius is R = clamp(round(r / D), 1, 16) reduced texels with a
// normalized Gaussian, σ = R / 2, taps −R…R. Halo extent: E = (R + 2) · D pixels (Chebyshev
// distance from the nearest contributing pixel; derivation in research FX-001-D3).
// Computed when the size or the parameters change, never per frame.
//
// PERF-003 (research PERF-003-D2): `quality` .reduced derives (D', R') from Full's (D, R) and halo E: when
// D' = 2D ≤ 8 and r = min(⌈R/2⌉, ⌊E/D'⌋ − 2) ≥ 1 it takes (2D, r), else (D, ⌈R/2⌉). Either way R' ≤ ⌈R/2⌉ and
// E' = (R' + 2)·D' ≤ E, so the FX-019 area model and `BloomLuminanceModel` (both computed for Full) stay upper
// bounds. .full and .minimal are Full's plan (Minimal is skipped by `BloomEffect`, never encoded).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public struct BloomPlan: Sendable, Equatable {
    public static let maxTapsPerSide = 16
    public static let downsampleFactors = [2, 4, 8]

    public let width: Int
    public let height: Int
    /// D.
    public let downsample: Int
    /// R, in reduced texels.
    public let blurRadius: Int
    public let reducedWidth: Int
    public let reducedHeight: Int
    /// The half kernel: weights[0] for the centre, weights[i] for ±i; w0 + 2·Σ = 1.
    public let weights: [Float]

    /// E = (R + 2) · D pixels.
    public var haloExtent: Int { (blurRadius + 2) * downsample }

    /// Texel reads of the two blur passes: reduced texels × (2R + 1) × 2 (PERF-003-S2).
    public var blurWork: Int { reducedWidth * reducedHeight * (2 * blurRadius + 1) * 2 }

    /// D and R for an output size at a quality level (no allocation).
    static func sizes(parameters: BloomParameters, width: Int, height: Int,
                      quality: EffectQualityLevel) -> (downsample: Int, blurRadius: Int) {
        let (d, r) = sizes(parameters: parameters, width: width, height: height)
        guard quality == .reduced else { return (d, r) }
        let half = (r + 1) / 2
        let extent = (r + 2) * d
        let coarser = 2 * d
        if coarser <= 8 {
            let fitting = min(half, extent / coarser - 2)
            if fitting >= 1 { return (coarser, fitting) }
        }
        return (d, half)
    }

    /// D and R for an output size (no allocation).
    static func sizes(parameters: BloomParameters, width: Int, height: Int) -> (downsample: Int, blurRadius: Int) {
        let pixels = Double(parameters.clamped().radius) * Double(min(max(width, 1), max(height, 1)))
        var d = 2   // the first of 2, 4, 8 whose radius fits, else 8 (downsampleFactors)
        while d < 8 && Int((pixels / Double(d)).rounded(.up)) > maxTapsPerSide { d *= 2 }
        let r = min(max(Int((pixels / Double(d)).rounded()), 1), maxTapsPerSide)
        return (d, r)
    }

    /// E for an output size without building the plan (FX-019's area model; no allocation).
    public static func haloExtent(parameters: BloomParameters, width: Int, height: Int) -> Int {
        let (d, r) = sizes(parameters: parameters, width: width, height: height)
        return (r + 2) * d
    }

    public init(parameters: BloomParameters, width: Int, height: Int, quality: EffectQualityLevel = .full) {
        let w = max(width, 1), h = max(height, 1)
        self.width = w
        self.height = h
        let (d, r) = Self.sizes(parameters: parameters, width: w, height: h, quality: quality)
        downsample = d
        blurRadius = r
        reducedWidth = (w + d - 1) / d
        reducedHeight = (h + d - 1) / d
        let sigma = Double(r) / 2
        var raw = (0...r).map { i in exp(-Double(i * i) / (2 * sigma * sigma)) }
        let sum = raw[0] + 2 * raw.dropFirst().reduce(0, +)
        raw = raw.map { $0 / sum }
        weights = raw.map(Float.init)
    }
}
