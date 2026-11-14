// OscilloscopeConfiguration.swift — the oscilloscope's parameters (VIS-003-R6 to R8; data-model.md).
//
// `init` clamps; properties set later are clamped by `clamped()`, which every consumer applies.
// Non-finite values take their defaults.

public struct OscilloscopeConfiguration: Sendable, Equatable {
    /// The analysis tap's rate (the normalized ring's 44.1 kHz).
    public static let sampleRate = 44_100.0
    public static let windowRange: ClosedRange<Double> = 5...40
    public static let thicknessRange: ClosedRange<Double> = 0.001...0.05
    public static let amplitudeRange: ClosedRange<Double> = 0.1...1
    public static let defaultWindowMilliseconds = 20.0
    public static let defaultLineThickness = 0.008
    public static let defaultAmplitude = 0.9

    /// Time shown across the width, 5…40 ms (the app offers 10, 20 and 40).
    public var windowMilliseconds: Double
    /// Line thickness as a fraction of the output's shorter side, 0.001…0.05 (at least 1 px drawn).
    public var lineThickness: Double
    /// Fraction of the half height a full-scale sample (±1) reaches, 0.1…1.
    public var amplitude: Double
    public var palette: VisualPalette
    /// Premultiplied, linear.
    public var background: LinearColor

    public init(windowMilliseconds: Double = OscilloscopeConfiguration.defaultWindowMilliseconds,
                lineThickness: Double = OscilloscopeConfiguration.defaultLineThickness,
                amplitude: Double = OscilloscopeConfiguration.defaultAmplitude,
                palette: VisualPalette = .spectrum, background: LinearColor = .opaqueBlack) {
        self.windowMilliseconds = windowMilliseconds
        self.lineThickness = lineThickness
        self.amplitude = amplitude
        self.palette = palette
        self.background = background
        self = clamped()
    }

    /// Every value in its documented range; non-finite values take their defaults.
    public func clamped() -> OscilloscopeConfiguration {
        var c = self
        func clamp(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            v.isFinite ? min(max(v, range.lowerBound), range.upperBound) : fallback
        }
        c.windowMilliseconds = clamp(windowMilliseconds, Self.windowRange, Self.defaultWindowMilliseconds)
        c.lineThickness = clamp(lineThickness, Self.thicknessRange, Self.defaultLineThickness)
        c.amplitude = clamp(amplitude, Self.amplitudeRange, Self.defaultAmplitude)
        c.background = background.clamped
        return c
    }

    /// Samples shown: 441, 882 or 1,764 for 10, 20 or 40 ms.
    public var windowSamples: Int {
        let samples: Double = windowMilliseconds * Self.sampleRate / 1_000
        return Int(samples.rounded())
    }
}
