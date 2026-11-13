# Implementation Plan: FILE-010 Safe Cache Cleanup

**Branch**: `feature/file-010` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/072-file-010-safe-cache-cleanup/spec.md`

## Summary

Clear Caches on FILE-009's Storage screen, backed by a plain-Swift allowlist planner and executor:

1. **LocalPortability** (`CacheCleanup.swift`): `StorageCategory.cleanable` (Recordings, Shares and
   exports, Caches), `CacheCleanupRequest` (container, cache roots per category, protected user-data
   roots, in-use paths), `CacheCleanupFileSystem` (FILE-009's `StorageDirectoryReading` plus
   `removeItem(atPath:)`; injected in tests), `FileManagerCacheCleanupFileSystem`, `CacheCleaner.plan(_:)`
   (vets each root, lists its children without following links, keeps in-use paths and descends only
   into folders that hold one, sizes each item with FILE-009's limits) and `CacheCleaner.execute(_:inUse:)`
   (re-checks each item: still inside its root, no link above it, not in use now; removes links as
   links), `CacheCleanupPlan`, `CacheCleanupResult`.
2. **App**: `StorageLocations.protectedRoots` (every user-data category folder, `Show`,
   `Library/Preferences`) and `cleanupRequest(inUse:)`; `StorageUsageModel` gains `prepareCleanup()`,
   `clear()`, the pending plan and the last result (detached utility tasks, then a refresh);
   `StorageUsageView` gains a Clear Caches section, the confirmation alert and result notes;
   `AppCoordinator+CacheCleanup.swift` gathers files in use from `VideoRecordingCoordinator.filesInUse`,
   `CaptureShareCoordinator.request` and `UserPresetsCoordinator.filesInUse` (two small computed
   properties added); `SettingsView` and `VisualizerView` pass the provider (one line each). The DEBUG
   fixture also seeds a show, the two export folders and a Library/Preferences file.
3. **Tests**: LocalPortability `CacheCleanupTests` (real file system and an injected one: plan,
   refusals, links, in-use, execute re-checks, Linux shape); app `CacheCleanupAcceptanceTests` (the
   row's acceptance: fixture container → cleanup → byte-identical user data, current and backup scene
   load through `SceneAutosaveStore`, show scenes through `ShowStore`, caches gone, in-use recording
   kept); UI `CacheCleanupUITests` (one test).
4. **Docs**: contract `contracts/cache-cleanup.md`. No ADR: no default is overridden (FILE-009-R7
   already assigned clearing to FILE-010; no new manifest reason).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac; Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio)

**Primary Dependencies**: Foundation (`FileManager.removeItem`, `URLResourceValues` link and size keys),
SwiftUI; nothing new

**Storage**: removes only inside the five cache folders; writes only in DEBUG fixtures

**Testing**: `swift test --package-path Packages/LocalPortability` (host; Linux shape through the
injected file system); `xcodebuild test` on an own iOS 27.2 simulator for `projectM-iOSTests`,
`projectM-iOSUITests/CacheCleanupUITests`, `StorageUsageUITests`, `SettingsUITests`

**Target Platform**: iOS 26+ app; macOS 15 / Linux package tests

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: plan and clear a few thousand cache files well under a second on a device (not
asserted on wall clock)

**Constraints**: no file dates, no volume capacity; never follow links; unit tests about 1-2 s, UI test
under 30 s (owner rule 7)

**Scale/Scope**: ~250 lines of package code, ~200 lines of app code, ~450 lines of tests

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: `FileManager.removeItem(atPath:)`, `contentsOfDirectory`, resource keys already used by FILE-009. |
| II-V. Capture | Not touched. |
| VI. Modular boundaries | Pass: planner and executor in the dependency-free `LocalPortability` package behind a protocol; the app gathers folders and in-use paths and draws. |
| VII. Real-time audio safety | Pass: detached utility tasks; never on audio or render threads; recording files in use are kept. |
| VIII-IX. Engine, dependencies | Not touched; no new dependency. |
| X. Evidence-based quality | Pass: fixture acceptance test with byte comparison and real loaders; simulator UI test; device check left open as `{device}`. |
| Privacy | Pass: on-device only; no file dates or disk space read; `check_privacy_manifest.py` on the built Debug app. |

Post-design re-check: unchanged (Pass).

## Project Structure

```text
specs/072-file-010-safe-cache-cleanup/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
└── contracts/cache-cleanup.md

Packages/LocalPortability/
├── Sources/LocalPortability/CacheCleanup.swift
└── Tests/LocalPortabilityTests/CacheCleanupTests.swift

Apps/projectM-iOS/
├── Coordinators/StorageLocations.swift         (protected roots, cleanup request)
├── Coordinators/StorageUsageModel.swift        (prepare, clear, result)
├── Coordinators/AppCoordinator+CacheCleanup.swift
├── Coordinators/VideoRecordingCoordinator.swift (filesInUse)
├── Coordinators/UserPresetsCoordinator.swift    (filesInUse)
├── Views/StorageUsageView.swift                 (Clear Caches, alert, notes)
├── Views/SettingsView.swift, Views/VisualizerView.swift (pass the provider)
├── Debug/UITestStorageFixture.swift             (more seeded folders)
├── Tests/CacheCleanupAcceptanceTests.swift
└── UITests/CacheCleanupUITests.swift
```

**Structure Decision**: `LocalPortability`, next to FILE-009's walk it reuses (`StorageDirectoryReading`,
`StorageWalkLimits`, `StorageUsage`); its host and Linux CI lanes already exist, so no CI change.

## Complexity Tracking

None.
