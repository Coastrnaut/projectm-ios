# Contract: Expression Budgets (SHD-010)

Module `ParameterExpression` (Packages/ParameterGraph). Extends SHD-009's contract
`specs/045-shd-009-expression-mapping-dsl/contracts/expression-language.md` (E1-E8).

## B1 API

```swift
public struct ExpressionFrameBudget: Sendable, Hashable {
    public var maximumExpressions: Int          // 32
    public var maximumOperationCost: Int        // 2048
    public var expressionLimits: ExpressionLimits   // .standard
    public static let standard: ExpressionFrameBudget
}
public struct ExpressionFrameSet: Sendable {
    public struct Handle: Sendable, Hashable, Comparable { public let rawValue: UInt64 }
    public init(budget: ExpressionFrameBudget = .standard)
    public var budget: ExpressionFrameBudget { get }
    public var usedCost: Int { get }
    public var count: Int { get }
    public var handles: [Handle] { get }
    public mutating func admit(_ expression: CompiledExpression) throws(ExpressionBudgetError) -> Handle
    @discardableResult public mutating func remove(_ handle: Handle) -> Bool
    public var snapshot: ExpressionFrameSnapshot { get }
}
public struct ExpressionFrameSnapshot: Sendable {
    public let expressions: [CompiledExpression]
    public let handles: [ExpressionFrameSet.Handle]
    public let operationCost: Int
    public func evaluate(_ inputs: ExpressionInputs, into results: UnsafeMutableBufferPointer<Double>) -> Int
}
public struct ExpressionCompileWork: Sendable, Hashable { lexerSteps, parserSteps, compilerSteps, total }
extension CompiledExpression {
    public static func measure(source: String, limits: ExpressionLimits = .standard)
        -> (result: Result<CompiledExpression, ExpressionError>, work: ExpressionCompileWork)
}
```

No API of the frame set or the snapshot takes source text.

## B2 Refusal messages (in check order)

| Check | Message |
|---|---|
| A limit of the formula's `limits` is above the budget's `expressionLimits` (first in the order source bytes, tokens, nodes, nesting, bindings, operation cost) | `the formula was compiled with <a source length / a token / a node / a nesting / a binding / an operation cost> limit of <value>; the standard limit is <standard>` |
| `count == maximumExpressions` | `the frame already evaluates <n> formulas; at most <n> are allowed` |
| `usedCost + cost > maximumOperationCost` | `a formula of cost <c> would bring the frame to <used + c>; at most <limit> is allowed (<used> used)` |

## B3 Pathological fixtures (standard limits)

| Fixture | Outcome |
|---|---|
| 1,000,001 bytes (spaces then `1`) | `1:513: the source is 1000001 bytes; at most 512 are allowed`, lexer steps ≤ 513 |
| 127 `(`, `1`, 127 `)` (255 tokens) | `1:17: nesting deeper than 16 levels` |
| 255 `(`, `1`, 255 `)` (511 bytes) | `1:257: more than 256 tokens` |
| 255 `-` then `1` | `1:17: nesting deeper than 16 levels` |
| 17 nested `abs(` | `1:68: nesting deeper than 16 levels` |
| `1+1+…` (256 ones, 511 bytes) | `1:257: more than 256 tokens` |
| 400-digit literal | `1:1: number '1…1' is out of range` |
| 17 `let` bindings | `1:<offset>: more than 16 bindings` |
| 43 × `sin(1)` joined by `+` | `1:294: operation cost over 256` |
| 52 × `audio.bandMean` joined by `+` | `1:<pos>: operation cost over 256` (52 × 4 + 51 = 259) |
| A 16-binding ring `let a0 = a1; … let a15 = a0; a0` | `recursive binding: a0 → a1 → … → a15 → a0` |
| Doubling chain `let a0 = audio.onset; let a1 = a0 + a0; … a15` | accepted; cost linear (16 stores, 15 adds, 30 loads, 1 read, 1 final load = 63); value 2¹⁵ × onset |
| A cost-256 formula compiled with `maximumOperationCost: 100000` and cost 300 | compiles; refused by the frame set with the loosened-limit message |

Exact positions are fixed by the tests (`ExpressionPathologicalTests`).

## B4 Compile work bounds

Counters: lexer = 1 (length check) + bytes visited by each scan; parser = grammar-rule entries +
token advances; compiler = nodes resolved + bindings named + dependency visits + references followed
+ loop-report steps + instructions emitted. With `b` = min(source bytes, `maximumSourceBytes`) and
`t` = tokens produced (end included):

- `lexerSteps ≤ 2b + 1`
- `parserSteps ≤ 6t + 6`
- `compilerSteps ≤ 5t`
- at the standard limits, `total ≤ 4096` for every source of any length.

## B5 Cost equals work

For every compiled formula, `operationCost == Σ ExpressionLimits.cost(of: $0.opcode)` over
`instructions`, and the opcode set has no jump; so evaluation work equals the static cost and the
snapshot's work equals `operationCost` (Σ of its formulas).
