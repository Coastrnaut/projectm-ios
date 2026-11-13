// ParameterKind.swift — units, curve hints, value kinds, enum cases and colors (MOD-001-R2, R3;
// data-model.md).

/// The unit of a parameter's value. Raw values are stable (stored by later rows).
public enum ParameterUnit: String, Sendable, Hashable, CaseIterable, Codable {
    case none
    /// A fraction 0…1 of something named by the parameter (a slot, a pitch, a strength).
    case normalized
    /// A fraction of the output's size (the parameter's display name says which side).
    case fractionOfOutput
    case seconds
    case perSecond
    case degrees
    case count
}

/// How a continuous parameter is best presented and mapped (UIX rows, MOD-004). A hint only: the
/// store never applies it.
public enum ParameterCurve: String, Sendable, Hashable, CaseIterable, Codable {
    case linear
    /// Requires a minimum above 0.
    case logarithmic
    case exponential
}

/// One case of an enum parameter. `id` is stable and stored; `displayName` is for people.
public struct ParameterEnumCase: Sendable, Hashable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    /// A lowercase ASCII letter or digit, then ASCII letters and digits.
    public static func isWellFormedID(_ id: String) -> Bool {
        guard let first = id.utf8.first, ParameterSyntax.isLower(first) || ParameterSyntax.isDigit(first) else {
            return false
        }
        return id.utf8.allSatisfy { ParameterSyntax.isLower($0) || ParameterSyntax.isUpper($0) || ParameterSyntax.isDigit($0) }
    }
}

/// A linear, straight-alpha RGBA color with components in 0…1. Encoded as `[r, g, b, a]`.
public struct ParameterColor: Sendable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var components: [Double] { [red, green, blue, alpha] }
    public var isFinite: Bool { components.allSatisfy(\.isFinite) }
    public var isInRange: Bool { components.allSatisfy { $0 >= 0 && $0 <= 1 } }

    /// Each component clamped to 0…1 (callers reject non-finite components first).
    public var clamped: ParameterColor {
        func c(_ v: Double) -> Double { min(max(v, 0), 1) }
        return ParameterColor(red: c(red), green: c(green), blue: c(blue), alpha: c(alpha))
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        red = try container.decode(Double.self)
        green = try container.decode(Double.self)
        blue = try container.decode(Double.self)
        alpha = try container.decode(Double.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "a color has exactly four components")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(contentsOf: components)
    }
}

/// What kind of value a parameter holds, with its constraints and default. Bounds are stored as
/// separate numbers (not `ClosedRange`) so a malformed descriptor (min > max, NaN) can be built and
/// rejected by validation instead of trapping.
public enum ParameterKind: Sendable, Hashable {
    /// A Double in minimum…maximum. `step` is a presentation hint (> 0); the store never snaps.
    case continuous(minimum: Double, maximum: Double, defaultValue: Double, step: Double? = nil,
                    curve: ParameterCurve = .linear)
    /// An Int in minimum…maximum; values snap to `step` (≥ 1) counted from the minimum.
    case integer(minimum: Int, maximum: Int, defaultValue: Int, step: Int = 1)
    case boolean(defaultValue: Bool)
    /// One of `cases` (ordered), identified by case ID.
    case enumeration(cases: [ParameterEnumCase], defaultValue: String)
    case color(defaultValue: ParameterColor)

    /// The stable kind name used in JSON and messages.
    public var name: String {
        switch self {
        case .continuous: "continuous"
        case .integer: "integer"
        case .boolean: "boolean"
        case .enumeration: "enum"
        case .color: "color"
        }
    }

    public var defaultValue: ParameterValue {
        switch self {
        case let .continuous(_, _, value, _, _): .continuous(value)
        case let .integer(_, _, value, _): .integer(value)
        case let .boolean(value): .boolean(value)
        case let .enumeration(_, value): .enumeration(value)
        case let .color(value): .color(value)
        }
    }

    /// Continuous and integer kinds (the ones add and multiply apply to).
    public var isNumeric: Bool {
        switch self {
        case .continuous, .integer: true
        default: false
        }
    }
}
