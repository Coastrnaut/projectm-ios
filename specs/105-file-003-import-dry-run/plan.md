# Implementation Plan: FILE-003 Import Dry Run

**Branch**: `feature/file-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/105-file-003-import-dry-run/spec.md`

## Summary

A pure planner turns an archive plus the current library into an import plan; the install executes
exactly that plan after planning again, all or nothing; Cancel discards the plan. Presets get the
whole flow with a preview sheet in My Presets; scene archives get the planner and the plan-checked
install in `SceneArchiveService` (no screen until SCN-014).

In `Packages/PresetLibrary` (plain Swift, builds and tests on Linux):

- New `UserPresets/PresetArchiveImportPlan.swift`: `PresetArchiveConflictPolicy` (`keepBoth`,
  `skip`), `PresetArchiveEntryKind`, `PresetArchiveRefusal`, `PresetArchivePlanEntry`,
  `PresetArchiveImportPlan` (counts, missing licences, total bytes, actions; Equatable, so a
  re-plan is compared with `==`), and the pure `PresetArchiveImportPlanner.plan(...)`.
  Keep both's new identifiers are derived deterministically from the incoming identifier and text
  hash (research FILE-003-D3), so planning twice gives equal plans.
- `UserPresetStore.addAll(_:)`: stages every text in `UserPresets/Staging/`, checks each staged
  file's SHA-256, moves them into `Files/`, writes the index once; any failure undoes every step
  (moved files, created folders, staging). A throwing test hook (`fileOperationFault`) sits on the
  store's single file-operation path. `load()` removes a leftover `Staging/` folder.
- `UserPresetLibrary.planArchiveImport(_:policy:)` (reads only) and
  `installArchive(_:plan:)` → `PresetArchiveInstallOutcome` (`installed`, `changed(new plan)`,
  `refused(message)`); installed presets are `pending` and go through the PRE-012 trial.
- New `LibraryTreeSnapshot` (`LibraryTreeSnapshot.swift`): relative path → SHA-256 of every file
  plus every directory, under given roots; `digest`. Used by the byte-for-byte tests and the DEBUG
  probe.

In the app:

- `UserPresetsCoordinator`: `importPicked` routes a `.zip` to `previewArchive(at:)`: reads the
  file once under its security scope (size-limited), plans, sets `archiveReview`. `setArchivePolicy`,
  `installArchive()`, `cancelArchive()`. Announcements through `announceLibrary` (wired by
  AppCoordinator to `AccessibilityAnnouncer` kind `.library`). DEBUG: `libraryDigest` probe and a
  `-uitestPresetArchiveFixture` hook that writes a fixture archive and previews it.
- New `Views/PresetArchiveImportView.swift`: the preview sheet (counts, conflicts with the policy
  picker, missing licences, refused with reasons, size, Install/Cancel); small separate properties
  so each body type-checks quickly; vertical text rows that wrap at accessibility sizes; no
  animation.
- `UserPresetsView`: accepts `.zip` in the picker, presents the sheet from `archiveReview`.
- `SceneArchiveService.planImport(at:)` → `SceneArchiveImportPlan`, and
  `importArchive(at:plan:)` that refuses `.planChanged` when the archive's SHA-256 or the current
  photo/video differ; otherwise FILE-001's all-or-nothing import, shared with `importArchive(at:)`.
- `AccessibilityAnnouncer`: new lane `library`.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode; CI also Xcode 26.

**Primary Dependencies**: Foundation, SwiftUI, LocalPortability (stored ZIP, SHA-256), SceneArchive, SceneFormat.

**Storage**: Files in Application Support (`UserPresets`, `PresetCollections`, `Photos`, `Videos`) and UserDefaults (photo/video current IDs).

**Testing**: XCTest: PresetLibrary package tests (host and Linux shape), app unit tests (projectM-iOSTests), one XCUITest on the iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26.0+.

**Project Type**: Mobile app with SwiftPM packages.

**Performance Goals**: Planning 1,000 presets is linear (hash lookups); unit tests use a few presets (owner rule 7).

**Constraints**: Public APIs only, no networking, no wall-clock assertions, typed closures and small SwiftUI bodies (CI's Xcode 26 type-check limit).

**Scale/Scope**: At most 1,000 presets of 512 KiB per archive (PRE-014 limits).

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Foundation file APIs, SwiftUI `fileImporter`, security-scoped URLs |
| VI Modular boundaries | Pass: planner and store in PresetLibrary (Linux-testable); UI and wiring in the app |
| IX Pinned dependencies, licences | Pass: no new dependency; licence lines are surfaced, never verified |
| X Evidence-based quality | Pass: fixture table, byte-for-byte snapshots, injected faults, simulator UI test; simulator never performance evidence |
| Security | Pass: archives verified by the existing reader; texts re-validated by MilkdropPresetValidator; nothing executed; path guard kept (staging inside the library folder) |
| Privacy | Pass: no networking, no new keys outside the library; nothing logged |

Re-checked after Phase 1 design: unchanged, no violations.

## Project Structure

### Documentation (this feature)

```text
specs/105-file-003-import-dry-run/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/import-dry-run.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/PresetLibrary/Sources/PresetLibrary/
├── LibraryTreeSnapshot.swift                     (new)
└── UserPresets/
    ├── PresetArchiveImportPlan.swift             (new: plan types and planner)
    ├── UserPresetStore.swift                     (addAll, fault hook, staging cleanup)
    └── UserPresetLibrary.swift                   (plan/install entry points)
Packages/PresetLibrary/Tests/PresetLibraryTests/
├── PresetArchiveFixtures.swift                   (new)
├── PresetArchiveImportPlanTests.swift            (new: fixture table)
└── PresetArchiveInstallTests.swift               (new: byte-for-byte, faults, re-validation)
Apps/projectM-iOS/
├── Coordinators/UserPresetsCoordinator.swift     (preview state and actions)
├── Coordinators/SceneArchiveService.swift        (planImport, importArchive(at:plan:))
├── Coordinators/AccessibilityAnnouncer.swift     (library lane)
├── Coordinators/AppCoordinator.swift             (wiring, DEBUG hook)
├── Views/PresetArchiveImportView.swift           (new)
├── Views/UserPresetsView.swift                   (picker types, sheet)
├── Tests/PresetArchiveImportAppTests.swift       (new)
├── Tests/SceneArchiveImportPlanTests.swift       (new)
└── UITests/PresetArchiveImportUITests.swift      (new)
```

**Structure Decision**: logic in the PresetLibrary package so the fixture table and the
byte-for-byte proof run on Linux; the scene plan stays in the app beside `SceneArchiveService`
because staging uses the app's photo and video stores.

## Complexity Tracking

None.
