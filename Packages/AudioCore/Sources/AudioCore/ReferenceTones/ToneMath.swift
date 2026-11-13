// ToneMath.swift — sine, exponential and logarithm for the reference-tone generator, built from
// correctly rounded IEEE 754 arithmetic only (AUD-016-R3; research AUD-016-D1).
//
// Why not Foundation's `sin`, `exp` and `log`: they come from each platform's math library (Apple's
// libm on macOS and iOS, glibc on Linux), which is not required to round correctly and can differ
// in the last bit between platforms and OS releases. Every operation used here (+, −, ×, ÷, rounding
// to an integer, `exponent`/`significand`, and exact scaling by a power of two) has one correct
// result in IEEE 754, so the same source gives the same bits everywhere. Swift does not fuse
// multiply-add pairs on its own (no fast-math), so the operations are the ones written.
//
// The approximations are Taylor polynomials after an exact range reduction; their truncation error
// is far below one ulp (ToneMathTests checks the accuracy against Foundation as a tolerance).

enum ToneMath {
    // MARK: Sine

    private static let halfPi = 1.5707963267948966          // π/2 rounded to Double

    /// sin(2π·cycles). Whole cycles are removed first; the result is exact at 0, ¼, ½ and ¾.
    static func sin2pi(_ cycles: Double) -> Double {
        let c = cycles - cycles.rounded(.down)                  // [0, 1), exact
        let q4 = c * 4                                          // exact (power of two)
        let quadrant = q4.rounded(.down)
        let r = q4 - quadrant                                   // [0, 1), exact
        switch Int(quadrant) {
        case 0: return quarterSine(r)                           // sin(π/2·r)
        case 1: return quarterSine(1 - r)                       // cos(π/2·r)
        case 2: return -quarterSine(r)
        default: return -quarterSine(1 - r)
        }
    }

    /// sin(π/2·u) for u ∈ [0, 1], through the polynomial with the smaller argument.
    private static func quarterSine(_ u: Double) -> Double {
        if u <= 0.5 { return sinPoly(u * halfPi) }
        return cosPoly((1 - u) * halfPi)
    }

    // 1/n! as correctly rounded quotients.
    private static let s3 = -1.0 / 6.0
    private static let s5 = 1.0 / 120.0
    private static let s7 = -1.0 / 5_040.0
    private static let s9 = 1.0 / 362_880.0
    private static let s11 = -1.0 / 39_916_800.0
    private static let s13 = 1.0 / 6_227_020_800.0
    private static let s15 = -1.0 / 1_307_674_368_000.0
    private static let s17 = 1.0 / 355_687_428_096_000.0
    private static let c2 = -1.0 / 2.0
    private static let c4 = 1.0 / 24.0
    private static let c6 = -1.0 / 720.0
    private static let c8 = 1.0 / 40_320.0
    private static let c10 = -1.0 / 3_628_800.0
    private static let c12 = 1.0 / 479_001_600.0
    private static let c14 = -1.0 / 87_178_291_200.0
    private static let c16 = 1.0 / 20_922_789_888_000.0

    /// sin x for |x| ≤ π/4 (degree 17; truncation below 1e-19).
    private static func sinPoly(_ x: Double) -> Double {
        let x2 = x * x
        let p = s15 + x2 * s17
        let q = s11 + x2 * (s13 + x2 * p)
        let r = s7 + x2 * (s9 + x2 * q)
        let t = s3 + x2 * (s5 + x2 * r)
        return x + x * (x2 * t)
    }

    /// cos x for |x| ≤ π/4 (degree 16; truncation below 1e-18).
    private static func cosPoly(_ x: Double) -> Double {
        let x2 = x * x
        let p = c14 + x2 * c16
        let q = c10 + x2 * (c12 + x2 * p)
        let r = c6 + x2 * (c8 + x2 * q)
        let t = c2 + x2 * (c4 + x2 * r)
        return 1 + x2 * t
    }

    // MARK: Exponential and logarithm

    // ln 2 split so that k·ln2Hi is exact for |k| < 2^20 (fdlibm's constants).
    private static let ln2Hi = 6.93147180369123816490e-01
    private static let ln2Lo = 1.90821492927058770002e-10
    private static let invLn2 = 1.44269504088896338700e+00

    /// eˣ. Cody–Waite reduction x = k·ln2 + r, |r| ≤ ½·ln2, a degree-13 polynomial, then ·2ᵏ exactly.
    static func exp(_ x: Double) -> Double {
        if x.isNaN { return x }
        if x > 709.78 { return .infinity }
        if x < -745.2 { return 0 }
        let k = (x * invLn2).rounded()
        let r = (x - k * ln2Hi) - k * ln2Lo
        // Taylor series of eʳ to r¹³ (truncation below 1e-17 for |r| ≤ 0.35).
        var p = 1.0 / 6_227_020_800.0
        p = 1.0 / 479_001_600.0 + r * p
        p = 1.0 / 39_916_800.0 + r * p
        p = 1.0 / 3_628_800.0 + r * p
        p = 1.0 / 362_880.0 + r * p
        p = 1.0 / 40_320.0 + r * p
        p = 1.0 / 5_040.0 + r * p
        p = 1.0 / 720.0 + r * p
        p = 1.0 / 120.0 + r * p
        p = 1.0 / 24.0 + r * p
        p = 1.0 / 6.0 + r * p
        p = 0.5 + r * p
        p = 1.0 + r * p
        p = 1.0 + r * p
        return scaled(p, byPowerOfTwo: Int(k))
    }

    /// p·2ᵏ, exact while the result is normal; a gradual underflow rounds once.
    private static func scaled(_ p: Double, byPowerOfTwo k: Int) -> Double {
        if k > 1_000 { return Double(sign: .plus, exponent: k - 1_000, significand: p) * 0x1p1000 }
        if k < -1_000 { return Double(sign: .plus, exponent: k + 1_000, significand: p) * 0x1p-1000 }
        return Double(sign: .plus, exponent: k, significand: p)
    }

    private static let sqrt2 = 1.4142135623730951

    /// ln x for finite x > 0 (NaN for x < 0 or NaN, −∞ for 0). x = m·2ᵉ with m ∈ [√½, √2), then
    /// ln m = 2·atanh(s), s = (m − 1)/(m + 1), |s| ≤ 0.172, as an odd series to s²⁷.
    static func log(_ x: Double) -> Double {
        if x.isNaN || x < 0 { return .nan }
        if x == 0 { return -.infinity }
        if x == .infinity { return x }
        var e = Double(x.exponent)
        var m = x.significand                                   // [1, 2), exact
        if m > sqrt2 {
            m *= 0.5                                            // exact
            e += 1
        }
        let s = (m - 1) / (m + 1)                               // m − 1 is exact (Sterbenz)
        let s2 = s * s
        var sum = 1.0 / 27.0
        var j = 25.0
        while j >= 1 {
            sum = 1.0 / j + s2 * sum
            j -= 2
        }
        return e * ln2Hi + (e * ln2Lo + 2 * s * sum)
    }
}
