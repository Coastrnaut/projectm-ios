# Implementation Plan: FILE-004 Import Conflict Resolver

**Branch**: `feature/file-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/111-file-004-import-conflict-resolver/spec.md`

## Summary

FILE-003's preset planner gains a third choice, Replace, and per-conflict overrides on top of the
plan-wide default ("Apply to all"). The store's staged install learns to replace records in place
(same identifier, new text) with the index write as the single commit point; old texts are deleted
only after the commit, and a list of them left in `staging/` lets the next load finish a cleanup the
app did not. Scenes get a pure planner and a journalled, all-or-nothing installer in the show's
folder (`ShowStorage`), with the same three choices; no screen until SCN-014.

In `Packages/PresetLibrary` (Linux-testable):

- `PresetArchiveConflictPolicy` gains `.replace`; `PresetArchiveImportPlanner.plan(..., policy:,
  overrides:)`; entries carry the effective `choice`, `replaces` (identifier and name of the replaced
  preset) and `fellBack` (Replace installed as Keep both, FILE-004-R4); `PresetArchiveAction` gains
  `replacesID`. Keep both keeps FILE-003-D3's derived identifiers.
- `UserPresetStore.addAll` becomes `commitImport(adding:replacing:)` (addAll stays as a wrapper):
  staged texts, `staging/replaced.json` naming the texts the commit makes unreferenced, moves into
  `files/`, one index write, then deletion of the old texts; `removeLeftoverStaging()` deletes listed
  texts no record names.
- `UserPresetLibrary.planArchiveImport(_:policy:overrides:)`, `installArchive` handles Replace,
  refuses a held target; `runTrial` discards a result when the preset's text changed during the trial.

In `Packages/ShowControl` (`ShowStorage`, Linux-testable; new dependency on `LocalPortability` for
SHA-256):

- New `ShowSceneImport.swift`: `ShowSceneImportChoice`, `ShowSceneImportPlan`, the pure
  `ShowSceneImportPlanner`, `ShowStore.planSceneImport`, `installImportedScenes`,
  `recoverInterruptedSceneImport()` and the journal (research D4).

In the app:

- `UserPresetsCoordinator`: `setArchiveChoice(_:for:)`, `setArchivePolicy` clears overrides,
  words for Replace and fallbacks, install announcement with the replaced count; DEBUG
  `-uitestPresetArchiveConflictFixture` previews an archive that clashes with the seeded preset.
- `PresetArchiveImportView`: per-row choice buttons in their own small view
  (`PresetArchiveChoiceRow`), "Apply to all" picker with three options.
- `AppCoordinator`: one DEBUG line for the conflict fixture.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode; CI also Xcode 26.

**Primary Dependencies**: Foundation, SwiftUI, LocalPortability (SHA-256), SceneFormat, ShowControl.

**Storage**: `Application Support/UserPresets` (index, files, quarantine, staging) and
`Application Support/Show` (show.json, Scenes/, ImportStaging/, scene-import.journal.json).

**Testing**: XCTest: PresetLibrary and ShowControl package tests (host and Linux), app unit tests,
one XCUITest on an own iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26.0+. **Project Type**: Mobile app with SwiftPM packages.

**Performance Goals**: Linear planning; unit tests use a few items (owner rule 7).

**Constraints**: Public APIs only, no networking, typed closures, no long untyped numeric
expressions, small SwiftUI bodies, no wall-clock assertions, no main-actor mutation in setUp/tearDown.

**Scale/Scope**: 1,000 presets per archive (PRE-014); one scene per archive today (FILE-001), the
planner takes a list.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Foundation file APIs, SwiftUI |
| VI Modular boundaries | Pass: planners and installers in packages (Linux-testable); UI in the app |
| IX Pinned dependencies | Pass: only an existing local package (LocalPortability) added to ShowStorage |
| X Evidence-based quality | Pass: ID table, fault injection at every file operation, simulated crashes, simulator UI test |
| Security | Pass: archive readers unchanged; texts re-validated; path guard kept; nothing executed |
| Privacy | Pass: no networking, no new keys |

Re-checked after Phase 1 design: unchanged.

## Project Structure

```text
specs/111-file-004-import-conflict-resolver/  plan.md research.md data-model.md quickstart.md contracts/conflict-resolver.md tasks.md
Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/
├── PresetArchiveImportPlan.swift     (choices, overrides, Replace planning)
├── UserPresetStore.swift             (commitImport, cleanup list)
└── UserPresetLibrary.swift           (plan/install with Replace, held refusal, trial guard)
Packages/PresetLibrary/Tests/PresetLibraryTests/PresetArchiveConflictTests.swift   (new)
Packages/ShowControl/Package.swift                          (LocalPortability dependency)
Packages/ShowControl/Sources/ShowStorage/ShowSceneImport.swift   (new)
Packages/ShowControl/Tests/ShowControlTests/ShowSceneImportTests.swift   (new)
Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift
Apps/projectM-iOS/Coordinators/AppCoordinator.swift          (one DEBUG line)
Apps/projectM-iOS/Views/PresetArchiveImportView.swift
Apps/projectM-iOS/Views/PresetArchiveChoiceRow.swift         (new)
Apps/projectM-iOS/Tests/PresetArchiveConflictAppTests.swift  (new)
Apps/projectM-iOS/UITests/PresetArchiveConflictUITests.swift (new)
```

**Structure Decision**: The scene installer lives beside `ShowStore` because the show folder is
where scene IDs are stored and referenced (spec Baseline), and the package tests run on Linux.

## Complexity Tracking

None.
