# Tasks: MOD-014 Modulation Feedback Prevention

**Input**: Design documents in `specs/035-mod-014-modulation-feedback-prevention/` (spec.md, plan.md,
research.md, data-model.md, contracts/modulation-graph.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change. Budgets (owner rule 7): each unit
test well under 1 s on the host, the package suite under 1 minute; representative cases only; no
wall-clock assertions.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). No `{device}` or `{sim}` task: the row changes no app code. Inside descriptions
"T03" is short for `MOD-014-T03`. A task is ticked only when its acceptance evidence was produced,
with " — Verified <date>: <how>" appended. Logs go to `.build/scratch/`.

## Phase 1: Setup

- [X] MOD-014-T01 Record the baseline: `swift test --package-path Packages/ParameterGraph` on the host (test count, failures). Evidence: counts recorded here. — Verified 2026-11-13: at c5a1217, ParameterGraph 48 tests on the host, 0 failures (0.021 s of tests; .build/scratch/mod014-T01.log).

## Phase 2: Foundational

- [X] MOD-014-T02 Create `Packages/ParameterGraph/Sources/ParameterGraph/ModulationGraph.swift` with the value types of data-model.md: `ModulationNode` (`.audio`, `.parameter`, `.generator`; `id`; order by `id` then kind audio < parameter < generator), `ModulationGenerator` (`id`, `displayName`, `inputs`), `ModulationEdge` (`source`, `target`, `input` default `"value"`), `ModulationGraph` (`generators`, `edges`, `maximumNodes = 1_024`, `maximumEdges = 4_096`), `ModulationCycle` (`edges`, `path`, `displayPath`), `ModulationGraphIssue` (problems listed in data-model.md), `ModulationGraphError` (`issues`, `description` one message per line). All `Sendable`, `Hashable`; no Foundation. Evidence: the package builds on the host. — Verified 2026-11-13: `swift build --package-path Packages/ParameterGraph` succeeds on the host with the model types (and a validator stub).

## Phase 3: User Story 1 - a loop is refused with a readable path (P1) MVP

**Independent test**: `ModulationGraphCycleTests`.

