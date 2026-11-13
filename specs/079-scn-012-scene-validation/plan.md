# Implementation Plan: SCN-012 Scene Validation

**Branch**: `feature/scn-012` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/079-scn-012-scene-validation/spec.md`

## Summary

Two layers:

1. **SceneFormat** (pure, Foundation-free, Linux): `SceneRepairReport` turns a decode refusal
   (`SceneDecodeError`), decode warnings, SCN-001 validation issues and MOD-013's per-edge outcomes
   into grouped entries (`Group`: missing media, invalid mappings, unsupported version, unknown content
   kept, values adjusted, damaged file) with a `Severity` (cannot open, needs repair, problem, note),
   the item, the problem, what happens if opened anyway, and `SceneRepairAction`s. `SceneDocument
   .repairing(_:registry:assets:)` applies actions in one canonical order, each recomputing its targets
   from a fresh `validate` (one definition of validity, research SCN-012-D2). `SceneRepairReport
   .open(bytes:registry:assets:)` is the single entry point from bytes: refusal → report; document →
   report plus the decoded document.
2. **App**: `SceneRepairCoordinator` (@MainActor, @Observable) holds one pending `SceneRepairRequest`
   (title, report, document, open/cancel closures) and resolves it with Open with repairs, Open as is
   or Cancel; `SceneRepairReportView` is the sheet (VoiceOver headings, Dynamic Type). Show cues
   (`ShowCoordinator.show`) route a decode refusal or a report that `needsReview` through it; Reopen
   (`AppCoordinator.reopenLastScene`) does the same for the held scene; `SceneArchiveImportResult`
   gains `repairReport`; the launch restore is unchanged (logs and falls back). DEBUG:
   `-uitestShowRepairSeed` seeds a three-cue show (good, broken, newer version) for
   `SceneRepairUITests`.

ADR-0028 is amended (repair report and actions; no default overridden, so no new ADR).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals)

**Primary Dependencies**: SceneFormat (existing codec and validation), ParameterGraph, Compositor; app:
SwiftUI, Observation. No new package.

**Storage**: none new. Repairs are in memory; stored scene files are never rewritten by this feature.

**Testing**: XCTest. `swift test --package-path Packages/SceneFormat --filter SceneRepair` on the host
and the Linux shape (`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc
-DANALYSIS_NO_ACCELERATE`); `xcodebuild test` of `projectM-iOSTests`, the new `SceneRepairUITests`,
`ShowCueUITests` and `SessionRecoveryUITests` on an own iOS 27.2 simulator. Budgets (owner rule 7):
unit ≤ 10 s (target 1-2 s), suite < 1 min, UI test < 30 s, property test ≤ 1 s.

**Target Platform**: iOS 26+ / macOS 15 packages, Linux CI; app iOS 26+

**Project Type**: mobile app + SwiftPM packages

**Performance Goals**: a report is one validate plus one modulation restore (already done on every
open); a repair is at most nine validate passes over a ≤ 1 MiB document (typically a few KB, well
under 10 ms).

**Constraints**: no networking; no files read by the module; Foundation stays in
`SceneValidation.swift` only (source-safety test); no main-actor mutation in setUp/tearDown; no
wall-clock assertions.

**Scale/Scope**: 33 issue codes and 10 refusal kinds mapped; 9 repair actions.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: SwiftUI, Observation, Foundation. |
| II-V Capture | Not affected: no audio source change; no compatibility claim. |
| VI Modular boundaries | Pass: report and repairs in SceneFormat (pure, Linux); presentation in the app target. |
| VII Real-time audio safety | Pass: nothing on audio threads; main-actor work only on user steps. |
| VIII Upstream fidelity | Not affected (no engine change). |
| IX Pinned dependencies | Pass: no new dependency. |
| X Evidence-based quality | Pass: table, idempotency, property and UI tests; simulator only, no device claim. |
| Privacy | Pass: nothing stored or sent; the report shows asset keys and store IDs, never paths. |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/079-scn-012-scene-validation/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/scene-repair-report.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/SceneFormat/Sources/SceneFormat/SceneRepair.swift        # report, entries, actions, repairing (new)
Packages/SceneFormat/Tests/SceneFormatTests/SceneRepairTests.swift  # fixture table, idempotency, fuzz (new)
Packages/SceneFormat/Tests/SceneFormatTests/SceneSourceSafetyTests.swift   # file list + SceneRepair.swift
Apps/projectM-iOS/Coordinators/SceneRepairCoordinator.swift        # pending request, resolve (new)
Apps/projectM-iOS/Views/SceneRepairReportView.swift                 # the sheet (new)
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                # route reports
Apps/projectM-iOS/Coordinators/AppCoordinator.swift (+Show)         # own the coordinator, Reopen route
Apps/projectM-iOS/Coordinators/SceneArchiveService.swift            # result carries the report
Apps/projectM-iOS/Views/VisualizerView.swift                        # present the sheet
Apps/projectM-iOS/Debug/UITestShowFixture.swift                     # -uitestShowRepairSeed
Apps/projectM-iOS/Tests/SceneRepairCoordinatorTests.swift           # (new)
Apps/projectM-iOS/UITests/SceneRepairUITests.swift                  # (new)
docs/adr/ADR-0028-*.md                                              # amendment
```

**Structure Decision**: the existing package and app layout; one new source file per side.

## Complexity Tracking

None.
