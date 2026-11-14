# Implementation Plan: PERF-009 Startup warm cache

**Branch**: `feature/perf-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A small, key-checked file cache in `Library/Caches/WarmStart/` (LocalPortability: `WarmCacheKey`,
`WarmCacheStore`, `WarmCacheHash`, `WarmStartLoader`, an injected-clock `LaunchTimeline`) holds two entries made
only from bundle content: the prepared bundled preset library (a compact binary snapshot from PresetLibrary, so a
warm launch skips the JSON decode, sort and search-key folding) and a Metal binary archive of the app's native
pipelines (VisualGenerators `NativePipelineArchive`, used by the native spectra's `FlatShapePass` and the
compositor's `CompositorShaders.pipeline`). Each entry's key (app version, build, OS version, GPU family, format
version, SHA-256 of its inputs) and checksum are checked before use; any mismatch or damage deletes and rebuilds.
The app (`WarmStartCache`) wires the library load and archive open into launch with signpost intervals, writes the
archive back when the scene leaves the foreground, and the measurement build's `perf009` mode plus
`run_device_tests.py warmstart` record cold and warm launches.

## Technical Context

**Language/Version**: Swift 6 (packages, app), Python 3 (device runner)
**Primary Dependencies**: Foundation; CryptoKit (Apple, hash) with the portable SHA-256 on Linux; Metal
(`MTLBinaryArchive`, Apple only, compiled out with `VISUAL_NO_METAL`); OSSignposter via `DiagnosticsLog`
**Storage**: `Library/Caches/WarmStart/<entry>.bin` + `<entry>.key.json` (FILE-009 Caches category)
**Testing**: XCTest in LocalPortability (Linux + host), PresetLibrary (Linux + host), VisualGenerators (host Metal),
the app unit tests (host-app on the iOS 27.2 simulator); `scripts/test_scripts.py`
**Target Platform**: iOS/iPadOS 26+; packages also macOS 15 and Linux (non-Metal parts)
**Project Type**: mobile app + Swift packages
**Performance Goals**: warm library load skips the decode/sort/fold step (counted); hashing the 4.9 MB index with
CryptoKit costs a few ms; no work added on the render path
**Constraints**: never use a stale or damaged entry; never cache user data; failures fall back silently; tests
short (owner rule 7) and clock-free
**Scale/Scope**: 12,847 presets; ~10 native pipelines

## Constitution Check

- I Public APIs: `MTLBinaryArchive`, CryptoKit, FileManager, OSSignposter are public. PASS
- VI Modular boundaries: cache core in LocalPortability (Foundation only); PresetLibrary owns its snapshot format;
  Metal archive in VisualGenerators; the app only wires them. PASS
- VIII projectM fidelity: no engine or ANGLE change; preset programs are not cached (R12). PASS
- X Evidence: tests prove invalidation and step counts; launch numbers are a `{device}` task; simulator numbers are
  labelled not evidence. PASS
- Privacy: bundle-derived data only, no identifiers; Clear Caches empties it; no UserDefaults keys added. PASS
- Post-design re-check: unchanged, PASS.

## Project Structure

```text
Packages/LocalPortability/Sources/LocalPortability/WarmStart/   WarmCacheKey, WarmCacheStore, WarmCacheHash,
                                                                 WarmStartLoader, LaunchTimeline
Packages/LocalPortability/Tests/LocalPortabilityTests/WarmCacheStoreTests.swift, LaunchTimelineTests.swift
Packages/PresetLibrary/Sources/PresetLibrary/PresetLibrarySnapshot.swift, PresetLibrary+WarmStart.swift
Packages/PresetLibrary/Tests/PresetLibraryTests/PresetLibraryWarmStartTests.swift
Packages/VisualGenerators/Package.swift                          + LocalPortability dependency
Packages/VisualGenerators/Sources/VisualGenerators/NativePipelineArchive.swift (+ FlatShapePass wiring)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/NativePipelineArchiveTests.swift
Packages/Compositor/Package.swift                                Compositor target + VisualGenerators product
Packages/Compositor/Sources/Compositor/CompositorShaders.swift   archivedSources, pipeline() through the archive
Apps/projectM-iOS/Coordinators/WarmStartCache.swift              identity, store, signposts, background write
Apps/projectM-iOS/Coordinators/AppCoordinator.swift              library load + sceneBecame (2 small edits)
Apps/projectM-iOS/Automation/AutomationRunner.swift              perf009 launch mode
Apps/projectM-iOS/Tests/WarmStartCacheTests.swift                app-level: identity, clear, outcome labels
scripts/run_device_tests.py (+ test_scripts.py)                  `warmstart` step, perf009.json allowed
docs/test-reports/performance.md                                 PERF-009 section ({device} D1 cold/warm)
```

## Phases

- Research: [research.md](research.md). Data model: [data-model.md](data-model.md). Contract:
  [contracts/warm-cache.md](contracts/warm-cache.md). Quickstart: [quickstart.md](quickstart.md).

## Complexity Tracking

None: no constitution deviation, no ADR needed (no default overridden).
