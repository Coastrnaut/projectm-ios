# Data Model: SHD-010 Expression Sandbox Budgets

## Cost table (`ExpressionLimits.cost(of:)`)

| Opcode | Cost |
|---|---|
| `sin`, `cos`, `sqrt`, `pow`, `smoothstep`, `bandMean` | 4 |
| every other opcode | 1 |

Invariant: `CompiledExpression.operationCost == Σ cost(of: instruction.opcode)` and every
instruction runs exactly once per evaluation.

## ExpressionFrameBudget

| Field | Type | Default | Rule |
|---|---|---|---|
| `maximumExpressions` | Int | 32 | formulas per frame |
| `maximumOperationCost` | Int | 2048 | Σ formula cost per frame (inclusive) |
| `expressionLimits` | ExpressionLimits | `.standard` | each admitted formula's `limits` must be field-by-field ≤ these |

## ExpressionFrameSet (builder; value type)

- `budget`, `usedCost` (Σ admitted cost), `count`, `handles` (admission order).
- `admit(_ expression: CompiledExpression) throws(ExpressionBudgetError) -> Handle`: checks loosened
  limits, then count, then cost; on refusal the set is unchanged.
- `remove(_ handle: Handle) -> Bool`: true when something was removed; frees its cost.
- `snapshot`: an `ExpressionFrameSnapshot` of the current entries.
- `Handle`: `rawValue: UInt64`, issued from 1 upward, never reused within one set.

## ExpressionFrameSnapshot (immutable, Sendable)

- `expressions` and `handles` in admission order; `operationCost`.
- `evaluate(_ inputs: ExpressionInputs, into results: UnsafeMutableBufferPointer<Double>) -> Int`:
  writes `min(count, results.count)` results, returns that number.

## ExpressionBudgetError

Reasons: `looserLimit(field, value, standard)`, `tooManyExpressions(limit)`,
`costOverBudget(cost, total, limit, used)`. Messages: contract B2.

## ExpressionCompileWork

`lexerSteps`, `parserSteps`, `compilerSteps`, `total`; `bound(for:limits:)` helpers per contract B4.
