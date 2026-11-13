# ADR-0021: Expression Mapping Language

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: SHD-009 (`specs/045-shd-009-expression-mapping-dsl`)
- **Constitution**: I, VI, VII, X; Security (untrusted input); FR-068
- **Builds on**: ADR-0018 (content is data, no shader source from content), ADR-0019 (closed
  operation sets, validation before anything runs), ADR-0012 (parameter registry, MOD-002 features)

## Context

SHD-009 must "evaluate a restricted numeric expression over known audio parameters", and its
acceptance is that the parser "rejects unknown identifiers, recursion and excessive complexity".
SHD-010 (P0) will add operation and time budgets for expression graphs, and SHD-011 (P0) will
accept user-authored content from imported files. A formula is the app's first piece of
user-written text that is executed, so it must be safe by construction, not by review of each
formula.

## Decisions

1. **A formula is data, run by a fixed interpreter.** A hand-written byte lexer and
   recursive-descent parser build a small tree; a compiler emits a closed stack-machine
   instruction set with permanent opcodes (`ExpressionOpcode`) and no jumps; one `switch` loop
   evaluates it. Nothing is generated as Swift, Metal or any other source; `NSExpression`,
   JavaScriptCore, `eval`, dynamic loading and process launching are not used.
2. **The module cannot reach those facilities.** `ParameterExpression` is its own target in
   `Packages/ParameterGraph`, depending on `ParameterGraph` only; it does not import Foundation,
   so the system expression evaluators are not even in scope. Its one other import is the platform
   C math library (`sin`, `cos`, `pow`). `ExpressionSourceSafetyTests` scans the module's sources
   for imports and forbidden facilities and fails if that changes.
3. **Closed names.** Identifiers are MOD-002's audio features (parsed only by
   `AudioFeatureSource(id:)`), `time` and the constants `pi`, `tau`, `e`; functions are a whitelist
   of 13 with fixed argument counts (`min max clamp abs sin cos floor fract mix smoothstep step sqrt
   pow`). Anything else is "unknown".
4. **Declarative bindings, never recursive.** `let name = expr;` bindings may appear in any order;
   the compiler orders them by dependency and rejects a binding that reaches itself, reporting the
   loop as a path (`a → b → a`) from its first binding in source order. Each binding is evaluated
   once into a slot, so sharing never multiplies work. There are no loops, user functions or
   assignments.
5. **Static limits with exact errors.** Source ≤ 512 bytes, ≤ 256 tokens, ≤ 128 nodes, nesting ≤ 16
   (parentheses, call arguments, unary operands; flat chains stay at one level), ≤ 16 bindings and a
   static weighted operation cost ≤ 256 (transcendental functions and `smoothstep` cost 4). The
   parser checks nesting before each descent, so its own recursion is bounded. Errors are the
   first problem in a fixed phase order, formatted `line:column: reason`. Limits are one value
   (`ExpressionLimits`), so SHD-010 can lower them per graph; since there are no loops, the static
   cost is exactly the work done, and SHD-010's time budget can be derived from it.
6. **Total, finite arithmetic.** Every instruction's result is made finite (NaN → 0, ±∞ → ± the
   largest finite number); `x / 0` → 0 (as in MilkDrop preset equations); `sqrt` of a non-positive
   number → 0; non-finite inputs read 0. Evaluation never traps and never returns NaN or infinity.
   Scratch values live in one buffer of `slots + maximum stack depth` doubles, sized at compile
   time and placed on the stack by `withUnsafeTemporaryAllocation`, so evaluation does not touch the
   heap. Results are bit-identical for the same inputs on one platform (one C math library);
   identity across CPU architectures is not required.
7. **Adapter only in this row.** `ExpressionMapping` limits a formula's value to the 0…1 position
   and maps it with MOD-003's interpolation, so formulas reach parameters only through the existing
   MOD-001/MOD-002 clamping; it reports the features read (for MOD-014 graph edges). Wiring
   mappings into `AudioFeatureModulator` bindings and saving them in presets are later rows.
8. **For SHD-011**: imported formulas are compiled with these limits after the import's own size
   check; no imported text can reach code generation, dynamic loading or native code.

## Consequences

- A formula can be shown, stored and shared as plain text; its compiled form has a stable byte
  encoding (`CompiledExpression.bytes`) for determinism tests and caching.
- Authors cannot write loops or recursive helpers; anything beyond the language needs a new
  whitelisted function and a new opcode (reviewed, tested, appended with a new permanent value).
- `audio.bandMean` costs 1 although it reads every band (≤ 128); SHD-010 may weight it when it
  sets time budgets.
- Not measured: an allocation counter during evaluation (the no-heap property rests on the
  standard library's stack placement of small temporary allocations and code review).
