# Contract: SHD-009 Expression Language

Module `ParameterExpression` (`Packages/ParameterGraph`). A formula is data: this contract is the
whole language. Anything not listed here is rejected.

## E1. Lexical rules

- The source is at most `maximumSourceBytes` (512) UTF-8 bytes.
- Whitespace: space, tab, carriage return, line feed. A line feed starts a new line; positions are
  1-based `line:column`, columns counting bytes.
- Names: `[A-Za-z_][A-Za-z0-9_]*`, optionally followed by `.` segments `[A-Za-z0-9_]+`
  (`audio.band.3` is one name). `let` is a keyword.
- Numbers: `[0-9]+ ("." [0-9]+)? ([eE] [+-]? [0-9]+)?`, decimal only, no sign (unary `-` applies).
  A number directly followed by a letter, digit, `_` or `.` is malformed (`1.`, `1e`, `1.2.3`,
  `0x1F`, `12abc`); its text runs to the end of that run of characters. A number whose value is not
  finite (`1e400`) is out of range.
- Punctuation: `( ) , ; = + - * /`.
- Any other printable character is an unexpected character; any other byte (control characters,
  non-ASCII) is an unexpected byte.
- At most `maximumTokens` (256) tokens (the end of input is not a token).

## E2. Grammar

```text
program  = { "let" name "=" expr ";" } expr END
expr     = term { ("+" | "-") term }
term     = unary { ("*" | "/") unary }
unary    = ("+" | "-") unary | primary
primary  = number | name | name "(" [ expr { "," expr } ] ")" | "(" expr ")"
```

Binary operators are left-associative; `*` `/` bind tighter than `+` `-`; unary operators bind
tighter than both (`-2 * 3` is `(-2) * 3`).

- **Nodes**: each number, name, call, unary operator and binary operator is one node; parentheses
  are free. At most `maximumNodes` (128) across the bindings and the result; the error is at the
  token that would add node 129.
- **Nesting**: entering a parenthesis group, a call's arguments or a unary operand adds one level;
  the top level is 0; at most `maximumNesting` (16) levels; the error is at the `(` or operator
  that would open level 17.
- **Bindings**: at most `maximumBindings` (16); the error is at the 17th `let`.

## E3. Identifiers (closed set)

| Name | Value |
|---|---|
| `audio.band.0` … `audio.band.127` | MOD-002 band level (decimal index without leading zeros; a band missing from the frame reads 0) |
| `audio.bandMean` | MOD-002 mean of the frame's bands (0 without bands) |
| `audio.onset` | MOD-002 onset value (0 when absent) |
| `audio.beatConfidence` | MOD-002 beat confidence (0 when absent) |
| `time` | the time in seconds passed to evaluation (non-finite → 0) |
| `pi`, `tau`, `e` | π, 2π, Euler's number (`Double.pi`, `2 * Double.pi`, `2.718281828459045`) |
| binding names | the formula's own `let` bindings |

Non-finite audio readings are 0 (MOD-002-R6).

## E4. Functions (closed whitelist)

| Function | Arity | Cost | Result (then made finite, E6) |
|---|---|---|---|
| `min(a, b)`, `max(a, b)` | 2 | 1 | smaller, larger |
| `clamp(x, lo, hi)` | 3 | 1 | `min(max(x, lo), hi)` (`hi` wins when `lo > hi`) |
| `abs(x)` | 1 | 1 | magnitude |
| `sin(x)`, `cos(x)` | 1 | 4 | platform C math library, radians |
| `floor(x)` | 1 | 1 | largest whole number ≤ x |
| `fract(x)` | 1 | 1 | `x − floor(x)` |
| `mix(a, b, t)` | 3 | 1 | `a + (b − a) · t` (t not clamped) |
| `smoothstep(e0, e1, x)` | 3 | 4 | `t = clamp((x − e0)/(e1 − e0), 0, 1)`, `t·t·(3 − 2t)`; `e0 = e1` → `step(e0, x)` |
| `step(edge, x)` | 2 | 1 | 0 when `x < edge`, else 1 |
| `sqrt(x)` | 1 | 4 | 0 when `x ≤ 0`, else the square root |
| `pow(x, y)` | 2 | 4 | platform C `pow`; NaN (negative base, fractional exponent) → 0, overflow → largest finite |

