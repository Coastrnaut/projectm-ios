// GeneratorGraphDocument.swift — the versioned, declarative graph document (SHD-002-R1; research
// SHD-002-D1; data-model.md "GeneratorGraphDocument"; contracts/generator-graph.md "Document").
//
// A document is data only: node IDs, kind names from the closed set (GraphNodeKind), connections by
// node ID and literal numbers. Nothing in it is ever interpreted as code (ADR-0018 decision 3). The
// types are Codable; callers decode them (this module has no Foundation and reads no files; importing
// files is SHD-011's). Unknown JSON keys are ignored; a newer `version` is refused by validation.
// Plain Swift; builds on Linux.

public struct GeneratorGraphDocument: Codable, Sendable, Equatable {
    public static let formatName = "projectm-ios.generator-graph"
    public static let currentVersion = 1
    public static let defaultSpeed = 0.2

    public var format: String
    public var version: Int
    public var name: String
    /// Cycles of phase per second before the compiler's cap; −1…1.
    public var speed: Double
    public var nodes: [GraphNode]

    public init(name: String, speed: Double = GeneratorGraphDocument.defaultSpeed, nodes: [GraphNode],
                format: String = GeneratorGraphDocument.formatName, version: Int = GeneratorGraphDocument.currentVersion) {
        self.format = format
        self.version = version
        self.name = name
        self.speed = speed
        self.nodes = nodes
    }

    private enum CodingKeys: String, CodingKey { case format, version, name, speed, nodes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        version = try c.decode(Int.self, forKey: .version)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? Self.defaultSpeed
        nodes = try c.decode([GraphNode].self, forKey: .nodes)
    }
}

/// One node: a stable ID, a kind name, connections (input name → source node ID) and literal values
/// (input or setting name → number or numbers).
public struct GraphNode: Codable, Sendable, Equatable {
    public var id: String
    public var kind: String
    public var inputs: [String: String]
    public var values: [String: GraphValue]

    public init(_ id: String, _ kind: String, inputs: [String: String] = [:], values: [String: GraphValue] = [:]) {
        self.id = id
        self.kind = kind
        self.inputs = inputs
        self.values = values
    }

    /// A node of a built-in kind.
    public init(_ id: String, _ kind: GraphNodeKind, inputs: [String: String] = [:], values: [String: GraphValue] = [:]) {
        self.init(id, kind.rawValue, inputs: inputs, values: values)
    }

    private enum CodingKeys: String, CodingKey { case id, kind, inputs, values }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        inputs = try c.decodeIfPresent([String: String].self, forKey: .inputs) ?? [:]
        values = try c.decodeIfPresent([String: GraphValue].self, forKey: .values) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        if !inputs.isEmpty { try c.encode(inputs, forKey: .inputs) }
        if !values.isEmpty { try c.encode(values, forKey: .values) }
    }
}

/// A literal: one number (scalar inputs and settings) or several (2 for a point, 3 for a color).
public enum GraphValue: Codable, Sendable, Equatable {
    case number(Double)
    case numbers([Double])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else {
            self = .numbers(try c.decode([Double].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .number(v): try c.encode(v)
        case let .numbers(v): try c.encode(v)
        }
    }

    /// The numbers, one for `.number`.
    var components: [Double] {
        switch self {
        case let .number(v): return [v]
        case let .numbers(v): return v
        }
    }
}

extension GraphValue: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(arrayLiteral elements: Double...) { self = .numbers(elements) }
}
