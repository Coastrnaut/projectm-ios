// ContrastCurve.swift — FX-005's contrast curves (FX-005-R1 to R5; specs/292-fx-005-contrast-curves,
// contracts/contrast-curves.md, research FX-005-D3 to D5). CPU only, builds on Linux. The plain-Swift reference of the
// curve the compositor's `cmp_contrast` shader applies in float as step 7 of FX-003's grade; tests compare the two.
//
// One monotone curve per channel on display-range values x ∈ 0…1, strength s ∈ 0…1:
//   linear (or s = 0): x (the grade skips the step entirely: bit-for-bit bypass);
//   sCurve: pivot p = 0.18, c = 1 + s; x ≤ p → p·(x/p)^c, else 1 − (1 − p)·((1 − x)/(1 − p))^c
//           (f(0) = 0, f(p) = p, f(1) = 1, slope c at the pivot from both sides);
//   filmic: F = S∘T, toe T(x) = x²(1 + τ)/(x + τ), shoulder S(y) = y(1 + σ)/(y + σ), τ = 0.1, σ = 0.5;
//           output x + s·(F(x) − x) (keeps 0 and 1 exact in floating point).
// The input is clamped to 0…1 (NaN → 0) and so is the output. Every expression is split into typed steps.
import Foundation

/// FX-005: the contrast presets (FX-005-R1). Raw values are the stored and scene names (never rename one).
public enum ContrastCurve: String, Sendable, CaseIterable, Codable, Hashable {
    case linear
    case sCurve
    case filmic

    /// Unknown or missing names read as Linear (FX-005-R8).
    public init(storedName: String?) {
        self = storedName.flatMap { (name: String) -> ContrastCurve? in ContrastCurve(rawValue: name) } ?? .linear
    }

    /// Picker and catalog names.
    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .sCurve: return "S-curve"
        case .filmic: return "Filmic"
        }
    }

    public static let strengthRange: ClosedRange<Double> = 0...1
    public static let defaultStrength: Double = 0.5
    public static let strengthStep: Double = 0.01
    /// S-curve pivot: linear mid-grey (research FX-005-D3).
    public static let pivot: Double = 0.18
    /// Filmic toe and shoulder constants (research FX-005-D4).
    public static let toe: Double = 0.1
    public static let shoulder: Double = 0.5

    /// The curve of one display-range value (contract C1): output in 0…1, f(0) = 0 and f(1) = 1 exactly, monotone.
    public static func value(_ x: Double, curve: ContrastCurve, strength: Double) -> Double {
        let input: Double = x.isNaN ? 0 : min(max(x, 0), 1)
        let s: Double = strength.isNaN ? 0 : min(max(strength, 0), 1)
        if curve == .linear || s <= 0 { return input }
        let out: Double = curve == .sCurve ? sCurve(input, exponent: 1 + s) : filmic(input, strength: s)
        return min(max(out, 0), 1)
    }

    /// The two-sided power curve around `pivot` (x already in 0…1).
    public static func sCurve(_ x: Double, exponent c: Double) -> Double {
        let p: Double = pivot
        if x <= p {
            let t: Double = x / p
            return p * pow(t, c)
        }
        let q: Double = 1 - p
        let t: Double = (1 - x) / q
        let fall: Double = q * pow(t, c)
        return 1 - fall
    }

    /// The fixed toe ∘ shoulder curve (x in 0…1), unblended.
    public static func filmicBase(_ x: Double) -> Double {
        let tau: Double = toe
        let sigma: Double = shoulder
        let square: Double = x * x
        let t: Double = square * (1 + tau) / (x + tau)
        let y: Double = t * (1 + sigma) / (t + sigma)
        return y
    }

    /// Filmic blended with the identity by `strength`.
    public static func filmic(_ x: Double, strength s: Double) -> Double {
        let f: Double = filmicBase(x)
        let delta: Double = f - x
        return x + s * delta
    }
}
