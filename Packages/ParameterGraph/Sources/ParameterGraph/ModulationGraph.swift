// ModulationGraph.swift — a pure description of what modulates what (MOD-014-R1, R4; data-model.md;
// contract G1, G2), shared by audio bindings (MOD-002), LFOs (MOD-007 to MOD-009), macros (MOD-010),
// mixes (MOD-011), the matrix UI (MOD-012) and serialization (MOD-013).
//
// Nodes are audio features (sources only), registered parameters (one input, `value`) and
// generators (operator nodes such as LFOs and macros, with the inputs they declare). Connections go
// from a source node to one input of a target node. Validation (`validate(in:)`) refuses cycles with
// a readable path; cycles are refused, never delayed (research MOD-014-D1).

/// One node of the modulation graph, identified by a stable ID.
public enum ModulationNode: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// A normalized audio feature: a source only, it has no inputs.
    case audio(AudioFeatureSource)
    /// A registered parameter: its one input is `value`.
    case parameter(ParameterID)
    /// A declared generator (LFO, macro, …), by its stable ID.
    case generator(String)

    /// The stable ID: `audio.band.3`, `visual.ring.gap`, `lfo.one`.
    public var id: String {
        switch self {
        case let .audio(source): source.id
        case let .parameter(id): id.rawValue
        case let .generator(id): id
        }
    }

    public var description: String { id }

    var kindRank: Int {
        switch self {
        case .audio: 0
        case .parameter: 1
        case .generator: 2
        }
    }

    /// By stable ID, then kind (audio, parameter, generator), so the order is total and the same on
    /// every host (research MOD-014-D4).
    public static func < (lhs: ModulationNode, rhs: ModulationNode) -> Bool {
        let l = lhs.id, r = rhs.id
        return l != r ? l < r : lhs.kindRank < rhs.kindRank
    }
}

/// An operator node (LFO, macro, …) with a stable ID, a display name and named inputs.
public struct ModulationGenerator: Sendable, Hashable {
    /// The stable ID, with the parameter ID syntax (`lfo.one`, `macro.a`).
    public var id: String
    public var displayName: String
    /// The inputs other nodes may drive (`value`, `rate`, `amplitude`, …), each a single segment.
    public var inputs: [String]

    public init(id: String, displayName: String, inputs: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.inputs = inputs
    }
}

/// A directed connection: `source` drives `input` of `target`.
public struct ModulationEdge: Sendable, Hashable, CustomStringConvertible {
    /// The input every parameter has, and the default input of a connection.
    public static let valueInput = "value"

    public var source: ModulationNode
    public var target: ModulationNode
    public var input: String

    public init(source: ModulationNode, target: ModulationNode, input: String = ModulationEdge.valueInput) {
        self.source = source
        self.target = target
        self.input = input
    }

    /// How the target end is written in a path: the target's ID, plus `.<input>` for an input other
    /// than `value`.
    public var targetText: String { input == Self.valueInput ? target.id : target.id + "." + input }

    public var description: String { source.id + " → " + targetText }
}

/// Generators plus connections. Building one never fails; `validate(in:)` says what is wrong.
public struct ModulationGraph: Sendable, Hashable {
    /// At most this many nodes (declared generators plus distinct nodes named by connections).
    public static let maximumNodes = 1_024
    /// At most this many connections.
    public static let maximumEdges = 4_096

    public var generators: [ModulationGenerator]
    public var edges: [ModulationEdge]

    public init(generators: [ModulationGenerator] = [], edges: [ModulationEdge] = []) {
        self.generators = generators
        self.edges = edges
    }

    /// Every issue against `registry`, in the stable order of contract G4/G5; empty when accepted.
    /// Never traps; linear in nodes plus connections (up to a log factor), constant call depth.
    public func validate(in registry: ParameterRegistry) -> [ModulationGraphIssue] {
        ModulationGraphValidator(graph: self, registry: registry).run().issues
    }
}

/// A loop: `edges[0]` leaves the start node and the last edge enters it again.
public struct ModulationCycle: Sendable, Hashable, CustomStringConvertible {
    public let edges: [ModulationEdge]
    /// Stable IDs joined by ` → `, starting and ending at the start node, for example
    /// `macro.a → visual.ring.gap → lfo.one.rate → macro.a`.
    public let path: String
    /// The same steps with display names, for example `Macro A → Ring gap → LFO One (rate) → Macro A`.
    public let displayPath: String

    public var description: String { path }
}

/// One problem found by validation.
public struct ModulationGraphIssue: Sendable, Hashable, CustomStringConvertible {
    public enum Problem: String, Sendable, Hashable, CaseIterable {
        case tooManyEdges
        case tooManyNodes
        case malformedGeneratorID
        case emptyGeneratorName
        case duplicateGenerator
        case conflictingGeneratorID
        case malformedInput
        case duplicateInput
        case unknownAudioFeature
        case unknownParameter
        case retiredParameter
        case unknownGenerator
        case audioTarget
        case unknownInput
        case duplicateEdge
        case selfLoop
        case cycle
    }

    public let problem: Problem
    /// The connection concerned (connection problems and self-loops).
    public let edge: ModulationEdge?
    /// The generator concerned (generator problems).
    public let generatorID: String?
    /// The loop (self-loops and cycles).
    public let cycle: ModulationCycle?
    /// A readable sentence naming what is wrong and where.
    public let message: String

    public var description: String { message }
}

/// A refused graph: every issue, one per line in `description`.
public struct ModulationGraphError: Error, Sendable, Hashable, CustomStringConvertible {
    public let issues: [ModulationGraphIssue]

    public var description: String {
        (["Modulation graph is invalid (\(issues.count) issue\(issues.count == 1 ? "" : "s")):"]
            + issues.map { (issue: ModulationGraphIssue) -> String in "- " + issue.message }).joined(separator: "\n")
    }
}
