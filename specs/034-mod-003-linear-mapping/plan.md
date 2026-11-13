# Implementation Plan: MOD-003 Linear Mapping

**Branch**: `feature/mod-003` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/034-mod-003-linear-mapping/spec.md`

## Summary

Extract MOD-002's inline input scaling and output interpolation into one named, documented, pure
value type, `LinearMapping`, in `Packages/ParameterGraph`, with the precise two-branch interpolation
(research MOD-003-D1) that is exact at both ends, bounded and monotonic for every finite pair of
ends. `AudioFeatureBinding` exposes its ranges as a `mapping` (computed; its stored fields stay),
and `AudioFeatureModulator` uses `mapping.position(of:)` in `advance` and
`mapping.interpolate(_:)` in its effective value. Acceptance and regression tests prove exactness
at 0 and 1 over representative ranges, boundedness, monotonicity, clamping, and equality with
MOD-002. No app, UI, validation or catalog change; no ADR (the choice overrides no default).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode), Xcode 27.2; CI also Xcode 26
(explicit closure types in tests).

**Primary Dependencies**: none (no Foundation needed in the mapping itself).

**Storage**: none.

**Testing**: XCTest on the macOS host and Linux (CI; locally the Linux build shape of
VisualGenerators). Deterministic, no clock. Budgets (owner rule 7): each test well under 1 s, the
ParameterGraph suite under 5 s.

**Target Platform**: iOS/iPadOS 26+ (via the app), macOS 15 host, Linux.

**Project Type**: Swift package (library row).

**Performance Goals**: a handful of floating-point operations per call; no allocation, no branch on
heap state; `@inlinable` is not needed (same module as the modulator).

**Constraints**: Constitution VI (dependency-free model), VII (allocation-free per frame), X (unit
tests for deterministic logic). Bit-identity with MOD-002 per MOD-003-R7.

**Scale/Scope**: ~90 lines of model code, ~10 lines changed in the modulator and binding, ~200 lines
of tests.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: pure Swift arithmetic. `check_compliance.py` runs. |
| II-V Capture | Not affected; no compatibility claim. |
| VI Modular boundaries | Pass: stays in the dependency-free ParameterGraph module. |
| VII Real-time safety | Pass: value type, no allocation or lock; still evaluated off the audio callback. |
| VIII projectM fidelity | Not affected. |
| IX Dependencies | Pass: none added. |
| X Evidence | Pass: unit tests for every requirement; no device or simulator claim (no app change). |
| Privacy | Pass: no data. |

Post-design re-check (after Phase 1): unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/034-mod-003-linear-mapping/
├── plan.md
├── research.md            # MOD-003-D1 … D4
├── data-model.md
├── quickstart.md
├── contracts/linear-mapping.md
├── checklists/requirements.md
└── tasks.md               # /speckit-tasks
```

### Source Code

```text
Packages/ParameterGraph/
├── Sources/ParameterGraph/
│   ├── LinearMapping.swift            # new: the mapping (contract L1-L5)
│   ├── AudioFeatureBinding.swift      # `mapping` computed property
│   └── AudioFeatureModulator.swift    # uses the mapping in advance and effective
└── Tests/ParameterGraphTests/
    └── LinearMappingTests.swift       # new: acceptance, bounds, monotonicity, clamping, regression
```

**Structure Decision**: the mapping lives beside the binding in `ParameterGraph` so later rows
(curves MOD-004, macros MOD-010, LFOs MOD-007) compose with it without new dependencies.

## Rollback

Revert the commit: the modulator's two inline expressions come back; no stored data or API used by
the app depends on the new type.

## Complexity Tracking

None: no constitution violation.
