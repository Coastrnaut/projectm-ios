# Research: SHD-002 Node-Based Generator Graph

Decisions taken by Claude under owner rule 4 (best judgement), 2026-11-13.

## SHD-002-D1: Document format

- **Decision**: JSON-compatible Codable value: `{"format": "projectm-ios.generator-graph",
  "version": 1, "name": …, "speed": …, "nodes": [{"id", "kind", "inputs": {input: nodeID},
  "values": {name: number | [numbers]}}]}`. Each node has exactly one output, so a connection is
  "input ← node ID" and edges need no separate list. Unconnected inputs use their literal value or
  the kind's default; settings are literals only. Unknown keys are ignored by decoding (forward
  compatible); a higher `version` is refused.
- **Rationale**: the smallest format that makes cycles, types and determinism checkable, readable
  by people, and simple for SHD-011 to bound (no references other than node IDs, no expressions,
  no strings that are interpreted).
- **Alternatives**: separate edge list with port-to-port links (more failure modes: dangling or
  duplicate links, multi-output nodes); an expression string per node (that is SHD-009's DSL and
  would be parsed text).

## SHD-002-D2: How a graph is drawn (GPU cost versus complexity)

- **Decision**: one fixed fragment program interprets the plan per pixel: a loop over at most 64
  fixed-size instructions read from a GPU buffer, a `switch` on the operation, operands from 16
  four-number registers or literals in the instruction. One pipeline serves every graph.
- **Evidence**:
  - Multi-pass alternative (one pass per node into an intermediate rgba16Float picture): at the
    iPhone 15's 1179 × 2556 a picture is 24 MB; a 12-node graph writes 12 and reads about 18
    (inputs) pictures per frame, roughly 720 MB per frame or 43 GB/s at 60 fps, beyond the device's
    memory bandwidth budget for one layer, plus 12 extra textures (288 MB) resident.
  - Uber-kernel: no intermediate memory; the cost is per-pixel ALU for ≤ 64 instructions with
    branch-free uniform control flow (every pixel runs the same instruction sequence, so the
    `switch` does not diverge within a SIMD group). Host GPU timing of a 12-node graph against
    SHD-001's Noise Flow at 1179 × 2556 is recorded below by SHD-002-T21.
  - Per-graph generated source: forbidden (ADR-0018 decision 3).
- **Rationale**: lowest memory traffic, no per-graph compile (instant graph switching), and the
  smallest safety surface (data only).

### Host measurement (SHD-002-T21)

Filled in by SHD-002-T21.

## SHD-002-D3: Cycle detection and ordering

- **Decision**: reuse the approach of MOD-014's validator (`ModulationGraphValidator.swift`, specs/035), not its code: an iterative
  Tarjan pass with an explicit stack finds strongly connected components; each component with more
  than one node, or a node feeding itself, is one cycle. Its readable path starts at the
  component's smallest node ID and follows, at each step, the smallest-ID successor inside the
  component that leads back to the start along a shortest path (breadth-first search). Cycles are
  reported in order of their start ID. An acyclic graph is ordered with Kahn's algorithm whose ready
  set is ordered by node ID (UTF-8 bytes).
- **Rationale**: MOD-014's validator works on `ModulationEdge`s of a parameter registry and is
  internal to ParameterGraph; its types do not fit picture nodes, and Compositor does not depend on
  ParameterGraph for this target. The approach (iterative, stable, readable paths) is what matters.
- **Alternatives**: recursive DFS (unbounded recursion on hostile input), a dependency on
  ParameterGraph (unneeded coupling).

## SHD-002-D4: Node set

- **Decision**: 24 kinds in six groups (sources: coordinates, time, musicLevel; time: oscillate,
  spin, drift; transforms: scale, rotate, translate, polar; shapes and noise: circle, ring, box,
  noise; math: add, multiply, clamp, smoothstep, wave, component; color: gradient, palette, hsv,
  mixColor, scaleColor; plus output). Types scalar, point, color, phase; unconnected point inputs
  read the picture coordinates.
- **Rationale**: covers the roadmap's "noise, color, transform and shape" plus the time and music
  inputs the looks need; each kind has a closed-form derivative bound (D5).
- **Alternatives**: feedback/previous-frame nodes (unbounded brightness build-up, as SHD-001
  rejected), blur (needs neighbours: multi-pass), texture nodes (file input: SHD-011's question).

## SHD-002-D5: Flash bound

- **Decision**: for each value the compiler keeps `m` (bound on the largest absolute component),
  `dp` (bound on its change per unit of phase) and `da` (per unit of music level), propagated per
  kind with the chain rule using max-norm bounds (spatial Lipschitz constants: smoothstep 1.5 per
  edge width, value noise 3 per cell, rotation √2, etc.; polar of a moving point is unbounded).
  The output's `dp` and `da` give `speedCap = min(1, π / dp)` and `musicRate = min(1, π / da)`, so
  no channel of any pixel changes faster than π per second from time or from music (the slope of a
  full-range cosine at 1 Hz, SHD-001's per-term limit). A graph with `dp` or `da` above 64π is
  rejected.
- **Rationale**: a structural rule that holds for every graph without simulating it, that slows
  rather than rejects most combinations, and that a strobe attempt cannot get around.
- **Limits of the argument**: it is a per-pixel slope bound, not a proof of the FX-019 envelope
  (small fast oscillations could in principle still count as transitions); the composite flash
  guard remains the guarantee for the finished picture, and the tests measure the envelope on
  read-back pictures.

## SHD-002-D6: Time precision

- **Decision**: the phase is a Double integrated from the clamped frame durations; each frame the
  CPU reduces every time term (`fract(rate · phase + offset)` for oscillate, spin and palette shift;
  `velocity · phase` wrapped to ±1024 for drift) and passes 64 four-number terms with
  `setFragmentBytes`. The GPU never sees the raw phase.
- **Rationale**: no precision loss over long sessions; periodic terms never jump. A drift wraps once
  every ≥ 1024 s at full speed (a visible jump the composite guard handles); documented.

## SHD-002-D7: Module boundaries

- **Decision**: target `GeneratorGraph` in Packages/Compositor, depending on Compositor only; no
  Foundation in the module (documents are Codable; callers decode); examples built in code.
- **Rationale**: Linux build, no file access to scan for, SHD-011 owns importing.
