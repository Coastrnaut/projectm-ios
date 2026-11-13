// LinearSpectrumConfiguration.swift — the linear spectrum's parameters (VIS-002-R3 to R6;
// data-model.md).
//
// Lengths are fractions of the output's length axis L (its height for vertical bars, its width for
// horizontal ones); spacing is a fraction of a bar's slot on the cross axis. `init` clamps;
// properties set later are clamped by `clamped()`, which every consumer applies. Non-finite values
// take their defaults.

/// Which way the bars grow, relative to the output (the screen as currently held; VIS-002-R3).
public enum LinearSpectrumOrientation: String, CaseIterable, Sendable, Hashable {
    /// Bars rise from the bottom edge; band 0 at the left. Default.
    case vertical
    /// Bars grow from the left edge; band 0 at the top.
    case horizontal
}

public struct LinearSpectrumConfiguration: Sendable, Equatable {
    public static let spacingRange: ClosedRange<Double> = 0...0.9
    public static let capThicknessRange: ClosedRange<Double> = 0...0.05
    public static let peakHoldRange: ClosedRange<Double> = 0...5
    public static let peakFallRange: ClosedRange<Double> = 0.1...10
    public static let defaultSpacing = 0.2
    public static let defaultCapThickness = 0.015
    public static let defaultLengthScale = 0.9
    public static let defaultPeakHoldSeconds = 0.5
    public static let defaultPeakFallPerSecond = 1.0

    public var barCount: SpectrumBarCount
    public var orientation: LinearSpectrumOrientation
    /// Fraction of a slot left empty, 0…0.9 (half on each side of the bar).
    public var spacing: Double
    /// Cap thickness t as a fraction of L, 0…0.05 (0: no caps).
    public var capThickness: Double
    /// λ: the length of a full band (value 1) as a fraction of L, 0…(1 − t).
    public var lengthScale: Double
    /// How long a cap stays at its peak, 0…5 s of frame time.
    public var peakHoldSeconds: Double
    /// How fast a cap falls after the hold, 0.1…10 bar lengths per second of frame time.
    public var peakFallPerSecond: Double
    public var palette: VisualPalette
    /// Premultiplied, linear.
    public var background: LinearColor

    public init(barCount: SpectrumBarCount = .b64, orientation: LinearSpectrumOrientation = .vertical,
                spacing: Double = LinearSpectrumConfiguration.defaultSpacing,
                capThickness: Double = LinearSpectrumConfiguration.defaultCapThickness,
                lengthScale: Double = LinearSpectrumConfiguration.defaultLengthScale,
                peakHoldSeconds: Double = LinearSpectrumConfiguration.defaultPeakHoldSeconds,
                peakFallPerSecond: Double = LinearSpectrumConfiguration.defaultPeakFallPerSecond,
                palette: VisualPalette = .spectrum, background: LinearColor = .opaqueBlack) {
        self.barCount = barCount
        self.orientation = orientation
        self.spacing = spacing
        self.capThickness = capThickness
        self.lengthScale = lengthScale
        self.peakHoldSeconds = peakHoldSeconds
        self.peakFallPerSecond = peakFallPerSecond
        self.palette = palette
        self.background = background
        self = clamped()
    }

    /// Every value in its documented range; non-finite values take their defaults.
    public func clamped() -> LinearSpectrumConfiguration {
        var c = self
        func clamp(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            v.isFinite ? min(max(v, range.lowerBound), range.upperBound) : fallback
        }
        c.spacing = clamp(spacing, Self.spacingRange, Self.defaultSpacing)
        c.capThickness = clamp(capThickness, Self.capThicknessRange, Self.defaultCapThickness)
        c.lengthScale = clamp(lengthScale, 0...(1 - c.capThickness), min(Self.defaultLengthScale, 1 - c.capThickness))
        c.peakHoldSeconds = clamp(peakHoldSeconds, Self.peakHoldRange, Self.defaultPeakHoldSeconds)
        c.peakFallPerSecond = clamp(peakFallPerSecond, Self.peakFallRange, Self.defaultPeakFallPerSecond)
        c.background = background.clamped
        return c
    }
}
