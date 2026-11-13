// BloomPlan.swift — the bloom's working sizes and blur kernel for one output size (FX-001-R7 a, R14,
// R15; research FX-001-D3 steps 2-3; data-model.md).
//
// r = radius · min(W, H) pixels. The thresholded image is reduced by D, the smallest of 2, 4, 8 with
// ⌈r / D⌉ ≤ 16 (else 8); the blur radius is R = clamp(round(r / D), 1, 16) reduced texels with a
// normalized Gaussian, σ = R / 2, taps −R…R. Halo extent: E = (R + 2) · D pixels (Chebyshev
// distance from the nearest contributing pixel; derivation in research FX-001-D3).
// Computed when the size or the parameters change, never per frame.
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

    public init(parameters: BloomParameters, width: Int, height: Int) {
        let w = max(width, 1), h = max(height, 1)
        self.width = w
        self.height = h
        let pixels = Double(parameters.clamped().radius) * Double(min(w, h))
        let d = Self.downsampleFactors.first { Int((pixels / Double($0)).rounded(.up)) <= Self.maxTapsPerSide }
            ?? Self.downsampleFactors[Self.downsampleFactors.count - 1]
        let r = min(max(Int((pixels / Double(d)).rounded()), 1), Self.maxTapsPerSide)
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
