# Implementation Plan: FILE-009 Storage Usage Explorer

**Branch**: `feature/file-009` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/071-file-009-storage-usage-explorer/spec.md`

## Summary

A read-only Settings › Storage screen with nine categories and a total, backed by a plain-Swift
measuring walk:

1. **LocalPortability** (`StorageUsage.swift`): `StorageCategory` (nine cases, fixed order),
   `StorageEntry`, the `StorageDirectoryReading` protocol (one directory listing at a time; injected in
   tests), `FileManagerStorageReader` (Foundation: `contentsOfDirectory` with the file-size,
   allocated-size and link keys only), `StorageWalkLimits` (depth 32, 100,000 entries per walk),
   `StorageUsageCalculator.measure(_:)` (iterative walk, no recursion, never follows links, never walks
   a root outside the container, checks `Task.isCancelled` every 256 entries), `StorageReport`.
2. **App** (`Apps/projectM-iOS`): `StorageLocations` (category folders from the stores' own
   definitions; `standard()` and a redirectable `make(applicationSupport:temporary:caches:container:)`),
   `StorageUsageModel` (`@Observable`, main actor; runs the calculator in a detached utility task,
   cancels the previous one), `StorageUsageView` (List, nine rows + total, Refresh, incomplete note),
   one `NavigationLink("Storage")` row in `SettingsView`'s last section, and the DEBUG fixture
   `UITestStorageFixture` (`-uitestStorageFixture`).
3. **Tests**: LocalPortability `StorageUsageTests` (fixture tree on the real file system: exact content
   bytes, overhead bound, sparse file, links, empty folder; injected-reader tests for limits,
   cancellation, outside roots; runs on the host and in the Linux shape, real-file-system allocated
   checks only where the platform reports allocation), app `StorageLocationsTests` (store APIs agree;
   redirected mapping), UI `StorageUsageUITests` (one test).
4. **Docs**: contract `contracts/storage-usage.md`; `project.yml` gains `LocalPortability` as a direct
   app dependency (one line). No ADR: no default is overridden (read-only screen, no new manifest
   reason).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac; Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio)

**Primary Dependencies**: Foundation (`FileManager`, `URLResourceValues`), SwiftUI; nothing new

**Storage**: reads only; writes only in DEBUG fixtures under `<tmp>/StorageFixture`

**Testing**: `swift test --package-path Packages/LocalPortability` (host and Linux shape);
`xcodebuild test` on an iOS 27.2 simulator for `projectM-iOSTests/StorageLocationsTests`,
`projectM-iOSUITests/StorageUsageUITests`, `projectM-iOSUITests/SettingsUITests`

**Target Platform**: iOS 26+ app; macOS 15 / Linux package tests

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: a few thousand files measured well under a second on a device (not asserted on
wall clock); work bounded by the entry limit

**Constraints**: no file dates, no volume capacity keys (privacy manifest unchanged); unit tests about
1-2 s, suite under 1 minute, UI test under 30 s (owner rule 7)

**Scale/Scope**: ~250 lines of package code, ~250 lines of app code, ~400 lines of tests

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: `FileManager`, `URLResourceKey.fileSizeKey` / `totalFileAllocatedSizeKey` / `isSymbolicLinkKey`, SwiftUI. |
| II-V. Capture | Not touched. |
| VI. Modular boundaries | Pass: logic in the dependency-free `LocalPortability` package behind a protocol; the app only maps folders and draws. |
| VII. Real-time audio safety | Pass: measuring runs on a detached utility task, never on audio or render threads. |
| VIII-IX. Engine, dependencies | Not touched; no new dependency. |
| X. Evidence-based quality | Pass: fixture tests with exact expected sizes; simulator UI test; the device check is a `{device}` task left open. |
| Privacy | Pass: on-device only; no file dates (FileTimestamp) and no volume capacity (DiskSpace) read; `check_privacy_manifest.py` on the built Debug app. |

Post-design re-check: unchanged (Pass).

## Project Structure

```text
specs/071-file-009-storage-usage-explorer/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
└── contracts/storage-usage.md

Packages/LocalPortability/
├── Sources/LocalPortability/StorageUsage.swift
└── Tests/LocalPortabilityTests/StorageUsageTests.swift

Apps/projectM-iOS/
├── Coordinators/StorageLocations.swift
├── Coordinators/StorageUsageModel.swift
├── Views/StorageUsageView.swift
├── Views/SettingsView.swift            (one NavigationLink)
├── Debug/UITestStorageFixture.swift
├── Tests/StorageLocationsTests.swift
└── UITests/StorageUsageUITests.swift
project.yml                              (LocalPortability as a direct app dependency)
```

**Structure Decision**: `LocalPortability` rather than a new package: it is already the
Foundation-only package for the app's local files, with host and Linux CI lanes, so no CI change is
needed (a new package would need five CI loop edits).

## Complexity Tracking

None.
