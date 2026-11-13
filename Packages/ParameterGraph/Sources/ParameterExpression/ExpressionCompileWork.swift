// ExpressionCompileWork.swift — counted compile work and its documented linear bounds
// (SHD-010-R5; contract specs/047-shd-010-expression-sandbox-budgets/contracts/expression-budgets.md B4).
//
// Steps are counted, never timed, so the bound is deterministic and the same on every platform:
// - lexer: 1 for the length check, then every byte a scan visits (the main scan, a number's scan, the
//   scan that delimits a malformed number, the scan that places an oversized source's error);
// - parser: every grammar-rule entry and every token advance;
// - compiler: every node resolved, binding named, dependency visit, reference followed, loop-report
//   step and instruction emitted.

public struct ExpressionCompileWork: Sendable, Hashable {
    public var lexerSteps = 0
    public var parserSteps = 0
    public var compilerSteps = 0
    /// Source bytes counted by the bound: min(source bytes, the limit's maximum).
    public var boundedBytes = 0
    /// Tokens produced, end of input included (0 when lexing failed before the first token).
    public var tokens = 0

    public init() {}

    public var total: Int { lexerSteps + parserSteps + compilerSteps }

    /// Contract B4: lexer ≤ 2b + 1.
    public var lexerBound: Int { 2 * boundedBytes + 1 }
    /// Contract B4: parser ≤ 6t + 6.
    public var parserBound: Int { 6 * tokens + 6 }
    /// Contract B4: compiler ≤ 5t.
    public var compilerBound: Int { 5 * tokens }

    /// Every phase within its bound.
    public var isWithinBounds: Bool {
        lexerSteps <= lexerBound && parserSteps <= parserBound && compilerSteps <= compilerBound
    }

    /// The ceiling the bounds give at `limits`: 2b + 1 + 6(t + 1) + 6 + 5(t + 1), with b and t at their
    /// maxima (the token limit plus the end of input). 3,858 at the standard limits (contract B4: ≤ 4,096).
    public static func ceiling(for limits: ExpressionLimits) -> Int {
        let t = limits.maximumTokens + 1
        return 2 * limits.maximumSourceBytes + 1 + 6 * t + 6 + 5 * t
    }
}
