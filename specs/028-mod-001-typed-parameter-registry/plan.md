# Implementation Plan: MOD-001 Typed Parameter Registry

**Branch**: `feature/mod-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/028-mod-001-typed-parameter-registry/spec.md`

## Summary

A Foundation-only parameter model (the roadmap's proposed `Packages/ParameterGraph`) plus the
app's first catalog, derived from the existing configuration types so ranges and defaults have one
source of truth. No user-visible change. ADR-0012 records the model because MOD-*, MIDI, OSC, SCN,
SHOW-008, UIX-003/004/009 and ACC-005 build on it.

1. **New package `Packages/ParameterGraph`, target `ParameterGraph`** (Foundation and
   Synchronization only; builds and tests on Linux):
   - `ParameterID` (dotted ID, syntax check), `ParameterGroup`, `ParameterUnit`, `ParameterCurve`,
     `ParameterKind` (continuous, integer, boolean, enum, color) with `ParameterEnumCase` and
     `ParameterColor`, `ParameterValue`, `ModulationPolicy` / `ModulationMixMode`,
     `ParameterDescriptor` (with its registration site).
   - `ParameterRegistry` (validated, ordered, immutable `Sendable` value) and
     `ParameterValidationIssue` / `ParameterRegistryError` (every issue, readable text).
   - `ParameterStore` (thread-safe current manual values, typed access, clamping, observers,
     change counter) and `ParameterSnapshot` (versioned `Codable`, restore report).
2. **Package `Packages/VisualGenerators`, new target `VisualParameters`** (depends on
   `ParameterGraph`, `VisualGenerators`, `VisualEffects`; added to the existing single library
   product so CI's `-scheme VisualGenerators` builds and tests it): `VisualParameterIDs` and
   `VisualParameterCatalog` (the 14 descriptors of MOD-001-R10, read from
   `CircularSpectrumConfiguration()`, `LinearSpectrumConfiguration`'s static ranges and default
   instance, `SpectrumBarCount.allCases`, `LinearSpectrumOrientation.allCases` and
   `BloomParameters`' static ranges and defaults). A drift test compares every descriptor with the
   types. The other targets of the package are not changed.
3. **App**: no source change. A new unit test file (`Apps/projectM-iOS/Tests/ParameterCatalogAppTests.swift`)
   checks that `AppSettings`' defaults and offered choices (bars, spacing, orientation, glow) lie
   in the registered parameters (MOD-001-R13, Clarifications Q1). `project.yml` needs no change:
   the app already links the `VisualGenerators` product, and local package dependencies resolve
   transitively (as `FlashSafety` does today).
4. **CI** (`.github/workflows/ios-ci.yml`): add `ParameterGraph` to the five package loops (Linux
   tests, macOS host tests, generic-iOS compile, iOS 26 and iOS 27 simulator tests).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode, strict concurrency complete),
Xcode 27.2

**Primary Dependencies**: Foundation, Synchronization (`Mutex`, iOS 18+/macOS 15+/Linux). No
third-party dependency.

**Storage**: none on disk in this row. Snapshots are `Codable` values; SCN-001/SCN-002 own
persistence. Rollback = restore an earlier snapshot (MOD-001-R9).

**Testing**: XCTest on the macOS host, Linux (CI) and the iOS 27.2 simulator (CI). Deterministic:
no clocks, no sleeps, no scheduling assumptions; observers are synchronous. Budgets (owner rule
7): each test well under 1 s, the ParameterGraph suite under 5 s, the VisualGenerators suite
unchanged plus under 1 s.

**Target Platform**: iOS/iPadOS 26+ (app), macOS 15 host, Linux for the package.

**Project Type**: mobile app + Swift packages.

**Performance Goals**: lookup O(1) by ID (dictionary built once); a store read is one uncontended
lock and a dictionary read; no per-frame use yet.

**Constraints**: Constitution I (public APIs), VI (the model knows nothing of UI, rendering,
capture or projectM), VII (no store use on the audio thread), IX (no dependency), X (unit tests
for deterministic logic). Privacy: no new stored data (FR-065 unchanged).

**Scale/Scope**: ~700 lines of package code, ~150 lines of catalog, ~500 lines of tests.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Foundation and Synchronization only. `check_compliance.py` runs. |
| II-V Capture | Not affected: no capture or source change; no compatibility claim. |
| VI Modular boundaries | Pass: `ParameterGraph` has no dependency; the catalog lives with the visuals it describes; the app is a consumer only. |
| VII Real-time safety | Pass: nothing runs on the audio callback. The store's lock is never held while calling observers. |
| VIII projectM fidelity | Pass: projectM untouched; its settings are not registered. |
| IX Dependencies | Pass: none added. |
| X Evidence | Pass: unit tests for every rule; ADR-0012 records the model. No device claim. |
| Privacy | Pass: no new stored data, no network. |

Post-design re-check (after Phase 1): unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/028-mod-001-typed-parameter-registry/
├── plan.md
├── research.md            # MOD-001-D1 … D8
├── data-model.md
├── quickstart.md
├── contracts/parameter-registry.md
├── checklists/requirements.md
└── tasks.md               # /speckit-tasks
docs/adr/0012-typed-parameter-registry.md
```

### Source Code

```text
Packages/ParameterGraph/
├── Package.swift
├── Sources/ParameterGraph/
│   ├── ParameterID.swift            # ParameterID, ParameterGroup, syntax rules
│   ├── ParameterKind.swift          # unit, curve, kind, enum case, color
│   ├── ParameterValue.swift         # typed value, Codable
│   ├── ModulationPolicy.swift
│   ├── ParameterDescriptor.swift    # descriptor + registration site
│   ├── ParameterValidation.swift    # issues, error, descriptor checks
│   ├── ParameterRegistry.swift
│   ├── ParameterStore.swift         # values, clamping, observers, change counter
│   └── ParameterSnapshot.swift      # versioned snapshot, restore report
└── Tests/ParameterGraphTests/
    ├── ParameterIDTests.swift
    ├── RegistryValidationTests.swift
    ├── RegistryEnumerationTests.swift
    ├── ParameterStoreTests.swift
    └── ParameterSnapshotTests.swift
Packages/VisualGenerators/
├── Package.swift                                  # + ParameterGraph, + VisualParameters
├── Sources/VisualParameters/VisualParameterCatalog.swift
└── Tests/VisualGeneratorsTests/VisualParameterCatalogTests.swift
Apps/projectM-iOS/Tests/ParameterCatalogAppTests.swift
.github/workflows/ios-ci.yml                       # + ParameterGraph in five loops
```

**Structure Decision**: a new package for the model (the roadmap's layout, Constitution VI), and
the catalog as a new target inside `VisualGenerators` because only there can it read the
configuration types without making `ParameterGraph` depend on rendering code.

## Rollback

The feature is additive: deleting `Packages/ParameterGraph`, the `VisualParameters` target, the
two test files and the CI loop entries restores the previous state; no stored data, settings key or
app behavior depends on it.

## Complexity Tracking

None: no constitution violation.
