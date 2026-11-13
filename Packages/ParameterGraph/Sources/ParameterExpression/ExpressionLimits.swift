// ExpressionLimits.swift — the complexity limits a formula is compiled under (SHD-009-R5, R13;
// contract specs/045-shd-009-expression-mapping-dsl/contracts/expression-language.md E1, E2, E6).
//
// One value with documented defaults, so SHD-010 can tighten the limits per expression graph.
// SHD-010 (specs/047-shd-010-expression-sandbox-budgets, contract B2, B5): `audio.bandMean` costs 4,
// and `firstLooserField(than:)` names the first limit above another value (frame-budget admission).

public struct ExpressionLimits: Sendable, Hashable {
    /// UTF-8 bytes of the source.
    public var maximumSourceBytes: Int
    /// Tokens, punctuation included (the end of input is not a token).
    public var maximumTokens: Int
    /// Expression nodes (numbers, names, calls, unary and binary operators) across all bindings and
    /// the result; parentheses are free.
    public var maximumNodes: Int
    /// Nesting levels: a parenthesis group, a call's arguments or a unary operand adds one; the
    /// top level is 0.
    public var maximumNesting: Int
    /// `let` bindings.
    public var maximumBindings: Int
    /// Static weighted instruction count (`cost(of:)`).
    public var maximumOperationCost: Int

    public init(maximumSourceBytes: Int = 512, maximumTokens: Int = 256, maximumNodes: Int = 128,
                maximumNesting: Int = 16, maximumBindings: Int = 16, maximumOperationCost: Int = 256) {
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumTokens = maximumTokens
        self.maximumNodes = maximumNodes
        self.maximumNesting = maximumNesting
        self.maximumBindings = maximumBindings
        self.maximumOperationCost = maximumOperationCost
    }

    /// 512 bytes, 256 tokens, 128 nodes, nesting 16, 16 bindings, cost 256.
    public static let standard = ExpressionLimits()

    /// The static cost of one instruction: 4 for `sin`, `cos`, `sqrt`, `pow`, `smoothstep` and
    /// `audio.bandMean` (a sum over up to 128 bands; SHD-010-R1), else 1. Every instruction runs exactly
    /// once per evaluation, so a formula's cost is the work its evaluation does.
    public static func cost(of opcode: ExpressionOpcode) -> Int {
        switch opcode {
        case .sin, .cos, .sqrt, .pow, .smoothstep, .bandMean: 4
        default: 1
        }
    }

    /// One limit, for messages (contract B2).
    public enum Field: Sendable, Hashable, CaseIterable {
        case sourceBytes, tokens, nodes, nesting, bindings, operationCost

        /// The phrase before "limit" in a frame-budget message.
        public var label: String {
            switch self {
            case .sourceBytes: "a source length"
            case .tokens: "a token"
            case .nodes: "a node"
            case .nesting: "a nesting"
            case .bindings: "a binding"
            case .operationCost: "an operation cost"
            }
        }
    }

    public func value(of field: Field) -> Int {
        switch field {
        case .sourceBytes: maximumSourceBytes
        case .tokens: maximumTokens
        case .nodes: maximumNodes
        case .nesting: maximumNesting
        case .bindings: maximumBindings
        case .operationCost: maximumOperationCost
        }
    }

    /// The first field, in `Field.allCases` order, whose value is above `other`'s; nil when every
    /// field is at most `other`'s (these limits are no looser).
    public func firstLooserField(than other: ExpressionLimits) -> Field? {
        Field.allCases.first { (field: Field) -> Bool in value(of: field) > other.value(of: field) }
    }
}
