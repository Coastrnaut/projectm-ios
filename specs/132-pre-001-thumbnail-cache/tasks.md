# Tasks: PRE-001 Visual Thumbnail Cache

**Input**: `specs/132-pre-001-thumbnail-cache/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (PRE-001-S1 to S7). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes; no
wall-clock assertions (the cache's sleep is injected). `{device}` tasks stay open until a person runs them.

## Phase 1: Setup

- [X] PRE-001-T01 Run `xcodegen generate`, initialize the preset submodules if missing, link `Build` to the main checkout's `Build` if the xcframeworks are missing, create the simulator "PRE1 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run — Verified 2026-11-14: `xcodegen generate`; preset submodules initialized; `Build` already linked to the main checkout; simulator C706A6BC "PRE1 iPhone 17" created from the iOS 27.2 runtime; PosterBoard reports 25 before

## Phase 2: Foundational (blocks every story)

- [X] PRE-001-T02 [P] `PresetThumbnailSpec` ("128 × 72 pixels", "45" frames, 44,100 Hz, "735 (stereo, interleaved)" samples per frame, seed `0x5052_4531`, `rendererVersion` 1) and `SyntheticPCM.frames(spec)` (110 Hz + 440 Hz sines, beat envelope every 15 frames, seeded LCG noise) in `Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/PresetThumbnailSpec.swift` (research PRE-001-D2) — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter PresetThumbnail` (12 tests, 0 failures, 0.1-0.8 s; three runs) and the full package suite (252 tests, 0 failures, 43 s); Linux not run on this host (no Docker), CI's Linux job runs the package with no flags and the only Apple-only call is behind `#if canImport(Darwin)`
- [X] PRE-001-T03 [P] `PresetThumbnailKey` (`stableID` = first 32 hex digits of SHA-256 of `presetID + "\n" + contentHash + "\n" + rendererVersion` via `PortableSHA256`; `fileName` = `stableID + ".png"`; `init(preset: IndexedPreset, spec:)`) in `Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/PresetThumbnailKey.swift` (D3) — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter PresetThumbnail` (12 tests, 0 failures, 0.1-0.8 s; three runs) and the full package suite (252 tests, 0 failures, 43 s); Linux not run on this host (no Docker), CI's Linux job runs the package with no flags and the only Apple-only call is behind `#if canImport(Darwin)`
- [X] PRE-001-T04 `PresetThumbnailIndex` (`schemaVersion` 1, `rendererVersion`, entries) and `PresetThumbnailIndex.openRepairing(directory:rendererVersion:fileManager:)` implementing the data-model's open-time repair (missing → empty; unreadable or newer → empty and all PNGs removed; older renderer entries and missing files dropped; orphan PNGs removed; repaired index saved) in `Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/PresetThumbnailIndex.swift` (D4) — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter PresetThumbnail` (12 tests, 0 failures, 0.1-0.8 s; three runs) and the full package suite (252 tests, 0 failures, 43 s); Linux not run on this host (no Docker), CI's Linux job runs the package with no flags and the only Apple-only call is behind `#if canImport(Darwin)`
- [X] PRE-001-T05 `PresetThumbnailRendering`, `PresetThumbnailError` (`unavailable`, `failed`, `dropped`) and the actor `PresetThumbnailCache` (contract C2, C3: hits, one entry per stable ID, newest first, `maxPending` 32 dropping the oldest, cancellation of waiters, worker at utility priority with an injected 150 ms sleep, session failures, a failed PNG or index write (disk full) is a session failure, backup exclusion on Apple platforms guarded by `#if canImport(Darwin)` because CI's Linux job builds this package with no flags) in `Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/PresetThumbnailCache.swift` (D5, D6, D7) — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter PresetThumbnail` (12 tests, 0 failures, 0.1-0.8 s; three runs) and the full package suite (252 tests, 0 failures, 43 s); Linux not run on this host (no Docker), CI's Linux job runs the package with no flags and the only Apple-only call is behind `#if canImport(Darwin)`

## Phase 3: User Story 2 - The second browse is instant (P1) — the acceptance

**Independent test**: counting fake renderer; first pass N renders, second pass 0 with the same IDs and files; again after a new cache instance on the same folder.

- [X] PRE-001-T06 [US2] Package tests `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetThumbnailCacheTests.swift`: acceptance (S1), relaunch (S2), same request twice at once renders once (R6), stable ID determinism and SyntheticPCM determinism (S6), cancellation before the render starts renders nothing (S4), queue bound drops the oldest and serves newest first (R3), `unavailable` is not remembered while `failed` is (R11); host and Linux shape — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter PresetThumbnail` (12 tests, 0 failures, 0.1-0.8 s; three runs) and the full package suite (252 tests, 0 failures, 43 s); Linux not run on this host (no Docker), CI's Linux job runs the package with no flags and the only Apple-only call is behind `#if canImport(Darwin)`

## Phase 4: User Story 3 - A damaged cache repairs itself (P2)

- [X] PRE-001-T07 [US3] Fixtures `Packages/PresetLibrary/Tests/PresetLibraryTests/ThumbnailFixtures/` (`index-renderer-v0.json`, `index-schema-v99.json`, `index-corrupt.json`, `index-missing-file.json`), registered as a test resource in `Packages/PresetLibrary/Package.swift`, and migration tests in `PresetThumbnailCacheTests.swift`: each opens without error and re-renders exactly the affected presets (S3); a folder removed while open (Clear Caches) re-renders and recreates the folder — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter PresetThumbnail` (12 tests, 0 failures, 0.1-0.8 s; three runs) and the full package suite (252 tests, 0 failures, 43 s); Linux not run on this host (no Docker), CI's Linux job runs the package with no flags and the only Apple-only call is behind `#if canImport(Darwin)`

## Phase 5: User Story 1 - I recognize presets by their picture (P1) — MVP UI

**Independent test**: open Included on the simulator; the first rows show `thumbnail:<name>` images.

- [ ] PRE-001-T08 [P] [US1] `PresetThumbnailDrawResult`, `PresetThumbnailDrawing` and `VisualizerRenderer.presetThumbnails` (default nil) in `Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift` (contract C4)
- [ ] PRE-001-T09 [US1] `PresetThumbnailRunner` in `Packages/ANGLERendering/Sources/ANGLERendering/PresetThumbnailRunner.swift` (D1: own thread, unshared context, fresh engine, BGRA8 target, frames of PCM, read-back flipped to top-down RGBA, timeout, suspension) and its wiring in `ANGLERenderer.swift` (property, texture paths, PERF-011 suspend and resume, shutdown); a simulator test in `Packages/ANGLERendering/Tests/ANGLERenderingTests/PresetThumbnailRunnerTests.swift` (an Included preset gives `width × height × 4` bytes that are not all one color; suspended → `unavailable`)
- [ ] PRE-001-T10 [US1] `PresetThumbnailModel` in `Apps/projectM-iOS/Coordinators/PresetThumbnailModel.swift` (cache in `Library/Caches/PresetThumbnails`, PNG adapter over the renderer's `presetThumbnails` with ImageIO, contents from `RendererPresetLoader` (bundled data, playable user data), playable presets only, `NSCache` of images; no renderer or a renderer without `presetThumbnails` (the GLES fallback) → `unavailable`, placeholders stay) plus `thumbnails` on `PresetCoordinator` and its creation in `AppCoordinator.swift`
- [ ] PRE-001-T11 [US1] `PresetThumbnailView` in `Apps/projectM-iOS/Views/PresetThumbnailView.swift` (64 × 36 points, placeholder `sparkles` or `lock`, `.task(id:)`, no spoken text and no extra VoiceOver stop (R12), identifiers `thumbnail:<name>` / `thumbnailPlaceholder:<name>`) shown first in `PresetRow` (`Apps/projectM-iOS/Views/PresetBrowserView.swift`)
- [ ] PRE-001-T12 [US1] App tests `Apps/projectM-iOS/Tests/PresetThumbnailModelTests.swift` (locked presets never request; the GLES fallback (no `presetThumbnails`) leaves placeholders; a playable preset's thumbnail lands in the cache folder under Caches through a fake renderer; PNG adapter round trip) and UI test `Apps/projectM-iOS/UITests/PresetThumbnailUITests.swift` (open Included; the first rows show `thumbnail:<name>` images, S5, < 30 s)

## Phase 6: Polish

- [ ] PRE-001-T13 Storage and erase decision checks: an app test that `PresetThumbnailModel.defaultDirectory` lies under `StorageLocations.standard().roots[.caches]` and outside every `protectedRoots` folder (D7); repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`, `check_privacy_manifest`, `check_network_symbols`), type-check budget, spec status, PosterBoard count after, simulator and derived data removed
- [ ] PRE-001-T14 {device} On D1: the visualizer's fps with the browser open while about 20 thumbnails generate, against a run with them cached (S7: within 10%) — `docs/test-reports/performance.md`

## Dependencies

T01 → T02, T03 (parallel) → T04 → T05 → T06, T07 (US2, US3) → T08 → T09 → T10 → T11 → T12 → T13. T14 after T12 on a device.

## Parallel examples

- T02 and T03 (different files); T08 can start alongside T06/T07.

## Implementation strategy

MVP = the package cache with the acceptance test (US2), then the repair fixtures (US3), then the
renderer and row (US1). Each phase is committed when its tests pass.
