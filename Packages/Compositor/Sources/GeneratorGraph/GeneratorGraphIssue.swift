// GeneratorGraphIssue.swift — every reason a graph is refused, with its exact readable message
// (SHD-002-R4, R5, R7, R12; contracts/generator-graph.md "Messages"). Plain Swift; builds on Linux.

public enum GeneratorGraphIssue: Error, Sendable, Equatable, CustomStringConvertible {
    public enum TooFastSource: String, Sendable, Equatable { case time, music }

    case unsupportedFormat(String)
    case unsupportedVersion(Int)
    case nameTooLong(count: Int)
    case speedOutOfRange(Double)
    case tooManyNodes(count: Int)
    case tooManyConnections(count: Int)
    case invalidNodeID(String)
    case duplicateNodeID(String)
    case unknownKind(node: String, kind: String)
    case unknownName(node: String, kind: String, name: String)
    case settingConnected(node: String, name: String)
    case connectedAndSet(node: String, input: String)
    case missingSource(node: String, input: String, source: String)
    case sourceIsOutput(node: String, input: String, source: String)
    case typeMismatch(node: String, input: String, expected: GraphPortType, source: String, actual: GraphPortType)
    case phaseLiteral(node: String, input: String)
    case missingInput(node: String, input: String)
    case wrongValueShape(node: String, name: String, expected: GraphPortType)
    case notFinite(node: String, name: String)
    case outOfRange(node: String, name: String, value: Double, lower: Double, upper: Double)
    case notWhole(node: String, name: String)
    case invalidSetting(node: String, rule: String)
    case noOutput
    case multipleOutputs([String])
    case cycle([String])
    case tooDeep(nodes: Int)
    case tooManyLiveValues(count: Int)
    case tooFast(TooFastSource)

    public var message: String {
        switch self {
        case let .unsupportedFormat(f):
            return "Unsupported format \"\(f)\"; expected \"\(GeneratorGraphDocument.formatName)\"."
        case let .unsupportedVersion(v):
            return "Unsupported version \(v); this app reads version \(GeneratorGraphDocument.currentVersion)."
        case let .nameTooLong(n):
            return "Graph name has \(n) characters; the limit is \(GeneratorGraphLimits.nameLength)."
        case let .speedOutOfRange(v):
            return "Graph speed \(Self.format(v)) is outside -1 to 1."
        case let .tooManyNodes(n):
            return "Graph has \(n) nodes; the limit is \(GeneratorGraphLimits.nodes)."
        case let .tooManyConnections(n):
            return "Graph has \(n) connections; the limit is \(GeneratorGraphLimits.connections)."
        case let .invalidNodeID(id):
            return "Node ID \"\(id)\" is invalid: use 1-32 letters, digits, \"-\" or \"_\", starting with a letter."
        case let .duplicateNodeID(id):
            return "Node ID \"\(id)\" is used more than once."
        case let .unknownKind(node, kind):
            return "Node \"\(node)\": unknown kind \"\(kind)\"."
        case let .unknownName(node, kind, name):
            return "Node \"\(node)\": kind \"\(kind)\" has no input or setting \"\(name)\"."
        case let .settingConnected(node, name):
            return "Node \"\(node)\": \"\(name)\" is a setting and cannot be connected."
        case let .connectedAndSet(node, input):
            return "Node \"\(node)\": input \"\(input)\" is both connected and given a value."
        case let .missingSource(node, input, source):
            return "Node \"\(node)\": input \"\(input)\" is connected to missing node \"\(source)\"."
        case let .sourceIsOutput(node, input, source):
            return "Node \"\(node)\": input \"\(input)\" is connected to output node \"\(source)\", which gives no value."
        case let .typeMismatch(node, input, expected, source, actual):
            return "Node \"\(node)\": input \"\(input)\" expects \(expected.rawValue) but node \"\(source)\" gives \(actual.rawValue)."
        case let .phaseLiteral(node, input):
            return "Node \"\(node)\": input \"\(input)\" takes time and cannot be given a value."
        case let .missingInput(node, input):
            return "Node \"\(node)\": required input \"\(input)\" is not connected."
        case let .wrongValueShape(node, name, expected):
            return "Node \"\(node)\": \"\(name)\" needs \(expected.article)."
        case let .notFinite(node, name):
            return "Node \"\(node)\": \"\(name)\" is not a finite number."
        case let .outOfRange(node, name, value, lower, upper):
            return "Node \"\(node)\": \"\(name)\" is \(Self.format(value)), outside \(Self.format(lower)) to \(Self.format(upper))."
        case let .notWhole(node, name):
            return "Node \"\(node)\": \"\(name)\" must be a whole number."
        case let .invalidSetting(node, rule):
            return "Node \"\(node)\": \(rule)."
        case .noOutput:
            return "Graph has no output node."
        case let .multipleOutputs(ids):
            let list = ids.map { (id: String) -> String in "\"\(id)\"" }.joined(separator: ", ")
            return "Graph has \(ids.count) output nodes (\(list)); exactly one is allowed."
        case let .cycle(path):
            return "Graph has a cycle: \(path.joined(separator: " → "))."
        case let .tooDeep(n):
            return "Graph's longest chain has \(n) nodes; the limit is \(GeneratorGraphLimits.depth)."
        case let .tooManyLiveValues(n):
            return "Graph needs \(n) values at once; the limit is \(GeneratorGraphLimits.registers)."
        case let .tooFast(source):
            return "Graph changes too fast with \(source.rawValue); it would have to run below 1/\(Int(GeneratorGraphLimits.maxSlowdown)) of normal speed."
        }
    }

    public var description: String { message }

    /// Whole numbers as integers, others in Swift's shortest form.
    static func format(_ v: Double) -> String {
        if v.isFinite, v == v.rounded(), abs(v) < 1e15 { return String(Int(v)) }
        return String(v)
    }
}

/// All issues of a refused document, in the documented order.
public struct GeneratorGraphValidationError: Error, Sendable, Equatable {
    public let issues: [GeneratorGraphIssue]
    public var messages: [String] { issues.map { (i: GeneratorGraphIssue) -> String in i.message } }
}

/// The size and rate limits (SHD-002-R5, R12).
public enum GeneratorGraphLimits {
    public static let nodes = 64
    public static let connections = 128
    public static let depth = 32
    public static let registers = 16
    public static let nameLength = 64
    public static let idLength = 32
    /// A graph slower than 1/64 of normal is refused (`tooFast`).
    public static let maxSlowdown = 64.0
    /// Per-channel change per second allowed from time, and separately from music: the slope of a
    /// full-range cosine at one cycle per second.
    public static let rateBudget = Double.pi
}
