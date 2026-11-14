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
//   5. saturation S: Y = Rec. 709 luminance of v, v ← max(Y + S·(v − Y), 0);
//   6. hue θ (FX-004, specs/126-fx-004-hue-shift, research FX-004-D1 to D3): d = (r − g, b − g),
//      y = g + wR·d.x + wB·d.y (the luminance, exact for greys), e = T(θ)·d with T = [[c − k, 2k], [−2k, c + k]],
//      k = sin θ/√3 (a rotation about the grey axis acting on the differences), g' = y − wR·e.x − wB·e.y,
//      v ← (g' + e.x, g', g' + e.y); a negative channel m pulls v toward y: v ← max(y + y/(y − m)·(v − y), 0).
// Then FX-002's tone map. Each operator runs only when its control is not neutral, so a neutral control is an
// exact identity. Every expression is split into typed steps (the type checker on Linux and Xcode 26).
import Foundation

/// The grading values (FX-003-R1, FX-004-R1; data-model.md). Master controls: one value for all three channels.
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
    /// FX-004: degrees around the grey axis (+120 turns red's hue into green's); greys and luminance unchanged.
    public var hue: Double

    public static let temperatureRange: ClosedRange<Double> = -1...1
    public static let liftRange: ClosedRange<Double> = -0.1...0.1
    public static let gammaRange: ClosedRange<Double> = 0.5...2
    public static let gainRange: ClosedRange<Double> = 0.5...2
    public static let saturationRange: ClosedRange<Double> = 0...2
    public static let hueRange: ClosedRange<Double> = -180...180

    /// Step hints (MOD-001 descriptors, slider steps).
    public static let temperatureStep: Double = 0.01
    public static let liftStep: Double = 0.005
    public static let gammaStep: Double = 0.01
    public static let gainStep: Double = 0.01
    public static let saturationStep: Double = 0.01
    public static let hueStep: Double = 1

    /// ±0.3 stop on red and blue at the ends of the temperature range (research D2).
    public static let temperatureStops: Double = 0.3

    /// Every control at its neutral value: grading is bypassed.
    public static let neutral = ColorGrade(temperature: 0, lift: 0, gamma: 1, gain: 1, saturation: 1, hue: 0)

    public init(temperature: Double = 0, lift: Double = 0, gamma: Double = 1, gain: Double = 1, saturation: Double = 1,
                hue: Double = 0) {
        self.temperature = temperature
        self.lift = lift
        self.gamma = gamma
        self.gain = gain
        self.saturation = saturation
        self.hue = hue
    }

    private enum CodingKeys: String, CodingKey { case temperature, lift, gamma, gain, saturation, hue }

    /// A grade encoded before FX-004 has no `hue`: it decodes as 0.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try container.decode(Double.self, forKey: .temperature)
        lift = try container.decode(Double.self, forKey: .lift)
        gamma = try container.decode(Double.self, forKey: .gamma)
        gain = try container.decode(Double.self, forKey: .gain)
        saturation = try container.decode(Double.self, forKey: .saturation)
        hue = try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0
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
                   saturation: Self.clamp(saturation, to: Self.saturationRange, neutral: 1),
                   hue: Self.clamp(hue, to: Self.hueRange, neutral: 0))
    }

    /// Every control neutral after clamping (no operator runs).
    public var isNeutral: Bool { coefficients.flags == 0 }

    /// The operator coefficients of the clamped values (research D4).
    public var coefficients: ColorGradeCoefficients { ColorGradeCoefficients(clamped) }

    /// Rec. 709 / WCAG luminance weights (as FX-002 and FX-019).
    public static let luminanceWeights: SIMD3<Double> = ToneMap.luminanceWeights

    /// The graded pixel (steps 0-6) of a linear premultiplied RGBA pixel, before the tone map. Reference only.
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
    public static let hueFlag: UInt32 = 32

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
    /// FX-004: T(θ) row by row (T00, T01, T10, T11), acting on (r − g, b − g); identity when hue is 0.
    public let hueMatrix: SIMD4<Double>
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
        if grade.hue != 0 {
            flags |= Self.hueFlag
            hueMatrix = Self.hueMatrix(degrees: grade.hue)
        } else {
            hueMatrix = SIMD4<Double>(1, 0, 0, 1)
        }
        self.flags = flags
    }

    /// FX-004-D1: what a rotation by `degrees` about the grey axis (1, 1, 1)/√3 does to (r − g, b − g).
    public static func hueMatrix(degrees: Double) -> SIMD4<Double> {
        let radians: Double = degrees * Double.pi / 180
        let c: Double = cos(radians)
        let k: Double = sin(radians) / 3.0.squareRoot()
        let twoK: Double = 2 * k
        return SIMD4<Double>(c - k, twoK, -twoK, c + k)
    }

    /// FX-004 step 6 on a non-negative colour (research FX-004-D1 to D3). Greys come back bit for bit.
    public static func rotateHue(_ v: SIMD3<Double>, matrix t: SIMD4<Double>) -> SIMD3<Double> {
        let w: SIMD3<Double> = ColorGrade.luminanceWeights
        let d1: Double = v.x - v.y
        let d2: Double = v.z - v.y
        let y: Double = v.y + w.x * d1 + w.z * d2
        let e1: Double = t.x * d1 + t.y * d2
        let e2: Double = t.z * d1 + t.w * d2
        let g: Double = y - w.x * e1 - w.z * e2
        let out = SIMD3<Double>(g + e1, g, g + e2)
        let m: Double = min(out.x, min(out.y, out.z))
        if m >= 0 { return out }
        if y <= 0 { return .zero }
        let q: Double = y / (y - m)
        var pulled: SIMD3<Double> = .zero
        for c in 0..<3 {
            let p: Double = y + q * (out[c] - y)
            pulled[c] = max(p, 0)
        }
        return pulled
    }

    /// The reference grading of one pixel (research D2, steps 0-5; FX-004 step 6).
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
        if flags & Self.hueFlag != 0 { v = Self.rotateHue(v, matrix: hueMatrix) }
        return ToneMap.Pixel(v.x, v.y, v.z, alpha)
    }
}