- [X] MOD-014-T03 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/ModulationGraphCycleTests.swift`: (a) the acceptance fixture (spec US1 scenario 1): exactly one `cycle` issue, `path == "lfo.one.rate → macro.a → visual.ring.gap → lfo.one.rate"`, `displayPath == "LFO One (rate) → Macro A → Ring gap → LFO One (rate)"`, message contains the path; (b) self-loop `lfo.one → lfo.one (rate)`: one `selfLoop` issue with path `lfo.one.rate → lfo.one.rate`; (c) two disjoint loops reported in ID order, identical across two validations and with edges given in reversed order; (d) diamond A → B, A → C, B → D, C → D, D → A: one cycle with path `a.n → b.n → d.n → a.n` (shortest, ties by ID); (e) a self-loop inside a larger loop: both issues; (f) the acceptance fixture without its closing edge is accepted (contract G5). — Verified 2026-11-13: written before the validator: 6 tests (acceptance, self-loop, disjoint loops, diamond, self-loop inside a loop, accepted without the closing edge). The acceptance path starts at the group's smallest ID (`lfo.one.rate → macro.a → visual.ring.gap → lfo.one.rate`); the brief's `macro.a → …` form is what the incremental check returns for the closing edge (spec and quickstart updated).
- [X] MOD-014-T04 [US1] Record the T03 red run; implement `Packages/ParameterGraph/Sources/ParameterGraph/ModulationGraphValidator.swift`: limits (G3), node indexing by stable ID, adjacency sorted by target index then input, iterative Tarjan (research MOD-014-D3), shortest loop per group by breadth-first search from the group's smallest node, self-loops, path and display path text (data-model.md), `ModulationGraph.validate(in:)` (G2, G5, G6). Evidence: T03 passes on the host. — Verified 2026-11-13: red run `cannot find 'ValidatedModulationGraph' in scope` (.build/scratch/mod014-red-T03.log); then ModulationGraphCycleTests 6 tests pass on the host, 0.003 s in all (.build/scratch/mod014-T04.log).

## Phase 4: User Story 2 - valid graphs get a stable evaluation order (P1)

**Independent test**: `ModulationGraphOrderTests` (order part), `ModulationGraphCycleTests` (chain, limits).

- [ ] MOD-014-T05 [P] [US2] Add to `ModulationGraphCycleTests.swift`: a 1,000-node generator chain validates with no issue and its evaluation order is the chain; 4,097 edges → exactly one `tooManyEdges` issue; 1,025 nodes → exactly one `tooManyNodes` issue (G3, G6); write `Packages/ParameterGraph/Tests/ParameterGraphTests/ModulationGraphOrderTests.swift` (order part): every edge's source precedes its target, independent nodes appear by ID, the order is identical for shuffled edge input, the empty graph gives an empty order; `ValidatedModulationGraph.init` throws `ModulationGraphError` listing every issue for the acceptance fixture (G7).
- [ ] MOD-014-T06 [US2] Record the T05 red run; implement `Packages/ParameterGraph/Sources/ParameterGraph/ValidatedModulationGraph.swift` with `evaluationOrder` (Kahn's algorithm, binary min-heap on the node index, research MOD-014-D4). Evidence: T05 passes on the host.

## Phase 5: User Story 3 - a connection is checked before it is made (P2)

**Independent test**: `ModulationGraphOrderTests.testIncrementalCheckMatchesFullValidation`.

- [ ] MOD-014-T07 [US3] Add to `ModulationGraphOrderTests.swift`: the acceptance fixture without its closing edge, `wouldCreateCycle(adding: lfo.one → macro.a)` returns the acceptance path; a self-connection returns a one-edge loop; an edge to a node not yet in the graph returns nil; property test with a fixed-seed generator (SplitMix64, 200 cases, 8-12 nodes, random acyclic edges): non-nil exactly when full validation of the graph plus the edge has a `selfLoop` or `cycle` issue, and a returned loop starts at the edge's target, ends with the edge, and each step's target is the next step's source (G8).
- [ ] MOD-014-T08 [US3] Record the T07 red run; implement `wouldCreateCycle(adding:)` in `ValidatedModulationGraph.swift` (breadth-first search from the edge's target to its source). Evidence: T07 passes on the host.

## Phase 6: User Story 4 - other mistakes are named, audio bindings behave as before (P2)

**Independent test**: `ModulationGraphIssueTests`, `ModulationGraphOrderTests.testAudioBindingsExpressAsGraphAndModulateIdentically`.

- [ ] MOD-014-T09 [P] [US4] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/ModulationGraphIssueTests.swift`: one fixture per problem (`malformedGeneratorID`, `emptyGeneratorName`, `duplicateGenerator`, `conflictingGeneratorID` for a registered, a retired and an `audio.` ID, `malformedInput`, `duplicateInput`, `unknownAudioFeature` (band 128 and −1), `unknownParameter`, `retiredParameter`, `unknownGenerator`, `audioTarget`, `unknownInput` (parameter input `rate`, undeclared generator input), `duplicateEdge`), each issue's message naming the connection or generator; a mixed fixture asserting the order of contract G4/G5 exactly; a connection with a problem is not also part of a reported loop.
- [ ] MOD-014-T10 [US4] Record the T09 red run if any; complete the structural checks in `ModulationGraphValidator.swift` (G4). Evidence: T09 passes on the host.
- [ ] MOD-014-T11 [US4] Add to `ModulationGraphOrderTests.swift`: three MOD-002 bindings → `modulationGraph` has three `audio → parameter.value` edges in binding order and validates; values over a fixed frame sequence equal `mapping.interpolate(position)` combined by the mix mode bit for bit (`==`); `feedbackCycle` has a readable description; `wouldCreateCycle` returns nil for a connection with a structural problem (unknown parameter self-connection). Record the red run (compile failure), then implement `modulationGraph` and the graph check in `bind` (`AudioFeatureModulator.swift`) and the `feedbackCycle(ParameterID, path:)` case (`AudioFeatureBinding.swift`) per G9. Evidence: T11 and MOD-002/MOD-003's suites pass unchanged.

## Phase 7: Polish

- [ ] MOD-014-T12 Run the quickstart commands: ParameterGraph and VisualGenerators on the host, VisualGenerators in the Linux build shape, `check_compliance.py`, `validate_docs.py`; record counts and suite durations here; confirm no file uses Foundation-only or C stdio APIs that Linux lacks.

## Dependencies

T01 → T02 → T03 → T04 → (T05 → T06 → T07 → T08) and (T09 → T10) → T11 → T12. T05 and T09 are
test files that can be written in parallel once T04 lands.

## Implementation strategy

MVP = US1 (T01-T04): the roadmap acceptance. US2-US4 add the order, the incremental check, the full
issue list and the binding integration that later rows (MOD-007 to MOD-013) build on.
