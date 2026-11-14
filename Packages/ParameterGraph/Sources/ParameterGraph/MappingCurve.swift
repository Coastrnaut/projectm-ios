// MappingCurve.swift — shapes a 0…1 position into 0…1 before MOD-003 interpolates it into a range
// (MOD-004-R1 to R5, R10; research MOD-004-D1 to D6; contract
// specs/129-mod-004-curve-mapping/contracts/mapping-curve.md K1-K6).
//
// * Input: read as MOD-003 reads a position (non-finite → 0, then limited to 0…1).
// * Every curve, valid or not: exactly 0 at 0 and 1 at 1, never outside 0…1, non-decreasing, and
//   deterministic (no clock, randomness or state). IEEE rounding is monotonic, `pow` with a fixed
//   positive exponent, `log1p` and `expm1` are monotonic, and limiting then pinning the ends keeps
//   the order (research D1); the acceptance tests sweep every kind.
// * An invalid curve used anyway acts on limited parameters and skips unusable piecewise points, so it
//   never traps; bindings and scenes refuse invalid curves before use (`validationProblem`).
// * Allocation-free `apply` (piecewise scans at most `maximumPoints` stored points). Shared with
//   MIDI-004, which stores `textForm` after `;curve=` in its mapping lines.
import Foundation

/// One interior point of a piecewise curve.
public struct CurvePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum MappingCurve: Sendable, Hashable {
    /// x.
    case linear
    /// x^p: slow start.
    case easeIn(exponent: Double)
    /// 1 − (1 − x)^p: fast start.
    case easeOut(exponent: Double)
    /// Ease-in on the first half, ease-out on the second, meeting at (0.5, 0.5).
    case easeInOut(exponent: Double)
    /// log(1 + k·x) / log(1 + k): low inputs count more.
    case logarithmic(strength: Double)
    /// ((1 + k)^x − 1) / k: the inverse of `logarithmic`.
    case exponential(strength: Double)
    /// Straight lines through (0, 0), the interior points, and (1, 1).
    case piecewise([CurvePoint])

    /// At most this many interior points (research D2).
    public static let maximumPoints: Int = 8
    /// Valid exponents: above this, …
    public static let exponentLowerBound: Double = 1
    /// … and at most this.
    public static let maximumExponent: Double = 8
    /// Valid strengths: above 0 and at most this.
    public static let maximumStrength: Double = 1000
    /// `init?(textForm:)` reads at most this many points (bounds the work on hostile text).
    static let maximumTextPoints: Int = 64

    // MARK: Shaping (contract K1-K4)

    /// The shaped position: 0 at 0, 1 at 1, within 0…1, non-decreasing, deterministic.
    public func apply(_ input: Double) -> Double {
        let x: Double = LinearMapping.clampedPosition(input)
        if case .linear = self { return x }   // bit-identical to the unshaped position (research D4)
        if x == 0 { return 0 }
        if x == 1 { return 1 }
        let shaped: Double = shape(x)
        return min(max(shaped.isFinite ? shaped : 0, 0), 1)
    }

    private func shape(_ x: Double) -> Double {
        switch self {
        case .linear:
            return x
        case let .easeIn(exponent):
            guard let p = Self.usableExponent(exponent) else { return x }
            return pow(x, p)
        case let .easeOut(exponent):
            guard let p = Self.usableExponent(exponent) else { return x }
            let rest: Double = 1 - x
            return 1 - pow(rest, p)
        case let .easeInOut(exponent):
            guard let p = Self.usableExponent(exponent) else { return x }
            if x < 0.5 {
                let doubled: Double = 2 * x
                return 0.5 * pow(doubled, p)
            }
            let doubledRest: Double = 2 * (1 - x)
            return 1 - 0.5 * pow(doubledRest, p)
        case let .logarithmic(strength):
            guard let k = Self.usableStrength(strength) else { return x }
            let scaled: Double = k * x
            let top: Double = log1p(scaled)
            let bottom: Double = log1p(k)
            return top / bottom
        case let .exponential(strength):
            guard let k = Self.usableStrength(strength) else { return x }
            let rate: Double = log1p(k)
            let exponentValue: Double = x * rate
            let top: Double = expm1(exponentValue)
            return top / k
        case let .piecewise(points):
            return Self.piecewiseValue(points, at: x)
        }
    }

    /// The exponent limited to the valid range; nil (act as linear) when not finite.
    private static func usableExponent(_ p: Double) -> Double? {
        guard p.isFinite else { return nil }
        return min(max(p, exponentLowerBound), maximumExponent)
    }

    /// The strength limited to the valid range; nil (act as linear) when not finite or not positive.
    private static func usableStrength(_ k: Double) -> Double? {
        guard k.isFinite, k > 0 else { return nil }
        return min(k, maximumStrength)
    }

    /// Straight lines through (0, 0), the usable points among the first `maximumPoints`, and (1, 1). A
    /// point is usable when it is finite, right of the previous usable point, left of 1, and its y is
    /// within the previous usable y…1; the usable set does not depend on `x`, so the result is monotonic.
    private static func piecewiseValue(_ points: [CurvePoint], at x: Double) -> Double {
        var x0: Double = 0
        var y0: Double = 0
        var considered: Int = 0
        for point in points {
            if considered == maximumPoints { break }
            considered += 1
            guard point.x.isFinite, point.y.isFinite, point.x > x0, point.x < 1, point.y >= y0, point.y <= 1 else { continue }
            if x < point.x { return segment(x0: x0, y0: y0, x1: point.x, y1: point.y, at: x) }
            x0 = point.x
            y0 = point.y
        }
        return segment(x0: x0, y0: y0, x1: 1, y1: 1, at: x)
    }

