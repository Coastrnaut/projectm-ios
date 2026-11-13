// BloomParameters.swift — the bloom's controls, ranges and soft-knee threshold (FX-001-R3, R4, R6;
// research FX-001-D3 step 1, D5; data-model.md).
//
// The threshold works on a pixel's brightest linear channel b: with K = knee · threshold,
//   s = clamp(b − (T − K), 0, 2K);  s = s² / (4K + 1e-5);  w = max(s, b − T) / max(b, 1e-5)
// and the pixel contributes P = pixel · w (all four channels). For b ≤ T − K, w is exactly 0; above
// T + K it is exactly (b − T)/b; in between it rises smoothly. The shader in `BloomEffect` uses the
// same formula (`BloomEffect.shaderSource`, `fx_bloom_weight`).
import VisualGenerators

public struct BloomParameters: Sendable, Equatable, Codable {
    public static let intensityRange: ClosedRange<Float> = 0...1
    public static let radiusRange: ClosedRange<Float> = 0.005...0.06
    public static let thresholdRange: ClosedRange<Float> = 0.1...1
    public static let kneeRange: ClosedRange<Float> = 0...1
    public static let defaultIntensity: Float = 0.5
    public static let defaultRadius: Float = 0.02
    public static let defaultThreshold: Float = 0.7
    public static let defaultKnee: Float = 0.5
    /// Components above this are treated as this (keeps the glow finite for extended-range input).
    public static let maximumComponent: Float = 64

    /// Glow on. Off by default (Clarifications).
    public var enabled: Bool
    /// Strength of the added glow, 0…1 (1: a halo pixel can reach, never pass, its source).
    public var intensity: Float
    /// Spread, as a fraction of the output's shorter side, 0.005…0.06.
    public var radius: Float
    /// Brightest-channel level (linear, 0.1…1) where the glow starts.
    public var threshold: Float
    /// Soft knee width as a fraction of the threshold, 0…1.
    public var knee: Float

    public init(enabled: Bool = false, intensity: Float = defaultIntensity, radius: Float = defaultRadius,
                threshold: Float = defaultThreshold, knee: Float = defaultKnee) {
        self.enabled = enabled
        self.intensity = intensity
        self.radius = radius
        self.threshold = threshold
        self.knee = knee
    }

    @inline(__always)
    static func clamp(_ v: Float, _ range: ClosedRange<Float>, _ fallback: Float) -> Float {
        v.isNaN ? fallback : min(max(v, range.lowerBound), range.upperBound)
    }

    /// Every value in its range; NaN reads the default.
    public func clamped() -> BloomParameters {
        BloomParameters(enabled: enabled,
                        intensity: Self.clamp(intensity, Self.intensityRange, Self.defaultIntensity),
                        radius: Self.clamp(radius, Self.radiusRange, Self.defaultRadius),
                        threshold: Self.clamp(threshold, Self.thresholdRange, Self.defaultThreshold),
                        knee: Self.clamp(knee, Self.kneeRange, Self.defaultKnee))
    }

    /// Off, or on with intensity 0: the output is the input (FX-001-R8).
    public var isPassThrough: Bool {
        let c = clamped()
        return !c.enabled || c.intensity == 0
    }

    /// K = knee · threshold (of the clamped values).
    public var kneeWidth: Float {
        let c = clamped()
        return c.knee * c.threshold
    }

    /// The weight w ∈ 0…1 of a pixel whose brightest channel is `b`.
    public func contribution(ofMaxChannel b: Float) -> Float {
        let c = clamped()
        let brightness = b.isFinite ? min(max(b, 0), Self.maximumComponent) : 0
        let t = c.threshold
        let k = c.knee * t
        let low = t - k   // at or below: exactly 0
        var soft = min(max(brightness - low, 0), 2 * k)
        soft = soft * soft / (4 * k + 1e-5)
        let w = max(soft, brightness - t) / max(brightness, 1e-5)
        return min(max(w, 0), 1)
    }

    /// One component as the effect reads it: NaN, ∞ and negatives → 0, at most `maximumComponent`.
    @inline(__always)
    static func sanitized(_ v: Float) -> Float {
        v.isFinite ? min(max(v, 0), maximumComponent) : 0
    }

    /// P(color): what a pixel of this linear, premultiplied color contributes to the glow.
    public func thresholded(_ color: LinearColor) -> LinearColor {
        let r = Self.sanitized(color.red), g = Self.sanitized(color.green)
        let b = Self.sanitized(color.blue), a = Self.sanitized(color.alpha)
        let w = contribution(ofMaxChannel: max(r, max(g, b)))
        return LinearColor(red: r * w, green: g * w, blue: b * w, alpha: a * w)
    }

    // MARK: Codable (missing fields read the default; values are clamped)

    private enum CodingKeys: String, CodingKey { case enabled, intensity, radius, threshold, knee }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = BloomParameters(enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
                               intensity: try c.decodeIfPresent(Float.self, forKey: .intensity) ?? Self.defaultIntensity,
                               radius: try c.decodeIfPresent(Float.self, forKey: .radius) ?? Self.defaultRadius,
                               threshold: try c.decodeIfPresent(Float.self, forKey: .threshold) ?? Self.defaultThreshold,
                               knee: try c.decodeIfPresent(Float.self, forKey: .knee) ?? Self.defaultKnee).clamped()
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(intensity, forKey: .intensity)
        try c.encode(radius, forKey: .radius)
        try c.encode(threshold, forKey: .threshold)
        try c.encode(knee, forKey: .knee)
    }
}
