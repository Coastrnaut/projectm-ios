# Research: SHD-009 Expression Mapping DSL

## SHD-009-D1: Where the language lives

- **Decision**: a new `ParameterExpression` target and product in `Packages/ParameterGraph`,
  depending only on the `ParameterGraph` target; no Foundation import.
- **Rationale**: identifiers must be exactly MOD-002's (`AudioFeatureSource(id:)` is the one
  parser of those names) and the mapping adapter reuses MOD-003's interpolation. A separate module
  without Foundation means `NSExpression`, `NSPredicate` and friends cannot be referenced at all;
  the source scan is a second line of defence.
- **Alternatives**: files inside the `ParameterGraph` target (that target imports Foundation in
  other files; only the scan would protect the boundary); a new package (more CI wiring for no
  gain).

## SHD-009-D2: Parser and evaluator

- **Decision**: a byte lexer and a recursive-descent parser with an explicit nesting counter (≤ 16)
  checked before each recursive descent, so parser recursion is bounded by construction; the tree
  is compiled to a stack-machine instruction list (permanent opcodes) evaluated by a `switch` loop.
- **Rationale**: the simplest structure whose termination and stack use are obvious; a stack
  machine gives a byte form for determinism tests and a static cost for SHD-010.
- **Alternatives**: evaluating the tree directly (recursive at run time, harder to bound and to
  serialize); `NSExpression` or JavaScriptCore (forbidden: ADR-0018, code execution surface);
  generating Metal or Swift source (forbidden).

## SHD-009-D3: Bindings and recursion

- **Decision**: declarative `let` bindings; references form a graph; a depth-first search over
  bindings in source order (references in source order) finds the first loop and reports it as
  `a → b → a` at the reference that closes it. Bindings compile in depth-first post-order into
  slots, each evaluated once.
- **Rationale**: makes "recursion" expressible and therefore testable (the acceptance) while
  keeping evaluation loop-free; slots avoid exponential inlining (`let b = a + a; let c = b + b`).
- **Alternatives**: sequential scope (a self-reference would just be "unknown", mutual recursion
  unrepresentable); inlining (node count could explode past limits after checking).

## SHD-009-D4: Numeric safety

- **Decision**: a finite-making step after every instruction (NaN → 0, ±∞ → ±`greatestFiniteMagnitude`),
  plus explicit rules: `x / 0` → 0, `sqrt(x ≤ 0)` → 0, `smoothstep(a, a, x)` → `step(a, x)`,
  non-finite inputs → 0. `sin`, `cos`, `pow` come from the platform C math library.
- **Rationale**: every stack value stays finite, so no operation sees NaN or infinity and the
  final result needs no special case; `x / 0 = 0` matches MilkDrop preset equations, which preset
  authors know. Results are deterministic per platform (one libm); bit-identity across CPU
  architectures is not required (spec Assumptions).
- **Alternatives**: trapping or throwing at run time (would stop the render path); custom
  polynomial `sin`/`cos`/`pow` for cross-platform identity (accuracy and maintenance cost without a
  requirement).

## SHD-009-D5: Limits and cost

- **Decision**: `ExpressionLimits` value with defaults 512 bytes, 256 tokens, 128 nodes, nesting 16,
  16 bindings, cost 256; cost 1 per instruction except `sin`, `cos`, `sqrt`, `pow`, `smoothstep`
  (4). Unary `+` emits nothing. `audio.bandMean` costs 1 although it reads every band (≤ 128); its
  true cost is a SHD-010 budget concern.
- **Rationale**: the defaults admit every realistic mapping formula (a few dozen tokens) while
  bounding worst-case work to a few hundred floating-point operations; one value lets SHD-010 tighten
  limits per graph.
- **Alternatives**: a runtime step counter (unnecessary: no loops, so the static count is exact).

## SHD-009-D6: Evaluation memory

- **Decision**: the compiler computes the maximum stack depth; evaluation uses
  `withUnsafeTemporaryAllocation(of: Double.self, capacity: slots + maxStack)` (≤ 16 + 128 doubles),
  which the standard library places on the stack for small sizes, so evaluation does not touch the
  heap; `CompiledExpression` is an immutable `Sendable` value.
- **Rationale**: no per-evaluator object to own or share, safe from any thread.
- **Alternatives**: an evaluator class holding a preallocated buffer (not `Sendable`, one per
  thread); `ContiguousArray` per call (allocates).
