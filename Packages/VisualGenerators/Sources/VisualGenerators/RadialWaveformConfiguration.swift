// RadialWaveformConfiguration.swift — the radial waveform's parameters (VIS-005-R2, R6, R7; data-model.md;
// research VIS-005-D4, D5).
//
// `init` clamps; properties set later are clamped by `clamped()`, which every consumer applies. Non-finite
// values take their defaults. Radii are fractions of half the output's shorter side: with R₀ in 0.2…0.75 and
// A in 0…0.25, every radius R₀ + A·s (s in −1…1) stays within 0…1, so the ring never leaves the picture.

public struct RadialWaveformConfiguration: Sendable, Equatable {
    public static let baseRadiusRange: ClosedRange<Double> = 0.2...0.75
    public static let amplitudeRange: ClosedRange<Double> = 0...0.25
    public static let thicknessRange: ClosedRange<Double> = 0.001...0.05
    public static let defaultBaseRadius = 0.55
    public static let defaultAmplitude = 0.18
    public static let defaultLineThickness = 0.006

    /// R₀: the ring's radius at silence, as a fraction of half the shorter side.
    public var baseRadius: Double
    /// A: how far a full-scale sample moves the ring, same unit.
    public var amplitude: Double
    /// Fraction of the output's shorter side (at least 1 px drawn).
    public var lineThickness: Double
    public var palette: VisualPalette
    /// Premultiplied, linear.
    public var background: LinearColor

    public init(baseRadius: Double = RadialWaveformConfiguration.defaultBaseRadius,
                amplitude: Double = RadialWaveformConfiguration.defaultAmplitude,
                lineThickness: Double = RadialWaveformConfiguration.defaultLineThickness,
                palette: VisualPalette = .spectrum, background: LinearColor = .opaqueBlack) {
        self.baseRadius = baseRadius
        self.amplitude = amplitude
        self.lineThickness = lineThickness
        self.palette = palette
        self.background = background
        self = clamped()
    }

    /// Every value in its documented range.
    public func clamped() -> RadialWaveformConfiguration {
        var c = self
        c.baseRadius = Self.clamp(baseRadius, Self.baseRadiusRange, Self.defaultBaseRadius)
        c.amplitude = Self.clamp(amplitude, Self.amplitudeRange, Self.defaultAmplitude)
        c.lineThickness = Self.clamp(lineThickness, Self.thicknessRange, Self.defaultLineThickness)
        c.background = background.clamped
        return c
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
