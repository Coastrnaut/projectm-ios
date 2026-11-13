# Tasks: SHD-002 Node-Based Generator Graph

**Input**: Design documents from `specs/042-shd-002-node-generator-graph/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/generator-graph.md,
quickstart.md

**Tests**: Requested by the spec (SHD-002-R4-R7, R9, R10, R12-R15) and owner rule 7 budgets: a unit
test about 1-2 s and at most 10 s, the package suite under 1 minute, GPU tests at 64 × 64.

**Format**: `[ID] [P?] [Story] Description`. `{device}` = needs D1-D3 and a person; left open by
this row.

## Phase 1: Setup

- [ ] SHD-002-T01 Add the `GeneratorGraph` target (dependency Compositor), the `GeneratorGraphTests` test target (adds Compositor, FlashSafety, AnalysisFeatures, ProceduralMaterials for the cost comparison) and the target in the `Compositor` library product in `Packages/Compositor/Package.swift`, with one header-comment paragraph; nothing else in the file changes

## Phase 2: Foundational (blocks every story)

- [ ] SHD-002-T02 [P] `GeneratorGraphDocument` (format `projectm-ios.generator-graph`, version 1, name, speed default 0.2, nodes), `GraphNode` (id, kind, inputs, values; empty maps omitted when encoding), `GraphValue` (number or array of numbers; Codable) in `Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphDocument.swift`
- [ ] SHD-002-T03 [P] `GraphPortType` (scalar, point, color, phase) and `GraphNodeKind` (the 24 kinds of data-model.md with each kind's inputs: name, type, range, default or required; settings: name, range, default, whole-number flag; output type; opcode) in `Packages/Compositor/Sources/GeneratorGraph/GraphNodeKind.swift`
- [ ] SHD-002-T04 [P] `GeneratorGraphIssue` with every case of the contract table and its exact `message`, number formatting (whole numbers as integers), `GeneratorGraphValidationError` in `Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphIssue.swift`

## Phase 3: User Story 1 - Describe a picture as connected nodes (P1) MVP

**Goal**: a document compiles to a plan and a layer draws it.
**Independent test**: `GraphDocumentTests`, `GraphRenderTests.testExamplesDrawValidFrames`.

- [ ] SHD-002-T05 [US1] Validator: document checks (format, version, name ≤ 64 characters, speed finite −1…1), early stop on > 64 nodes or > 128 connections, node checks (ID pattern `[A-Za-z][A-Za-z0-9_-]{0,31}`, duplicates, kind, names, connected settings, connected-and-set, missing source, source is output, type mismatch, phase literal, missing required input, value shape, finite, range, whole numbers, setting rules), output count in `Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphValidator.swift`
- [ ] SHD-002-T06 [US1] Rate bounds per kind (`m`, `dp`, `da` as in data-model.md "Bound") in `Packages/Compositor/Sources/GeneratorGraph/GraphRateBound.swift`
- [ ] SHD-002-T07 [US1] Compiler: reachable nodes from the output, Kahn order with ready set by node ID (UTF-8 bytes), registers (lowest free; freed after last use; ≤ 16), instructions (op, dst, sources, literals clamped to range, settings, time term), bounds → `speedCap`, `musicRate`, `tooFast` above 64π, `CompiledGeneratorGraph` with `planBytes` in `Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphCompiler.swift` and `Packages/Compositor/Sources/GeneratorGraph/CompiledGeneratorGraph.swift`
- [ ] SHD-002-T08 [P] [US1] `GraphMotion` (dt clamp 0…0.1 s, NaN 0; band level mean of finite bands clamped 0…1; level moves ≤ musicRate·dt; phase += dt·speed; reset) and per-frame time terms (`fract` in Double; drift wrapped to ±1024) in `Packages/Compositor/Sources/GeneratorGraph/GraphMotion.swift`
- [ ] SHD-002-T09 [US1] The interpreter constant `GeneratorGraphShaders.source` (full-screen vertex, one fragment `graph_main` looping ≤ 64 instructions over 16 registers; output clamped 0…1, alpha 1, non-finite → 0) and `makeLibrary(device:)`, the module's only library compile, in `Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphShaders.swift`
- [ ] SHD-002-T10 [US1] `GeneratorGraphPipeline` (shared per device) and `GeneratorGraphLayer` (CMP-001 `LayerSource`, transparent fallback, plan buffer made in `prepare`, `render` advances motion and draws with `setFragmentBytes`; `speed` clamps to ±speedCap) in `Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphLayer.swift`
- [ ] SHD-002-T11 [P] [US1] Three example documents (Ember Drift, Hue Rings, Soft Orbs) in `Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphExamples.swift`
- [ ] SHD-002-T12 [P] [US1] Document tests: JSON round-trip of every example (encode, decode, equal; compile equal), decoding the contract's example JSON, kind catalog (24 kinds, unique opcodes, defaults inside ranges, required inputs only phase/color as documented) in `Packages/Compositor/Tests/GeneratorGraphTests/GraphDocumentTests.swift`
- [ ] SHD-002-T13 [US1] GPU rig and render tests: every example draws a non-blank, finite, opaque, premultiplied-valid 64 × 64 frame, also through the `Compositor`; 1 × 1 and 97 × 13 draw; bad bands still valid; golden signatures (frame 30 at 60 Hz, no music: mean, peak, pixels (32,32), (8,8), (56,16), (16,56); tolerance 0.02) in `Packages/Compositor/Tests/GeneratorGraphTests/GraphGPURig.swift` and `Packages/Compositor/Tests/GeneratorGraphTests/GraphRenderTests.swift`

## Phase 4: User Story 2 - Compilation is deterministic (P1)

**Goal**: same graph → same plan bytes and same pixels.
**Independent test**: `GraphCompilerTests`, `GraphRenderTests.testRendersAreDeterministic`.

- [ ] SHD-002-T14 [P] [US2] Compiler tests: compile twice → identical `planBytes`; node order reversed and shuffled (fixed seed) → identical bytes; order is dependency order with ID tie-break (fixture); unreachable nodes omitted; registers reused (a 12-node chain needs ≤ 3); time terms and bounds for fixtures (speedCap, musicRate values) in `Packages/Compositor/Tests/GeneratorGraphTests/GraphCompilerTests.swift`
- [ ] SHD-002-T15 [US2] Render determinism: two layers of each example over the same 60-frame sequence with bands are bit-identical; one shared pipeline draws two different graphs in `Packages/Compositor/Tests/GeneratorGraphTests/GraphRenderTests.swift`
- [ ] SHD-002-T16 [US2] Property test (seed fixed): 200 random type-correct DAGs (2-24 nodes, random kinds, connections and in-range values) all compile or are refused only with `tooFast`/`tooManyLiveValues`; each compiled one is byte-identical when compiled again and shuffled; the first 20 compiled draw 3 frames at 32 × 32 with finite, valid pixels; under 1 s on the host in `Packages/Compositor/Tests/GeneratorGraphTests/GraphPropertyTests.swift`

## Phase 5: User Story 3 - Invalid graphs are rejected with readable reasons (P1)

**Goal**: every problem kind gives its exact message; cycles give paths.
**Independent test**: `GraphValidationTests`.

- [ ] SHD-002-T17 [US3] Iterative Tarjan cycle finder (explicit stack), readable path from the smallest ID along a breadth-first shortest path inside the component, cycles ordered by start ID; longest chain (≤ 32) after the acyclic check in `Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphValidator.swift`
- [ ] SHD-002-T18 [P] [US3] Validation tests: one fixture per issue case with its exact message; three-node cycle "a → b → c → a" from any start order; self-loop "a → a"; two cycles in stable order; a cycle not reaching the output still rejected; 65 nodes, 129 connections, a 33-node chain and 17 live values each rejected with the limit message; valid fixtures produce no issues in `Packages/Compositor/Tests/GeneratorGraphTests/GraphValidationTests.swift`

## Phase 6: User Story 4 - No graph can make the picture strobe (P1)

**Goal**: bounded time and music; strobes refused or slowed; defaults inside Reduce flashing.
**Independent test**: `GraphMotionTests`, `GraphFlashSafetyTests`.

- [ ] SHD-002-T19 [P] [US4] Motion tests: phase accumulation, dt clamp and NaN, band level, follower rate (alternating 0/1 bands every frame moves ≤ musicRate·dt per frame), reset, time terms stay in range after 10⁶ s in `Packages/Compositor/Tests/GeneratorGraphTests/GraphMotionTests.swift`
- [ ] SHD-002-T20 [US4] Flash tests: each example at defaults, 120 frames at 60 Hz, no music and steady music 0.6: every one of 17 areas ≤ 2 transitions per window under Reduce flashing; through the `Compositor` with Reduce flashing on, guard gain stays 1; strobe attempts: (a) oscillate → multiply 8 → wave 4 → gradient black/white is refused (`tooFast`); (b) oscillate → wave 2 → gradient black/white compiles with speedCap < 1 and, at speed 1 (clamped) with full music, stays ≤ 6 transitions per window; (c) musicLevel → wave 16 → gradient with bands alternating 0/1 every frame stays ≤ 6 in `Packages/Compositor/Tests/GeneratorGraphTests/GraphFlashSafetyTests.swift`
- [ ] SHD-002-T21 [US4] Host GPU cost bench (runs only with `SHD002_BENCH=1`, no assertion on time): a 12-node graph versus SHD-001 Noise Flow at 1179 × 2556, GPU start/end times over 60 frames; record the result in research.md SHD-002-D2 in `Packages/Compositor/Tests/GeneratorGraphTests/GraphCostBench.swift`

## Phase 7: User Story 5 - Graph content can never become code (P1)

**Goal**: data only, enforced by a scan.
**Independent test**: `GraphSourceSafetyTests`.

- [ ] SHD-002-T22 [P] [US5] Source scan of `Packages/Compositor/Sources/GeneratorGraph/*.swift`: exactly one `device.makeLibrary(source: Self.source,` in `GeneratorGraphShaders.swift` and one call of it; the shader literal has no interpolation and only `#include <metal_stdlib>`; no `contentsOf`, `URL(`, `URLSession`, `Bundle`, `FileManager`, `FileHandle`, `makeDefaultLibrary`, `dlopen`, `dlsym`, `NSClassFromString`, `import Foundation`, `import Network`; a document with kind `"#include <x>"` or a Metal snippet is refused as unknown kind, and the name field never reaches the plan bytes in `Packages/Compositor/Tests/GeneratorGraphTests/GraphSourceSafetyTests.swift`
- [ ] SHD-002-T23 [US5] ADR at the next free number (re-checked across branches at commit): the interpreter decision (D2), the flash bound (D5), the safety argument for SHD-011, the editor deferral; row in `docs/adr/README.md`

## Phase 8: Device stage (last)

- [ ] SHD-002-T24 {device} Frame cost of the 12-node bench graph on D1, D2 and D3 (GPU time per frame at native size), recorded in `docs/test-reports/performance.md`

## Phase 9: Polish

- [ ] SHD-002-T25 Linux shape (`--scratch-path .build/linuxshape` with the three `-D` flags) and one `xcodebuild test -scheme Compositor` run on a dedicated iOS 27.2 simulator (deleted afterwards; PosterBoard reports counted before and after); `validate_docs.py` and `check_compliance.py` pass; spec status updated

## Dependencies

T01 → T02-T04 → T05-T07 (T08, T11 parallel) → T09-T10 → T12-T13 → US2-US5 phases (T17 extends
T05; T14, T18, T19, T22 can run in parallel once T07 exists) → T21 → T23 → T25. T24 is last and
open.

## Implementation Strategy

MVP = Phase 3 (a compiled example draws). Then determinism, validation table, flash and safety
tests, ADR, polish. One writer; commits after each complete change.