    /// MOD-003's bounded, monotonic interpolation on one segment; exactly `y0` at `x0`.
    private static func segment(x0: Double, y0: Double, x1: Double, y1: Double, at x: Double) -> Double {
        let offset: Double = x - x0
        let width: Double = x1 - x0
        let t: Double = offset / width
        return LinearMapping.interpolate(from: y0, to: y1, at: t)
    }

    // MARK: Properties

    /// Linear, or a piecewise curve without points.
    public var isLinear: Bool {
        switch self {
        case .linear: true
        case let .piecewise(points): points.isEmpty
        default: false
        }
    }

    /// The stored kind name (scene `kind`, MOD-004-D5).
    public var kindName: String {
        switch self {
        case .linear: "linear"
        case .easeIn: "easeIn"
        case .easeOut: "easeOut"
        case .easeInOut: "easeInOut"
        case .logarithmic: "logarithmic"
        case .exponential: "exponential"
        case .piecewise: "piecewise"
        }
    }

    // MARK: Validation (contract K5)

    public var isValid: Bool { validationProblem == nil }

    /// Nil for a valid curve, otherwise the first fault as a readable clause.
    public var validationProblem: String? {
        switch self {
        case .linear:
            return nil
        case let .easeIn(p), let .easeOut(p), let .easeInOut(p):
            let valid: Bool = p.isFinite && p > Self.exponentLowerBound && p <= Self.maximumExponent
            return valid ? nil : "the exponent \(p) must be finite with 1 < p ≤ 8"
        case let .logarithmic(k), let .exponential(k):
            let valid: Bool = k.isFinite && k > 0 && k <= Self.maximumStrength
            return valid ? nil : "the strength \(k) must be finite with 0 < k ≤ 1000"
        case let .piecewise(points):
            return Self.piecewiseProblem(points)
        }
    }

    private static func piecewiseProblem(_ points: [CurvePoint]) -> String? {
        if points.count > maximumPoints {
            return "a piecewise curve has at most \(maximumPoints) points; this one has \(points.count)"
        }
        var previous: CurvePoint? = nil
        for (index, point) in points.enumerated() {
            let n: Int = index + 1
            guard point.x.isFinite, point.y.isFinite else { return "point \(n) is not finite" }
            guard point.x > 0, point.x < 1 else { return "point \(n) has x = \(point.x); x must be inside (0, 1)" }
            guard point.y >= 0, point.y <= 1 else { return "point \(n) has y = \(point.y); y must be in 0…1" }
            if let previous {
                guard point.x > previous.x else { return "point \(n) has x = \(point.x); x must be strictly increasing" }
                guard point.y >= previous.y else {
                    return "point \(n) has y = \(point.y), below the previous \(previous.y); y must never decrease"
                }
            }
            previous = point
        }
        return nil
    }

    // MARK: Text form (contract K6, for MIDI-004)

    /// `linear`, `easeIn:2.0`, `log:9.0`, `piecewise:0.25,0.5/0.75,0.9`; never contains `;`, `=` or spaces.
    public var textForm: String {
        switch self {
        case .linear: return "linear"
        case let .easeIn(p): return "easeIn:" + String(p)
        case let .easeOut(p): return "easeOut:" + String(p)
        case let .easeInOut(p): return "easeInOut:" + String(p)
        case let .logarithmic(k): return "log:" + String(k)
        case let .exponential(k): return "exp:" + String(k)
        case let .piecewise(points):
            let pairs: [String] = points.map { (p: CurvePoint) -> String in String(p.x) + "," + String(p.y) }
            return "piecewise:" + pairs.joined(separator: "/")
        }
    }

    /// Reads `textForm`'s output back; nil for anything else. Ranges are not checked (callers validate).
    public init?(textForm text: String) {
        if text == "linear" {
            self = .linear
            return
        }
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let tag: String = String(text[text.startIndex..<colon])
        let value: String = String(text[text.index(after: colon)...])
        if tag == "piecewise" {
            guard let points = Self.points(fromText: value) else { return nil }
            self = .piecewise(points)
            return
        }
        guard let number = Self.number(value) else { return nil }
        switch tag {
        case "easeIn": self = .easeIn(exponent: number)
        case "easeOut": self = .easeOut(exponent: number)
        case "easeInOut": self = .easeInOut(exponent: number)
        case "log": self = .logarithmic(strength: number)
        case "exp": self = .exponential(strength: number)
        default: return nil
        }
    }

    private static func number(_ text: String) -> Double? {
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        return Double(text)
    }

    private static func points(fromText text: String) -> [CurvePoint]? {
        if text.isEmpty { return [] }
        let pairs: [Substring] = text.split(separator: "/", omittingEmptySubsequences: false)
        guard pairs.count <= maximumTextPoints else { return nil }
        var points: [CurvePoint] = []
        for pair in pairs {
            let parts: [Substring] = pair.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 2, let x = number(String(parts[0])), let y = number(String(parts[1])) else { return nil }
            points.append(CurvePoint(x: x, y: y))
        }
        return points
    }
}
