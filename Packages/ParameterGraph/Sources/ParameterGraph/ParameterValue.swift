// ParameterValue.swift — a typed parameter value (data-model.md; research MOD-001-D7).
//
// JSON form: {"kind": "<continuous|integer|boolean|enum|color>", "value": …}; a color's value is
// [r, g, b, a]. The explicit kind keeps integer 1 and continuous 1.0 distinct across round trips.
import Foundation

public enum ParameterValue: Sendable, Hashable, Codable, CustomStringConvertible {
    case continuous(Double)
    case integer(Int)
    case boolean(Bool)
    /// An enum case ID.
    case enumeration(String)
    case color(ParameterColor)

    /// The stable kind name, matching `ParameterKind.name`.
    public var kindName: String {
        switch self {
        case .continuous: "continuous"
        case .integer: "integer"
        case .boolean: "boolean"
        case .enumeration: "enum"
        case .color: "color"
        }
    }

    public var description: String {
        switch self {
        case let .continuous(v): "\(v)"
        case let .integer(v): "\(v)"
        case let .boolean(v): "\(v)"
        case let .enumeration(v): "\"\(v)\""
        case let .color(c): "rgba(\(c.red), \(c.green), \(c.blue), \(c.alpha))"
        }
    }

    public var doubleValue: Double? { if case let .continuous(v) = self { v } else { nil } }
    public var intValue: Int? { if case let .integer(v) = self { v } else { nil } }
    public var boolValue: Bool? { if case let .boolean(v) = self { v } else { nil } }
    public var enumCaseID: String? { if case let .enumeration(v) = self { v } else { nil } }
    public var colorValue: ParameterColor? { if case let .color(v) = self { v } else { nil } }

    private enum CodingKeys: String, CodingKey { case kind, value }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "continuous": self = .continuous(try c.decode(Double.self, forKey: .value))
        case "integer": self = .integer(try c.decode(Int.self, forKey: .value))
        case "boolean": self = .boolean(try c.decode(Bool.self, forKey: .value))
        case "enum": self = .enumeration(try c.decode(String.self, forKey: .value))
        case "color": self = .color(try c.decode(ParameterColor.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown parameter value kind \"\(kind)\"")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kindName, forKey: .kind)
        switch self {
        case let .continuous(v): try c.encode(v, forKey: .value)
        case let .integer(v): try c.encode(v, forKey: .value)
        case let .boolean(v): try c.encode(v, forKey: .value)
        case let .enumeration(v): try c.encode(v, forKey: .value)
        case let .color(v): try c.encode(v, forKey: .value)
        }
    }
}
