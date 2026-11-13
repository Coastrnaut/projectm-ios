// SceneJSON.swift — the JSON value a scene is read into and written from (SCN-001-R7, R10;
// research SCN-001-D1; contract C2).
//
// Numbers keep the exact text they were written with, so preserved unknown content is written back
// byte for byte and typed fields read the full precision of what was written. Plain Swift.

/// One JSON number, as written. `text` always matches the JSON number grammar.
public struct SceneNumber: Sendable, Hashable, CustomStringConvertible {
    public let text: String

    /// Only the parser and the initializers below build numbers, so `text` is always valid JSON.
    init(validatedText: String) { text = validatedText }

    /// A finite double in its shortest round-trip form (`0.1`, `1.0`, `1e-07`, `-0.0`).
    /// Non-finite values cannot be written in JSON; callers refuse them first (`0.0` is written).
    public init(_ value: Double) {
        text = value.isFinite ? value.description : "0.0"
    }

    public init(_ value: Int64) { text = String(value) }
    public init(_ value: Int) { text = String(value) }
    public init(_ value: UInt64) { text = String(value) }

    /// The number as a double, or nil when it is too large to be finite.
    public var doubleValue: Double? {
        guard let d = Double(text), d.isFinite else { return nil }
        return d
    }

    /// The number as an integer when it is written as one (no fraction, no exponent) and fits.
    public var int64Value: Int64? { Int64(text) }

    /// The number as a non-negative integer when written as one and it fits.
    public var uint64Value: UInt64? { UInt64(text) }

    public var description: String { text }
}

/// A JSON value. Objects are maps: key order never matters (contract C3); the writer sorts keys.
public enum SceneJSON: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(SceneNumber)
    case string(String)
    case array([SceneJSON])
    case object([String: SceneJSON])

    public static func double(_ value: Double) -> SceneJSON { .number(SceneNumber(value)) }
    public static func integer(_ value: Int64) -> SceneJSON { .number(SceneNumber(value)) }

    /// The JSON type name used in messages.
    public var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "a boolean"
        case .number: "a number"
        case .string: "a string"
        case .array: "an array"
        case .object: "an object"
        }
    }

    public var objectValue: [String: SceneJSON]? { if case let .object(o) = self { o } else { nil } }
    public var arrayValue: [SceneJSON]? { if case let .array(a) = self { a } else { nil } }
    public var stringValue: String? { if case let .string(s) = self { s } else { nil } }
    public var numberValue: SceneNumber? { if case let .number(n) = self { n } else { nil } }
    public var boolValue: Bool? { if case let .bool(b) = self { b } else { nil } }
}

extension SceneJSON {
    /// SCN-002: reads one JSON value with the scene reader's bounds (at most
    /// `SceneLimits.maximumBytes`, nesting at most `SceneLimits.maximumDepth`, duplicate keys refused).
    /// The app uses it to embed a stored MED-009 text overlay as a scene text asset.
    public static func parse(_ bytes: [UInt8]) throws(SceneDecodeError) -> SceneJSON {
        guard !bytes.isEmpty else { throw .empty }
        guard bytes.count <= SceneLimits.maximumBytes else {
            throw .tooLarge(bytes: bytes.count, limit: SceneLimits.maximumBytes)
        }
        return try SceneJSONParser.parse(bytes, maximumDepth: SceneLimits.maximumDepth)
    }
}
