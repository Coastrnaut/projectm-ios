// ExpressionMath.swift — the arithmetic behind every instruction, always finite (SHD-009-R7;
// contract E4, E6; research SHD-009-D4).
//
// This file is the module's only import besides ParameterGraph: the platform C math library for
// `sin`, `cos` and `pow`. Every result passes through `finite`, so no value on the evaluation stack
// is ever NaN or infinite.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum ExpressionMath {
    /// NaN → 0, +∞ → the largest finite number, −∞ → the most negative finite number.
    @inline(__always)
    static func finite(_ x: Double) -> Double {
        if x.isFinite { return x }
        if x.isNaN { return 0 }
        return x > 0 ? Double.greatestFiniteMagnitude : -Double.greatestFiniteMagnitude
    }

    /// `a / b`, and 0 when `b` is 0 (as in MilkDrop preset equations).
    static func divide(_ a: Double, _ b: Double) -> Double {
        b == 0 ? 0 : finite(a / b)
    }

    /// 0 for `x ≤ 0`, else the square root.
    static func squareRoot(_ x: Double) -> Double {
        x <= 0 ? 0 : x.squareRoot()
    }

    static func sine(_ x: Double) -> Double { finite(sin(x)) }

    static func cosine(_ x: Double) -> Double { finite(cos(x)) }

    /// The C library's `pow`, made finite (a negative base with a fractional exponent is NaN → 0).
    static func power(_ x: Double, _ y: Double) -> Double { finite(pow(x, y)) }

    /// `min(max(x, lo), hi)`: `hi` wins when `lo > hi`.
    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        Swift.min(Swift.max(x, lo), hi)
    }

    /// `a + (b − a) · t`, t not clamped.
    static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        finite(a + finite(finite(b - a) * t))
    }

    /// 0 when `x < edge`, else 1.
    static func step(_ edge: Double, _ x: Double) -> Double { x < edge ? 0 : 1 }

    /// Hermite smoothstep; equal edges behave as `step(e0, x)`.
    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        if e0 == e1 { return step(e0, x) }
        let t = clamp(divide(finite(x - e0), finite(e1 - e0)), 0, 1)
        return t * t * (3 - 2 * t)
    }

    static func floor(_ x: Double) -> Double { x.rounded(.down) }

    /// `x − floor(x)`, in 0…1.
    static func fract(_ x: Double) -> Double {
        let f = x - x.rounded(.down)
        // Rounding can give exactly 1 for tiny negative x; keep the result below 1.
        return f < 1 ? f : 0
    }
}
