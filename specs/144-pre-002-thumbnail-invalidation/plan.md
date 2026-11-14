# Implementation Plan: PRE-002 Thumbnail Invalidation

**Branch**: `feature/pre-002` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/144-pre-002-thumbnail-invalidation/spec.md`

## Summary

PRE-001's keys already give changed content a new thumbnail ID; what is missing is removing the old
entry and file. Add two operations to the `PresetThumbnailCache` actor (PresetLibrary, Foundation
only): `invalidate(presetID:keepingContentHash:)` removes exactly one preset's stale entries, files,
queued requests and remembered failures; `retainOnly(_:)` collects entries of presets no longer
listed (or listed with another hash) once per launch. The app's `PresetThumbnailModel` forwards both
and evicts its in-memory pictures; `UserPresetsCoordinator.refresh()` (the one path every user preset
change takes) diffs the playable list before and after and invalidates changed or removed presets;
`PresetCoordinator.attach` starts the launch collection. The row already re-requests because its
request identity contains the content hash (made testable). Renderer version updates keep PRE-001's
open-time drop (research PRE-002-D3), now covered by a v1 → v2 fixture.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2; CI also Xcode 26)

**Primary Dependencies**: Foundation (PresetLibrary); SwiftUI/UIKit in the app

**Storage**: `Library/Caches/PresetThumbnails/index.json` (schema 1, unchanged) and `<id>.png`

**Testing**: XCTest: PresetLibrary package tests (macOS host, Linux in CI); app unit tests on the iOS 27.2 simulator

**Target Platform**: iOS 26+/iPadOS; PresetLibrary also Linux

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: an invalidation is a dictionary scan of the index (hundreds of entries) plus ≤ a few file deletions; the launch collection is one pass over the index and a dictionary of 12,847 IDs, off the main actor (inside the cache actor)

**Constraints**: no format change; no wall-clock assertions; tests within owner rule 7 budgets

**Scale/Scope**: size S; ~150 lines of code plus tests

## Constitution Check

| Principle | Check |
|---|---|
| I. Public Apple APIs only | FileManager and Foundation only. PASS |
| VI. Modular boundaries | Cache logic stays in PresetLibrary (no app types); the app only calls it. PASS |
| VII. Real-time audio safety | No audio path. PASS |
| VIII. Upstream fidelity | No engine change; the renderer version is a hand-bumped constant (research D3). PASS |
| X. Evidence | Package tests for the acceptance, fixtures for migration, an app unit test for the live path; nothing claimed from the simulator beyond logic. PASS |
| Privacy | Removes data only; nothing new stored, no network. PASS |

Post-design re-check: unchanged, PASS.

## Project Structure

### Documentation (this feature)

```text
specs/144-pre-002-thumbnail-invalidation/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/thumbnail-invalidation.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/
├── PresetThumbnailCache.swift              # + invalidate, retainOnly, in-flight discard
└── PresetThumbnailInvalidation.swift       # (new) pure planning helpers over the index
Packages/PresetLibrary/Tests/PresetLibraryTests/
├── PresetThumbnailInvalidationTests.swift  # (new) acceptance S1-S4
└── ThumbnailFixtures/index-renderer-v1.json  # (new) v1 → v2 migration fixture
Apps/projectM-iOS/Coordinators/
├── PresetThumbnailModel.swift              # + invalidate, collectGarbage, memory eviction
├── UserPresetsCoordinator.swift            # refresh(): diff and invalidate
└── PresetCoordinator.swift                 # attach(): launch collection
Apps/projectM-iOS/Views/PresetThumbnailView.swift   # request identity as a testable static
Apps/projectM-iOS/Tests/PresetThumbnailInvalidationAppTests.swift   # (new) S5
```

**Structure Decision**: extend the existing PRE-001 files; one new package source file for the
pure selection logic so it is unit-testable without the actor.

## Complexity Tracking

None.
