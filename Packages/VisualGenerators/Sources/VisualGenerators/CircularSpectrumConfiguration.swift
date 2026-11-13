// CircularSpectrumConfiguration.swift — the circular spectrum's parameters (VIS-001-R3, R4;
// data-model.md).
//
// Angles are degrees, measured clockwise from the top of the output (12 o'clock). Bar k's centre is
// θ(k) = start + d·(k + 0.5)·360/N + rotation offset, d = +1 clockwise, −1 counter-clockwise; each
// bar spans (1 − gap)·360/N. Radii are in radius units (half the output's shorter side, VIS-001-R5).
// `init` clamps; properties set later are clamped by `clamped()`, which every consumer applies.

/// The bar counts offered: ANL-002's band counts (VIS-001-R2).
public enum SpectrumBarCount: Int, CaseIterable, Sendable, Hashable {
    case b16 = 16
    case b32 = 32
    case b64 = 64
    case b128 = 128

    public static let maximum = 128
}

public enum RingDirection: Sendable, Hashable {
    case clockwise
    case counterClockwise

    var sign: Double { self == .clockwise ? 1 : -1 }
}

public struct CircularSpectrumConfiguration: Sendable, Equatable {
    public static let innerRadiusRange: ClosedRange<Double> = 0.05...0.9
    public static let gapRange: ClosedRange<Double> = 0...0.9
    static let defaultInnerRadius = 0.3
    static let defaultLengthScale = 0.65
    static let defaultGap = 0.2

    public var barCount: SpectrumBarCount
    /// Radius units, 0.05…0.9.
    public var innerRadius: Double
    /// Radius units a full band (value 1) adds to the inner radius, 0…(1 − innerRadius).
    public var lengthScale: Double
    /// Fraction of a bar's angular pitch left empty, 0…0.9.
    public var gap: Double
    public var rotationOffsetDegrees: Double
    public var startAngleDegrees: Double
    public var direction: RingDirection
    public var palette: VisualPalette
    /// Premultiplied, linear.
    public var background: LinearColor

    public init(barCount: SpectrumBarCount = .b64, innerRadius: Double = 0.3, lengthScale: Double = 0.65,
                gap: Double = 0.2, rotationOffsetDegrees: Double = 0, startAngleDegrees: Double = 0,
                direction: RingDirection = .clockwise, palette: VisualPalette = .spectrum,
                background: LinearColor = .opaqueBlack) {
        self.barCount = barCount
        self.innerRadius = innerRadius
        self.lengthScale = lengthScale
        self.gap = gap
        self.rotationOffsetDegrees = rotationOffsetDegrees
        self.startAngleDegrees = startAngleDegrees
        self.direction = direction
        self.palette = palette
        self.background = background
        self = clamped()
    }

    /// Every value in its documented range; non-finite values take their defaults (0 for angles).
    public func clamped() -> CircularSpectrumConfiguration {
        var c = self
        func clamp(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            v.isFinite ? min(max(v, range.lowerBound), range.upperBound) : fallback
        }
        c.innerRadius = clamp(innerRadius, Self.innerRadiusRange, Self.defaultInnerRadius)
        c.lengthScale = clamp(lengthScale, 0...(1 - c.innerRadius), min(Self.defaultLengthScale, 1 - c.innerRadius))
        c.gap = clamp(gap, Self.gapRange, Self.defaultGap)
        c.rotationOffsetDegrees = rotationOffsetDegrees.isFinite ? rotationOffsetDegrees : 0
        c.startAngleDegrees = startAngleDegrees.isFinite ? startAngleDegrees : 0
        c.background = background.clamped
        return c
    }

    /// 360/N.
    public var pitchDegrees: Double { 360 / Double(barCount.rawValue) }
    /// Half the arc a bar covers: (1 − gap)·pitch/2.
    public var halfWidthDegrees: Double { (1 - gap) * pitchDegrees / 2 }

    /// θ(k) in [0, 360).
    public func centerDegrees(ofBar k: Int) -> Double {
        let raw = startAngleDegrees + direction.sign * (Double(k) + 0.5) * pitchDegrees + rotationOffsetDegrees
        let r = raw.truncatingRemainder(dividingBy: 360)
        let v = r < 0 ? r + 360 : r
        return v >= 360 ? 0 : v
    }
}
