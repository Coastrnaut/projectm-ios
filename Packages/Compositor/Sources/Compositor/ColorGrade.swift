// ColorGrade.swift — FX-003's colour grade: the five values, their ranges, the operator coefficients the shader
// receives and the plain-Swift reference of the grading (FX-003-R2 to R5, R10; specs/123-fx-003-color-grading,
// contracts/color-grade.md, research FX-003-D2 to D4). CPU only, builds on Linux. The compositor's `cmp_grade`
// shader applies the same coefficients in the same order in float; tests compare the two.
//
// Per pixel, on the linear premultiplied composite colour v (the colour shown over black), research D2:
//   0. flags 0 (every control neutral): the pixel is returned unchanged (bypass, bit for bit, D3);
//      otherwise NaN/±Inf channels → 0, negative colour → 0 (alpha passes through, sanitised as FX-002 does);
//   1. temperature T: v × (r/n, 1/n, b/n), r = 2^(0.3·T), b = 2^(−0.3·T), n = 0.2126·r + 0.7152 + 0.0722·b
//      (greys keep their luminance);
//   2. lift L: v ← max(v·(1 − L) + L, 0);  3. gamma γ: v ← v^(1/γ);  4. gain G: v ← G·v;
//   5. saturation S: Y = Rec. 709 luminance of v, v ← max(Y + S·(v − Y), 0).
// Then FX-002's tone map. Each operator runs only when its control is not neutral, so a neutral control is an
// exact identity. Every expression is split into typed steps (the type checker on Linux and Xcode 26).
import Foundation

/// The five grading values (FX-003-R1; data-model.md). Master controls: one value for all three channels.
public struct ColorGrade: Sendable, Equatable, Hashable, Codable {
    /// Cool (−1) to warm (+1); unitless (spec Clarifications: no Kelvin claim).
    public var temperature: Double
    /// The black level in linear light (black → lift, white stays 1).
    public var lift: Double
    /// Mid-tones: values above 1 brighten (the exponent is 1/gamma).
    public var gamma: Double
    /// Overall multiplier.
    public var gain: Double
    /// 0 grey, 1 unchanged, 2 doubled.
    public var saturation: Double

    public static let temperatureRange: ClosedRange<Double> = -1...1
    public static let liftRange: ClosedRange<Double> = -0.1...0.1
    public static let gammaRange: ClosedRange<Double> = 0.5...2
    public static let gainRange: ClosedRange<Double> = 0.5...2
    public static let saturationRange: ClosedRange<Double> = 0...2

    /// Step hints (MOD-001 descriptors, slider steps).
    public static let temperatureStep: Double = 0.01
    public static let liftStep: Double = 0.005
    public static let gammaStep: Double = 0.01
    public static let gainStep: Double = 0.01
    public static let saturationStep: Double = 0.01

    /// ±0.3 stop on red and blue at the ends of the temperature range (research D2).
    public static let temperatureStops: Double = 0.3

    /// Every control at its neutral value: grading is bypassed.
    public static let neutral = ColorGrade(temperature: 0, lift: 0, gamma: 1, gain: 1, saturation: 1)

    public init(temperature: Double = 0, lift: Double = 0, gamma: Double = 1, gain: Double = 1, saturation: Double = 1) {
        self.temperature = temperature
        self.lift = lift
        self.gamma = gamma
        self.gain = gain
        self.saturation = saturation
    }

