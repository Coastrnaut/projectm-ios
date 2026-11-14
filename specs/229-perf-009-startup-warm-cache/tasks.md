# Tasks: PERF-009 Startup warm cache

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/warm-cache.md](contracts/warm-cache.md), [quickstart.md](quickstart.md)

Tests are required by the spec (PERF-009-S1-S3, R11): clock-free, counted, short (owner rule 7).

## Phase 1: Setup

- [ ] PERF-009-T01 Add the LocalPortability dependency to the `VisualGenerators` target in
  `Packages/VisualGenerators/Package.swift` and the `VisualGenerators` product to the `Compositor` target in
  `Packages/Compositor/Package.swift` (no new package; CI groups unchanged)

## Phase 2: Foundational (cache core, blocks every story)

- [ ] PERF-009-T02 [P] `WarmCacheKey` (fields "appVersion, build, osVersion, gpuFamily, formatVersion, contentHash";
  `firstMismatch`), `WarmStartIdentity`, `WarmCacheHash` (CryptoKit / PortableSHA256) in
  `Packages/LocalPortability/Sources/LocalPortability/WarmStart/WarmCacheKey.swift`
- [ ] PERF-009-T03 `WarmCacheStore` (read/lookup/write/commit/remove/clear; contract W1, W2, W4, D8: schema 1 key
  file, payload ≤ 64 MB, names `[a-z0-9-]`, link folder → unavailable) and `WarmCacheOutcome` labels in
  `Packages/LocalPortability/Sources/LocalPortability/WarmStart/WarmCacheStore.swift`
- [ ] PERF-009-T04 `WarmStartLoader` (W3) and `LaunchTimeline` with an injected `WarmStartClock` in
  `Packages/LocalPortability/Sources/LocalPortability/WarmStart/WarmStartLoader.swift`
- [ ] PERF-009-T05 Tests: each of the six key fields → stale + files deleted + rebuilt; truncated payload, flipped
  byte, bad key file, oversized payload → damaged; link folder → unavailable; loader builds 0 times warm, 1 time cold,
  decode failure → rebuilt; timeline milliseconds from a fake clock in
  `Packages/LocalPortability/Tests/LocalPortabilityTests/WarmCacheStoreTests.swift`

## Phase 3: User Story 1 + 2 (P1) — warm library, never stale

**Independent test**: load twice against one store with counted preparation; change a key field; damage the file.

- [ ] PERF-009-T06 [US1] Library snapshot format 1 (D7) encode/decode in
  `Packages/PresetLibrary/Sources/PresetLibrary/PresetLibrarySnapshot.swift`
- [ ] PERF-009-T07 [US1] `PresetLibrary.loadWarm(index:packs:store:identity:)` and
  `load(from:warmCache:identity:)` (W5; entry `preset-library`, gpu `none`) in
  `Packages/PresetLibrary/Sources/PresetLibrary/PresetLibrary+WarmStart.swift`
- [ ] PERF-009-T08 [US1] [US2] Tests: cold builds once and stores; warm builds 0 times and equals cold (presets,
  packs, home, archive order, search); changed index bytes / app build → stale, rebuilt; truncated snapshot →
  damaged-decode, rebuilt; user presets added after a warm load behave as after a cold load in
  `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetLibraryWarmStartTests.swift`

## Phase 4: User Story 1 + 2 (P1) — native pipeline archive, no stale shader

- [ ] PERF-009-T09 [US1] `NativePipelineArchive` (open on a key hit only, `gpuFamily(of:)`, shared slot,
  `makeRenderPipeline` with hit/miss counting and queued descriptors, `writeBack()`; D4-D6, W6) in
  `Packages/VisualGenerators/Sources/VisualGenerators/NativePipelineArchive.swift`; route `FlatShapePass` through it
  and expose `NativeShaderSources.visualGenerators`
- [ ] PERF-009-T10 [US1] `CompositorShaders.archivedSources` and `pipeline()` through the shared archive in
  `Packages/Compositor/Sources/Compositor/CompositorShaders.swift`
- [ ] PERF-009-T11 [US2] Tests (host Metal; skipped where archives are unsupported): cold open → miss, pipeline
  queued, writeBack stores; reopen → hit and `.failOnBinaryArchiveMiss` creation succeeds (hits counted); changed
  source hash, OS or GPU family → stale, archive not opened, file deleted; changed shader against the old archive file
  misses in Metal; damaged archive file → damaged, rebuilt in
  `Packages/VisualGenerators/Tests/VisualGeneratorsTests/NativePipelineArchiveTests.swift`

## Phase 5: App wiring (US1, US2)

- [ ] PERF-009-T12 [US1] `WarmStartCache` (identity from the bundle and OS, store at `Caches/WarmStart`, signpost
  intervals "WarmStart library" / "WarmStart pipeline archive", archive open off the main actor, write-back when the
  scene leaves the foreground) in `Apps/projectM-iOS/Coordinators/WarmStartCache.swift`; use it for the library load
  and in `sceneBecame` in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] PERF-009-T13 [US2] App tests: identity fields from an info dictionary; the store lies inside the FILE-010
  Caches root (cleanup plan includes it); clearing makes the next load a miss in
  `Apps/projectM-iOS/Tests/WarmStartCacheTests.swift`

## Phase 6: User Story 3 (P2) — cold and warm measurements

- [ ] PERF-009-T14 [US3] `perf009` launch mode (`PROJECTM_WARMCACHE=cold` clears first; sample per data-model) in
  `Apps/projectM-iOS/Automation/AutomationRunner.swift`
- [ ] PERF-009-T15 [US3] `warmstart` step (alternating cold/warm, medians per label, simulator = not evidence),
  `perf009.json` allowed in the privacy listing, dry-run test in `scripts/run_device_tests.py` and
  `scripts/test_scripts.py`
- [ ] PERF-009-T16 [US3] {device} Run `run_device_tests.py warmstart --device D1 --repeat 10` and record cold and
  warm medians in `docs/test-reports/performance.md` (PERF-009 section) — S5

## Phase 7: Polish

- [ ] PERF-009-T17 PERF-009 section in `docs/test-reports/performance.md` (method, simulator rehearsal as not
  evidence, open D1 row)
- [ ] PERF-009-T18 Repo checks, Linux shape builds (`-DVISUAL_NO_METAL`, `LOCALPORTABILITY_NO_CRYPTOKIT`), type-check
  budget, privacy manifest and network symbols on the Debug app; spec status

## Dependencies

T01 → T02-T05 → (T06-T08) and (T09-T11) in parallel → T12-T13 → T14-T15 → T16; T17-T18 last.
MVP: Phases 1-3 (warm library with full invalidation).
