# Implementation Plan: SCN-008 Scene Snapshots

**Branch**: `feature/scn-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

The SCN-001 document gains an optional verbatim `snapshots` list (like MOD-006 `triggers` and MOD-007
`lfos`), read into named `{ParameterID: ParameterValue}` sets with two new SCN-012 warning codes. A pure
`SceneSnapshotRecallPlan` validates a snapshot against the registry (unknown → skipped, clamped as
MOD-001 restore does). The app keeps the list in SCN-002's carry, and a `SceneSnapshotCoordinator`
saves, renames, deletes and recalls; recall writes through `ParameterInspectorTargets` (the Settings
path) and records one SCN-010 undo step. A Settings section shows the list. A DEBUG media-load spy proves
recall reloads nothing.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: SceneFormat (document, validation, repair), ParameterGraph (registry, store), app (SceneAutosave*, SceneHistoryCoordinator, ParameterInspectorTargets, SettingsView)
**Storage**: the current scene's autosave file (SCN-002), format version 1, optional key
**Testing**: XCTest: SceneFormat (host and Linux), app unit tests and one UI test on simulator "SCN8 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+
**Constraints**: byte-identical legacy encoding; no new settings keys; no networking; owner rule 7 budgets; Xcode 26 type-check budget

## Constitution Check

- Public APIs only, no networking, local-first data: pass (pure Swift model, local scene file).
- Accessibility (FR-070): standard List rows, VoiceOver actions, announcer library lane; pass.
- Photosensitive safety: recall writes through Settings; ACC-012's clamps still apply at render; pass.
- No compatibility or device claims: none made.

## Project Structure

```text
Packages/SceneFormat/Sources/SceneFormat/SceneSnapshots.swift        # new: entry, read, editing, recall plan, limits
Packages/SceneFormat/Sources/SceneFormat/SceneDocument.swift         # `snapshots` field
Packages/SceneFormat/Sources/SceneFormat/SceneDecoding.swift         # decode + count limit
Packages/SceneFormat/Sources/SceneFormat/SceneEncoding.swift         # written only when set
Packages/SceneFormat/Sources/SceneFormat/SceneLiveState.swift        # carried through live state and capture
Packages/SceneFormat/Sources/SceneFormat/SceneValidation.swift       # warnings
Packages/SceneFormat/Sources/SceneFormat/SceneIssue.swift            # two codes
Packages/SceneFormat/Sources/SceneFormat/SceneRepair.swift           # classification
Apps/projectM-iOS/Coordinators/SceneAutosaveCapture.swift            # carry.snapshots written back
Apps/projectM-iOS/Coordinators/SceneAutosaveCoordinator.swift        # read/replace the list, commit
Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift         # `recordStep(label:)`
Apps/projectM-iOS/Coordinators/SceneSnapshotCoordinator.swift        # new: save/rename/delete/recall
Apps/projectM-iOS/Coordinators/AppCoordinator+SceneSnapshots.swift   # new: wiring
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                  # property + connect call (2 lines)
Apps/projectM-iOS/Visuals/MediaLoadSpy.swift                         # new: DEBUG counters
Apps/projectM-iOS/Visuals/PhotoVisualHost.swift, VideoVisualHost.swift, Coordinators/LogoCoordinator.swift  # spy calls
Apps/projectM-iOS/Views/SceneSnapshotsSection.swift                  # new: the Settings section
Apps/projectM-iOS/Views/SettingsView.swift                           # one line in `mediaSections`
```

Tests: `SceneSnapshotTests` (SceneFormat), app `SceneSnapshotAcceptanceTests`, UI `SceneSnapshotUITests`.

## Complexity Tracking

None. No new package dependencies.
