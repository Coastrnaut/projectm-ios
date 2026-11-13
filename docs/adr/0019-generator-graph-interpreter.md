# ADR-0019: Generator Graph Interpreter

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: SHD-002 (`specs/042-shd-002-node-generator-graph`)
- **Constitution**: I, VI, X; Security (untrusted input); FR-068
- **Builds on**: ADR-0018 (procedural material shaders), ADR-0013 (layer contract), ADR-0011
  (strobe safety envelope)

## Context

SHD-002 lets a look be assembled from built-in noise, shape, transform, color, math, time and
music nodes, and must "compile deterministically and reject cycles". ADR-0018 decision 3 forbids
generating Metal source from user input: a graph may only combine code authored in the app.
SHD-011 (P0) will accept graphs from imported files, so the graph format is the app's first
user-supplied visual content and must be safe by construction. Graphs can also multiply time, so
SHD-001's per-parameter speed bounds are not enough on their own.

## Decisions

1. **A graph is a versioned, declarative document** (`projectm-ios.generator-graph`, version 1):
   nodes with stable IDs, a kind from a closed set of 26 (`GraphNodeKind`, permanent opcodes),
   connections by node ID and range-checked literal numbers. Nothing in a document is code, a
   path, an expression or a name that is looked up anywhere except the kind table. Documents from a
   newer version are refused.
2. **Validation before anything runs**: readable issues naming node and input (contract table);
   limits of 64 nodes, 128 connections, a 32-node chain and 16 live values; oversized input stops
   validation at once. Cycles are found with an iterative Tarjan pass (MOD-014's approach, not its
   code) and reported as paths from their smallest node ID.
3. **One fixed interpreter draws every graph.** The compiler emits fixed-size 80-byte instructions
   (opcode, registers, literals, settings) in dependency order with ties broken by node ID, so the
   same graph always gives byte-identical plans. The module's single shader constant
   (`GeneratorGraphShaders.source`) loops over at most 64 instructions per pixel and switches on the
   opcode; it is compiled once per device with `makeLibrary(source: Self.source, options:)`, the
   module's only library creation, and one pipeline can serve every graph layer.
   `GraphSourceSafetyTests` scans the module and fails if that changes. Rejected: one render pass
   per node through intermediate pictures (about 720 MB of picture traffic per frame for a 12-node
   graph at iPhone 15 size) and per-graph generated source (forbidden by ADR-0018). Measured on the
   host GPU (M5 Max) at 1179 × 2556: a 12-node graph 0.56 ms median against 0.18 ms for SHD-001's
   Noise Flow (research SHD-002-D2); device cost is SHD-002-T24 `{device}`.
4. **Flash safety by types, a compiled rate bound, then the guard.** Time is a separate "phase"
   type that only bounded inputs accept (|rate| ≤ 1); the graph speed is at most 1; music reaches a
   graph only through a follower that changes at most 1 per second. The compiler bounds how fast the
   output color can change per unit of phase and of music (chain rule with each operation's
   Lipschitz constant) and caps the speed and the follower so that neither can move a color channel
   faster than π per second (a full-range cosine at 1 Hz, SHD-001's per-term limit); a graph that
   would need less than 1/64 of normal speed is refused. This is a per-pixel slope bound, not a proof
   of the FX-019 envelope; every graph also draws under the composite flash guard, and tests measure
   the envelope on read-back pictures (examples at defaults, strobe attempts).
5. **Time precision**: the phase is a Double; the CPU reduces each instruction's time term each frame
   (`fract` for periodic terms, drift wrapped to ±1024), so long sessions never lose precision.
6. **For SHD-011**: importing must decode a document with a byte-size limit before validation (this
   module reads no files and has no Foundation); after decoding, this ADR's validation, limits and
   interpreter apply unchanged, and no imported content can reach shader compilation, dynamic
   loading or native code.
7. **No editor in this row.** No roadmap row owns a node editor yet; it is a follow-up after SHD-003
   (inspector metadata), SHD-005 and SHD-006 (gradient and noise editors). The kind table
   (`GraphNodeKind.spec`) and per-node messages are the editor's data.

## Consequences

- New node kinds need a new opcode, an interpreter branch, a rate-bound rule and tests; the module
  constant changes, so the scan and golden signatures guard them.
- The interpreter costs about 3 times a hand-written material on the host; graphs that need more
  speed can become curated materials (SHD-001) instead.
- Sharp moving edges and fast noise drift are slowed by the bound; that is the intended trade-off.