    /// NaN → the neutral value; out of range (including ±Inf) → the nearest bound.
    public static func clamp(_ value: Double, to range: ClosedRange<Double>, neutral: Double) -> Double {
        if value.isNaN { return neutral }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Every field valid (FX-003-R8's read rule).
    public var clamped: ColorGrade {
        ColorGrade(temperature: Self.clamp(temperature, to: Self.temperatureRange, neutral: 0),
                   lift: Self.clamp(lift, to: Self.liftRange, neutral: 0),
                   gamma: Self.clamp(gamma, to: Self.gammaRange, neutral: 1),
                   gain: Self.clamp(gain, to: Self.gainRange, neutral: 1),
                   saturation: Self.clamp(saturation, to: Self.saturationRange, neutral: 1))
    }

    /// Every control neutral after clamping (no operator runs).
    public var isNeutral: Bool { coefficients.flags == 0 }

    /// The operator coefficients of the clamped values (research D4).
    public var coefficients: ColorGradeCoefficients { ColorGradeCoefficients(clamped) }

    /// Rec. 709 / WCAG luminance weights (as FX-002 and FX-019).
    public static let luminanceWeights: SIMD3<Double> = ToneMap.luminanceWeights

    /// The graded pixel (steps 0-5) of a linear premultiplied RGBA pixel, before the tone map. Reference only.
    public func apply(_ input: ToneMap.Pixel) -> ToneMap.Pixel {
        coefficients.apply(input)
    }
}

/// What the shader receives (research D4): derived once per change in Double, rounded to Float for the GPU.
public struct ColorGradeCoefficients: Sendable, Equatable {
    public static let temperatureFlag: UInt32 = 1
    public static let liftFlag: UInt32 = 2
    public static let gammaFlag: UInt32 = 4
    public static let gainFlag: UInt32 = 8
    public static let saturationFlag: UInt32 = 16

    /// Per-channel white-balance gains (1, 1, 1 at neutral temperature).
    public let balance: SIMD3<Double>
    /// 1 − lift.
    public let liftScale: Double
    /// lift.
    public let liftOffset: Double
    /// 1 / gamma.
    public let exponent: Double
    public let gain: Double
    public let saturation: Double
    /// One bit per active operator; 0 ⇔ every control neutral.
    public let flags: UInt32

    /// `grade` must already be clamped.
    init(_ grade: ColorGrade) {
        var flags: UInt32 = 0
        if grade.temperature != 0 {
            flags |= Self.temperatureFlag
            let stops: Double = ColorGrade.temperatureStops * grade.temperature
            let red: Double = exp2(stops)
            let blue: Double = exp2(-stops)
            let w: SIMD3<Double> = ColorGrade.luminanceWeights
            let n: Double = w.x * red + w.y + w.z * blue
            balance = SIMD3<Double>(red / n, 1 / n, blue / n)
        } else {
            balance = SIMD3<Double>(1, 1, 1)
        }
        if grade.lift != 0 { flags |= Self.liftFlag }
        liftScale = 1 - grade.lift
        liftOffset = grade.lift
        if grade.gamma != 1 { flags |= Self.gammaFlag }
        exponent = 1 / grade.gamma
        if grade.gain != 1 { flags |= Self.gainFlag }
        gain = grade.gain
        if grade.saturation != 1 { flags |= Self.saturationFlag }
        saturation = grade.saturation
        self.flags = flags
    }

    /// The reference grading of one pixel (research D2, steps 0-5).
    public func apply(_ input: ToneMap.Pixel) -> ToneMap.Pixel {
        if flags == 0 { return input }
        var v: SIMD3<Double> = .zero
        for c in 0..<3 {
            let x: Double = input[c]
            v[c] = x.isFinite && x > 0 ? x : 0
        }
        let rawAlpha: Double = input[3]
        let alpha: Double = rawAlpha.isFinite ? min(max(rawAlpha, 0), 1) : 0
        if flags & Self.temperatureFlag != 0 { v = v * balance }
        if flags & Self.liftFlag != 0 {
            for c in 0..<3 {
                let lifted: Double = v[c] * liftScale + liftOffset
                v[c] = max(lifted, 0)
            }
        }
        if flags & Self.gammaFlag != 0 {
            for c in 0..<3 { v[c] = v[c] > 0 ? pow(v[c], exponent) : 0 }
        }
        if flags & Self.gainFlag != 0 { v = v * gain }
        if flags & Self.saturationFlag != 0 {
            let w: SIMD3<Double> = ColorGrade.luminanceWeights
            let y: Double = w.x * v.x + w.y * v.y + w.z * v.z
            for c in 0..<3 {
                let spread: Double = v[c] - y
                let s: Double = y + saturation * spread
                v[c] = max(s, 0)
            }
        }
        return ToneMap.Pixel(v.x, v.y, v.z, alpha)
    }
}
