# Implementation Plan: MOD-014 Modulation Feedback Prevention

**Branch**: `feature/mod-014` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/035-mod-014-modulation-feedback-prevention/spec.md`

## Summary

Add a pure, `Sendable` description of the modulation graph to `Packages/ParameterGraph`
(`ModulationNode`, `ModulationGenerator`, `ModulationEdge`, `ModulationGraph`), a validator that
refuses every cycle with a readable path (one shortest loop per strongly connected group, found with
an iterative Tarjan pass and a breadth-first search, research MOD-014-D2, D3) plus the structural
mistakes listed in MOD-014-R4, and `ValidatedModulationGraph`, which carries a deterministic
evaluation order (Kahn's algorithm with a min-heap on stable IDs) and the incremental
`wouldCreateCycle(adding:)` check. `AudioFeatureModulator` exposes its bindings as a
`modulationGraph` and checks each new binding set with the validator (new error
`feedbackCycle`). No app, UI or catalog change; no ADR (rejecting cycles overrides no constitution
default; the decision is research MOD-014-D1).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode), Xcode 27.2; CI also builds
with Xcode 26, so closures passed to `sorted`, `map` and `reduce` get explicit types.

**Primary Dependencies**: none (Swift standard library; no Foundation needed in the new files).

**Storage**: none (MOD-013 persists graphs later).

**Testing**: XCTest on the macOS host and Linux (CI; locally the Linux build shape of
VisualGenerators). Deterministic: fixed seeds, no clock, no wall-time assertions. Budgets (owner
rule 7): each test well under 1 s, the ParameterGraph suite under 10 s.

**Target Platform**: iOS/iPadOS 26+ (through the app), macOS 15 host, Linux.

**Project Type**: Swift package (library row).

**Performance Goals**: O(V + E log V) validation for V ≤ 1,024 nodes and E ≤ 4,096 connections;
no recursion (explicit stacks), so a 1,000-node chain needs constant call depth.

**Constraints**: Constitution VI (dependency-free model), VII (validation runs at bind or edit time,
never per frame or on the audio thread; `advance` and `value(for:)` stay allocation-free), X (unit
tests for deterministic logic). Bit-identical modulation (MOD-014-R9).

**Scale/Scope**: about 450 lines of model code, about 15 lines in the modulator and binding error,
about 400 lines of tests.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: pure Swift. `check_compliance.py` runs. |
| II-V Capture | Not affected; no compatibility claim. |
| VI Modular boundaries | Pass: stays in the dependency-free ParameterGraph module; no analysis or UI types. |
| VII Real-time safety | Pass: validation allocates, so it runs only in `bind` (already allocating, main-thread edit time); the per-frame path is untouched. |
| VIII projectM fidelity | Not affected. |
| IX Dependencies | Pass: none added. |
| X Evidence | Pass: unit tests for every requirement; no device or simulator claim (no app change). |
| Privacy | Pass: no data. |

Post-design re-check (after Phase 1): unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/035-mod-014-modulation-feedback-prevention/
├── plan.md
├── research.md            # MOD-014-D1 … D6
├── data-model.md
├── quickstart.md
├── contracts/modulation-graph.md
├── checklists/requirements.md
└── tasks.md               # /speckit-tasks
```

### Source Code

```text
Packages/ParameterGraph/
├── Sources/ParameterGraph/
│   ├── ModulationGraph.swift            # new: nodes, generators, edges, graph, issues, error (contract G1-G3)
│   ├── ModulationGraphValidator.swift   # new: structural checks, Tarjan, shortest loops (G4-G6)
│   ├── ValidatedModulationGraph.swift   # new: evaluation order, incremental check (G7, G8)
│   ├── AudioFeatureBinding.swift        # new error case `feedbackCycle`
│   └── AudioFeatureModulator.swift      # `modulationGraph`, graph check in `bind` (G9)
└── Tests/ParameterGraphTests/
    ├── ModulationGraphCycleTests.swift      # acceptance, self-loop, disjoint, diamond, limits, chain
    ├── ModulationGraphIssueTests.swift      # one fixture per structural issue, ordering
    └── ModulationGraphOrderTests.swift      # evaluation order, incremental property test, MOD-002 regression
```

**Structure Decision**: the graph lives beside the bindings in `ParameterGraph` so macros (MOD-010),
LFOs (MOD-007), mixes (MOD-011), the matrix (MOD-012) and serialization (MOD-013) share one
description and one validator without new dependencies.

## Rollback

Revert the commits: the new files go away and `bind` loses one check that never fires for audio
bindings; no stored data depends on the new types.

## Complexity Tracking

None: no constitution violation.
