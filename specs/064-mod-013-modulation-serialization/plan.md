# Implementation Plan: MOD-013 Modulation Serialization

**Branch**: `feature/mod-013` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/064-mod-013-modulation-serialization/spec.md`

## Summary

Two plain-Swift packages change; no app code changes.

1. **ParameterGraph** gains `ModulationIDMigrations`, an append-only table of stable-ID rules
   ("renamed to", "retired", each tagged with the table version that added it) for parameter IDs and
   audio feature IDs, validated on construction (no loops, self-renames, duplicates or cross-kind
   renames) and against the catalog when `ParameterRegistry` is built (a migrated parameter ID must be
   retired and unregistered; chains end at a registered or retired ID; audio renames end at a known
   feature). The registry carries the table and resolves IDs (`resolveParameter`, `resolveAudioFeature`).
   `VisualParameterCatalog` passes its (empty) table.
2. **SceneFormat** restores modulation per edge: `SceneDocument.restoreModulation(registry:)` judges
   every binding and connection in document order as restored, rewritten, dropped, orphaned or
   rejected (research MOD-013-D2, D3), returns the applied bindings, expressions and graph, the
   preserved (orphaned and rejected) edges verbatim, a report with paths, and the matching issues.
   Validation and `liveState` use it, so modulation-edge problems become warnings (ADR-0028
   amendment). Unknown audio features are read and kept (`SceneBinding.sourceID`,
   `SceneConnection`/`SceneNodeRef` in the modulation section). Capture writes live edges then
   preserved edges, so a round trip is a fixed point (research MOD-013-D4).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions)

**Primary Dependencies**: ParameterGraph (ParameterGraph, ParameterExpression), SceneFormat (its
existing Compositor dependency); tests also VisualGenerators (VisualParameters catalog)

**Storage**: none (the scene bytes are SCN-001's; files are SCN-002)

**Testing**: XCTest with `swift test` on the Mac host and the Linux shape
(`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`)

**Target Platform**: iOS 26+ / macOS 15 packages, Linux CI

**Project Type**: Swift packages (libraries)

**Performance Goals**: restoring 32 bindings and 256 connections takes milliseconds (one MOD-014
validation per connection, linear each); the 200-document property test under 1 s

**Constraints**: edit/load time only, never on an audio or render path; deterministic (no clock but
the one passed to `advance`); no wall-clock assertions; no C stdio

**Scale/Scope**: SCN-001 limits (32 bindings, 64 generators, 256 connections); migration tables of
tens of rules

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pure Swift. Pass. |
| VI Modular boundaries | ID migration lives with the IDs (ParameterGraph); restore and capture live with the document (SceneFormat); no app or engine change. Pass. |
| VII Real-time safety | Restore runs at load time; the modulator's per-frame path is unchanged. Pass. |
| IX Dependencies | None added. Pass. |
| X Evidence | Unit, acceptance and seeded property tests on two hosts; no simulator or device claim (no app change). Pass. |
| Security: untrusted input | Unknown IDs are kept as text and never applied; nothing is executed; SCN-001's size, depth and count limits still run first. Pass. |
| Privacy | No new data. Pass. |

No deviations. Two ADR amendments, no new ADR: ADR-0028 (per-edge restore, severities, preserved
edges) and ADR-0012 (the migration table extends the registry's ID rules without allowing reuse).

## Project Structure

### Documentation (this feature)

```text
specs/064-mod-013-modulation-serialization/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/modulation-serialization.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code

```text
Packages/ParameterGraph/Sources/ParameterGraph/
├── ModulationIDMigrations.swift          (new: table, rules, resolution, structural checks)
├── ParameterRegistry.swift               (migrations stored, catalog checks, resolve helpers)
└── ParameterValidation.swift             (three new problem codes)
Packages/ParameterGraph/Tests/ParameterGraphTests/
└── ModulationIDMigrationTests.swift      (new)
Packages/VisualGenerators/Sources/VisualParameters/VisualParameterCatalog.swift  (empty table passed)
Packages/SceneFormat/Sources/SceneFormat/
├── SceneDocument.swift                   (SceneBinding.sourceID, SceneNodeRef, SceneConnection)
├── SceneDecoding.swift / SceneEncoding.swift  (unknown audio IDs kept)
├── SceneIssue.swift                      (new codes, severities)
├── SceneModulationRestore.swift          (new: per-edge restore and report)
├── SceneValidation.swift                 (uses the restore)
└── SceneLiveState.swift                  (applied + preserved edges, report, apply, capture order)
Packages/SceneFormat/Tests/SceneFormatTests/
├── SceneModulationRestoreTests.swift     (new: acceptance, evaluation equality, migration)
└── SceneModulationPropertyTests.swift    (new: seeded fixed-point property)
docs/adr/0028-scene-document-format.md, docs/adr/0012-*.md  (amendments)
```

**Structure Decision**: extend the two existing packages; no new package (the table belongs with the
IDs it governs, the restore with the document it reads).

## Complexity Tracking

None.
