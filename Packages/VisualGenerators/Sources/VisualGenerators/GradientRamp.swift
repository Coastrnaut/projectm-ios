// GradientRamp.swift — SHD-005 multi-stop gradients with interpolation and alpha (SHD-005-R1, R2; research
// SHD-005-D3, D4; specs/236-shd-005-gradient-editor/contracts/gradient-stops.md G2).
//
// 2…8 stops (position 0…1, 8-bit sRGB colour, alpha 0…1), stable-sorted by position, and one interpolation mode.
// `color(at:)` is the CPU reference of the GPU evaluation in ProceduralMaterials (`mat_gradient` with a ramp) and the
// evaluation the native visuals use for a palette with stop detail. The segment rule is CMP-008's: before the first
// stop its value, at or after a stop that stop (equal positions: the later wins), else the fraction between the two
// neighbours. At a stop's position the result is that stop exactly, in every mode. Plain Swift; builds on Linux.

/// How colour blends between two stops; alpha always blends linearly (held in `step`).
public enum GradientInterpolation: String, Sendable, Hashable, CaseIterable {
    /// Linear light (the UIX-011 behaviour).
    case smooth
    /// The sRGB-encoded values blend, then decode.
    case srgb
    /// Each stop's colour holds until the next stop.
    case step

    /// The shader's mode number.
    public var shaderMode: Int32 {
        switch self {
        case .smooth: 0
        case .srgb: 1
        case .step: 2
        }
    }

    public var title: String {
        switch self {
        case .smooth: "Smooth"
        case .srgb: "sRGB"
        case .step: "Step"
        }
    }
}

/// One stop: where (0…1), which 8-bit sRGB colour and how opaque (0…1).
public struct GradientRampStop: Sendable, Hashable {
    public let position: Float
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: Float

    /// Clamps position and alpha to 0…1; a non-finite position reads 0 and a non-finite alpha 1.
    public init(position: Float, red: UInt8, green: UInt8, blue: UInt8, alpha: Float = 1) {
        self.position = position.isFinite ? min(max(position, 0), 1) : 0
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha.isFinite ? min(max(alpha, 0), 1) : 1
    }

    /// The colour decoded to linear light, with the stop's alpha (straight).
    public var linear: LinearColor {
        LinearColor(red: SRGB.decode(Float(red) / 255), green: SRGB.decode(Float(green) / 255),
                    blue: SRGB.decode(Float(blue) / 255), alpha: alpha)
    }

    /// The sRGB-encoded colour 0…1.
    public var encoded: SIMD3<Float> { SIMD3<Float>(Float(red) / 255, Float(green) / 255, Float(blue) / 255) }
}

/// A gradient of 2…8 stops; nil from `init?` outside that range.
public struct GradientRamp: Sendable, Hashable {
    public static let minimumStops = 2
    public static let maximumStops = 8

    /// Stable-sorted by position.
    public let stops: [GradientRampStop]
    public let interpolation: GradientInterpolation

    public init?(stops: [GradientRampStop], interpolation: GradientInterpolation = .smooth) {
        guard (Self.minimumStops...Self.maximumStops).contains(stops.count) else { return nil }
        let indexed: [(offset: Int, element: GradientRampStop)] = Array(stops.enumerated())
        let ordered = indexed.sorted { (a: (offset: Int, element: GradientRampStop), b: (offset: Int, element: GradientRampStop)) -> Bool in
            if a.element.position != b.element.position { return a.element.position < b.element.position }
            return a.offset < b.offset
        }
        self.stops = ordered.map { (entry: (offset: Int, element: GradientRampStop)) -> GradientRampStop in entry.element }
        self.interpolation = interpolation
    }

    /// The segment at `t`: the index of the last stop at or before `t` (−1 before the first) and the fraction.
    func segment(at t: Float) -> (index: Int, fraction: Float) {
        var index: Int = -1
        var i: Int = 0
        while i < stops.count, t >= stops[i].position {
            index = i
            i += 1
        }
        guard index >= 0, index < stops.count - 1 else { return (index, 0) }
        let a: Float = stops[index].position
        let b: Float = stops[index + 1].position
        let fraction: Float = (t - a) / (b - a)
        return (index, fraction)
    }

    /// The straight linear-light colour and alpha at `t` (NaN reads 0; clamped to 0…1).
    public func color(at t: Float) -> LinearColor {
        let clamped: Float = t.isNaN ? 0 : min(max(t, 0), 1)
        let (index, f) = segment(at: clamped)
        if index < 0 { return stops[0].linear }
        if index == stops.count - 1 || f <= 0 || interpolation == .step { return stops[index].linear }
        let a: GradientRampStop = stops[index]
        let b: GradientRampStop = stops[index + 1]
        let alpha: Float = a.alpha + (b.alpha - a.alpha) * f
        switch interpolation {
        case .smooth, .step:
            let la: LinearColor = a.linear
            let lb: LinearColor = b.linear
            return LinearColor(red: la.red + (lb.red - la.red) * f, green: la.green + (lb.green - la.green) * f,
                               blue: la.blue + (lb.blue - la.blue) * f, alpha: alpha)
        case .srgb:
            let ea: SIMD3<Float> = a.encoded
            let eb: SIMD3<Float> = b.encoded
            let e: SIMD3<Float> = ea + (eb - ea) * f
            return LinearColor(red: SRGB.decode(e.x), green: SRGB.decode(e.y), blue: SRGB.decode(e.z), alpha: alpha)
        }
    }

    /// What a native visual draws on black: colour × alpha, opaque (research SHD-005-D6).
    public func colorOverBlack(at t: Float) -> LinearColor {
        let c: LinearColor = color(at: t)
        return LinearColor(red: c.red * c.alpha, green: c.green * c.alpha, blue: c.blue * c.alpha, alpha: 1)
    }

    /// Per stop, the two float4s the shader reads (research SHD-005-D4): linear RGBA and encoded RGB + position.
    public var shaderStops: [(linear: SIMD4<Float>, encoded: SIMD4<Float>)] {
        stops.map { (s: GradientRampStop) -> (linear: SIMD4<Float>, encoded: SIMD4<Float>) in
            let l: LinearColor = s.linear
            let e: SIMD3<Float> = s.encoded
            return (SIMD4<Float>(l.red, l.green, l.blue, l.alpha), SIMD4<Float>(e.x, e.y, e.z, s.position))
        }
    }
}
