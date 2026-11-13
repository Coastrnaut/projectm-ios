# Data Model: SHD-009 Expression Mapping DSL

All types live in the `ParameterExpression` module.

## ExpressionLimits (value, Sendable, Hashable)

| Field | Default | Meaning |
|---|---|---|
| `maximumSourceBytes` | 512 | UTF-8 bytes of the source |
| `maximumTokens` | 256 | tokens, punctuation included |
| `maximumNodes` | 128 | expression nodes across bindings and result (numbers, names, unary and binary operators, calls; parentheses free) |
| `maximumNesting` | 16 | levels: a parenthesis group, a call's arguments, a unary operand |
| `maximumBindings` | 16 | `let` bindings |
| `maximumOperationCost` | 256 | static weighted instruction count |

`ExpressionLimits.standard` holds the defaults. `ExpressionLimits.cost(of: ExpressionOpcode)`: 4 for
`sin`, `cos`, `sqrt`, `pow`, `smoothstep`, else 1.

## SourcePosition (value)

`line`, `column`: 1-based; columns count bytes. `description` = `"line:column"`.

## ExpressionError (Error, Sendable, Hashable, CustomStringConvertible)

`position: SourcePosition`, `reason: ExpressionError.Reason`; `description` =
`"\(position): \(reason)"`. Reasons and messages: see the contract's error table.

## Tree (internal)

`ExpressionNode` (indirect enum): `number(Double, at)`, `name(String, at)`, `unary(op, node, at)`,
`binary(op, lhs, rhs, at)`, `call(name, [node], at)`. `ParsedProgram`: `bindings: [(name, position,
node)]`, `result: node`.

## ExpressionOpcode (UInt8, permanent values)

| Value | Opcode | Operand | Stack |
|---|---|---|---|
| 1 | `constant` | literal | +1 |
| 2 | `time` | — | +1 |
| 3 | `band` | index 0…127 | +1 |
| 4 | `bandMean` | — | +1 |
| 5 | `onset` | — | +1 |
| 6 | `beatConfidence` | — | +1 |
| 7 | `load` | slot | +1 |
| 8 | `store` | slot | −1 |
| 10-14 | `add`, `subtract`, `multiply`, `divide`, `negate` | — | −1 (negate 0) |
| 20-32 | `min`, `max`, `clamp`, `abs`, `sin`, `cos`, `floor`, `fract`, `mix`, `smoothstep`, `step`, `sqrt`, `pow` | — | 1 − arity |

## ExpressionInstruction (value, Hashable)

`opcode`, `index: UInt16` (band or slot, else 0), `literal: Double` (constants, else 0). Equality
compares the literal's bit pattern.

## CompiledExpression (value, Sendable, Hashable)

| Field | Meaning |
|---|---|
| `source` | the source text |
| `instructions` | the instruction list (bindings first, in dependency order, then the result) |
| `slotCount` | number of bindings |
| `maximumStackDepth` | largest stack depth during evaluation |
| `operationCost` | static weighted cost (≤ the limit) |
| `audioSources` | MOD-002 features read, first-use order, no duplicates |
| `readsTime` | whether `time` is read |
| `bytes` | byte form: `"PMX"`, version 1, slot count, max stack, instruction count (UInt16 LE), then per instruction opcode (1), index (UInt16 LE), literal bit pattern (UInt64 LE) |

Created by `CompiledExpression(source:limits:) throws(ExpressionError)`.
`evaluate(_ inputs: ExpressionInputs) -> Double` (always finite).

## ExpressionInputs (value)

`frame: AudioFeatureFrame` (borrowed, MOD-002), `timeSeconds: Double`.

## ExpressionMapping (value)

`expression: CompiledExpression`, `outputStart`, `outputEnd`; `isValid` (ends finite);
`position(_:)` = MOD-003 `clampedPosition(evaluate)`; `map(_:)` = MOD-003
`interpolate(from: outputStart, to: outputEnd, at: position)`.