## E5. Bindings

- `let name = expr;` names a value. Names: no `.`; not `let`, `time`, `pi`, `tau`, `e`, `audio`
  or a function name; not repeated.
- Bindings may be written in any order; a binding is computed once per evaluation, after the
  bindings it uses. A binding used by itself, directly or through other bindings, is recursive and
  rejected. Unused bindings are allowed (computed and counted).

## E6. Evaluation

- Every instruction's result is made finite: NaN → 0, +∞ → `Double.greatestFiniteMagnitude`,
  −∞ → `-Double.greatestFiniteMagnitude`. `x / 0` → 0 (also `0 / 0`).
- The result is always finite. Evaluation never traps, allocates nothing on the heap and runs
  exactly the compiled instructions (no loops).
- Same source and limits → identical `instructions` and `bytes`; same compiled expression and
  inputs → bit-identical result.
- Operation cost: 1 per instruction (`constant`, loads, `store`, arithmetic, `negate`, functions)
  except E4's cost-4 functions; unary `+` emits nothing. At most `maximumOperationCost` (256);
  the error is at the node whose instruction first takes the running total (in evaluation order:
  bindings in dependency order, then the result) over the limit.

## E7. Errors

The message is `line:column: reason`. Only the first problem is reported. Phases, in order (first
problem in source order within a phase):

1. Length (position of byte 513).
2. Characters and numbers (lexing, left to right).
3. Token count (position of token 257).
4. Syntax, nesting, node and binding counts (parsing, left to right).
5. Names: for each binding in source order its name, then its body; then the result —
   identifiers, functions, calls, argument counts.
6. Recursion: bindings in source order, depth-first, references in source order.
7. Operation cost.

| Reason | Message |
|---|---|
| source too long | `the source is 600 bytes; at most 512 are allowed` |
| unexpected character | `unexpected character '$'` |
| unexpected byte | `unexpected byte 0xC3` |
| malformed number | `malformed number '1.'` |
| number out of range | `number '1e400' is out of range` |
| too many tokens | `more than 256 tokens` |
| expected | `expected an expression, found ')'` · `expected ')', found end of input` · `expected end of input, found 'x'` |
| too deep | `nesting deeper than 16 levels` |
| too many nodes | `more than 128 expression nodes` |
| too many bindings | `more than 16 bindings` |
| unknown identifier | `unknown identifier 'audio.bass'` |
| unknown function | `unknown function 'tan'` |
| not a function | `'time' is not a function` |
| function without call | `function 'sin' needs arguments, as in sin(x)` |
| wrong argument count | `'clamp' takes 3 arguments, found 2` · `'abs' takes 1 argument, found 2` |
| invalid binding name | `binding name 'a.b' must not contain '.'` |
| reserved binding name | `'time' is a reserved name` |
| duplicate binding | `'x' is already defined` |
| recursion | `recursive binding: a → b → a` (self: `x → x`) |
| operation cost | `operation cost over 256` |

Token text in `expected` messages: punctuation, names and numbers in single quotes; the end as
`end of input`.

## E8. Mapping adapter

`ExpressionMapping(expression:outputStart:outputEnd:)`: `position(inputs)` =
`LinearMapping.clampedPosition(expression.evaluate(inputs))` (0…1); `map(inputs)` =
`LinearMapping.interpolate(from: outputStart, to: outputEnd, at: position)`; `isValid` when both
ends are finite. Range checks against a target parameter remain the binding's (MOD-002 contract
C2) when a later row wires mappings into bindings.
