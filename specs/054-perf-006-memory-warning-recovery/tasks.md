# Tasks: PERF-006 Memory Warning Recovery

**Input**: design documents in `specs/054-perf-006-memory-warning-recovery/` (spec, plan, research,
data-model, contracts/memory-pressure-recovery.md, quickstart).

**Tests**: requested by the spec (PERF-006-S1 to S5) and the brief; budgets follow owner rule 7
(unit test about 1-2 s, ≤ 10 s; suite < 1 min; UI test < 30 s).

Format: `- [ ] PERF-006-Tnn [P?] [US?] description (file)`. `{device}` = needs the owner's hands and
physical devices; left open.

## Phase 1: Foundational (blocks every story)

- [X] PERF-006-T01 [P] Recovery policy in plain Swift per contracts/memory-pressure-recovery.md: `MemoryPressureLevel` (warning, critical), `MemoryPressureTier` (cache, optional), `MemoryPressureRelease` (bytes ≥ 0, items ≥ 0, bytesEstimated; `.none`), `MemoryPressureResponder` (main actor; `restoreAfterMemoryPressure` default no-op), `MemoryPressureStepResult`, `MemoryPressureReport` (freedBytes = sum of steps; `summary` text with names and counts only), `MemoryPressureRecovery` (weak responders; cache steps in registration order then optional on escalation; escalate on critical or a warning with "now − last ≤ repeatWindow" (30 s); `shedUntil = now + coolDown` (60 s) on every escalating signal; `restoreIfDue` restores each shed responder once; re-entrant signals queued; optional responders registered while shedding are shed at once; counters), in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/MemoryPressureRecovery.swift` — Verified 2026-11-13: `swift test --package-path Packages/PresentationLifecycle` 49 tests, 0 failures (0.01 s) on the macOS host
- [X] PERF-006-T02 [P] Policy tests with fake responders and a test clock (host and Linux): order (cache before optional, registration order), idempotence (second release frees 0), single warning runs cache only, critical escalates, repeat inside the window escalates and outside does not, cool-down extended by a further escalation, restore exactly once and not before `shedUntil`, re-entrant signal handled after the running one, weak responders skipped, registering while shedding sheds at once, report sums and summary text, counters, in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/MemoryPressureRecoveryTests.swift` — Verified 2026-11-13: MemoryPressureRecoveryTests 8/8 on the macOS host (0.05 s); pure Swift with no platform imports (Linux runs in CI)
- [X] PERF-006-T03 [P] Diagnostics event `DiagnosticsLog.memoryRecovery(_ summary: String)` (one Points of Interest event plus one app log line, private) and its test, in `Packages/Diagnostics/Sources/Diagnostics/Logging.swift`, `Packages/Diagnostics/Tests/DiagnosticsTests/MemoryRecoveryLogTests.swift` — Verified 2026-11-13: `swift test --package-path Packages/Diagnostics` 11 tests, 0 failures
- [ ] PERF-006-T04 App coordinator: `MemoryPressureCoordinator` (`shared`; the only observer of `UIApplication.didReceiveMemoryWarningNotification` on the main queue; `handle(_:)` with `MonotonicClock`; one restore task scheduled for `shedUntil`, rescheduled when extended; logs every report; keeps `lastReport`), in `Apps/projectM-iOS/Coordinators/MemoryPressureCoordinator.swift`

## Phase 2: User Story 1 - The show keeps playing when the device runs low on memory (P1)

**Goal**: every cache step frees what it holds; the shown visual and the source are untouched.
**Independent test**: inject a warning while a visual renders; caches report 0, frames keep coming, `sourceStarts` unchanged.

- [ ] PERF-006-T05 [US1] Shared texture pool step (cache, measured bytes = retired bytes of every pool before the purge, items = retired textures; waiting textures are dropped safely because their command buffers retain them, PERF-006-R13); `SharedTexturePool` drops its own observer and registers the step with `MemoryPressureCoordinator.shared` on first pool; DEBUG `retiredBytes` total and `relaxIdleEvictionForUITests()`, in `Apps/projectM-iOS/Visuals/SharedTexturePool.swift`
- [ ] PERF-006-T06 [US1] Renderer steps: `VisualizerRenderer.memoryPressureResponders` (default `[]`) in `Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift`; `PresetWarming.holdsGraphicsResources` (default false; `PresetPrewarmer` = `hasGraphicsContext`); `PresetWarmUpController` cache step "preset warm-up context" (cancel a waiting request, `worker.stop()`, keep the last request and warmed IDs; 1 item and `targetSize² × 4` estimated bytes when the worker held its resources, else `.none`) and optional step "preset warm-up" (hold requests during the shed, restore schedules the newest unless suspended); `ANGLERenderer.memoryPressureResponders`, in `Packages/ANGLERendering/Sources/ANGLERendering/PresetWarmUpController.swift`, `PresetPrewarmer.swift`, `ANGLERenderer.swift`
- [X] PERF-006-T07 [P] [US1] Warm-up tests: fake worker (cache step stops once and keeps the request; repeat is `.none`; shed holds requests and restore issues the newest once; suspension wins over restore; a presentation resume during the shed schedules nothing (spec Edge Cases); the stop happens at the worker's safe point, PERF-006-R13) and the real prewarmer on the simulator (context held → step → no context; a later request warms again), in `Packages/ANGLERendering/Tests/ANGLERenderingTests/PresetWarmUpMemoryTests.swift` — Verified 2026-11-13: `xcodebuild test -scheme ANGLERendering` on the iOS 27.2 simulator, PresetWarmUpMemoryTests 5/5 (1.8 s) and PresetWarmUpControllerTests 16/16 unchanged (21 tests, 0 failures)
- [ ] PERF-006-T08 [US1] Archive step: `PresetArchive.dropCache() -> Int` (the chunk's byte count) and `RendererPresetLoader` as cache responder "preset archive cache" (measured), in `Apps/projectM-iOS/Coordinators/PresetArchive.swift`, `AppCoordinator.swift`
- [ ] PERF-006-T09 [US1] Idle spectrum step: `AppCoordinator` registers a cache responder "idle native spectrum" that releases `nativeVisual` (paused) only when the chosen visual is not a native spectrum (1 item, no bytes); registers the renderer's steps in `prepareRenderer()` and the loader's step at init, in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] PERF-006-T10 [US1] App integration tests (S1, S4): Photo host rendered at two sizes → retired bytes > 0 → injected warning (posted notification) → retired 0, report's pool step freed exactly the retired bytes, the next frame renders (framesShown advances), 60 further frames at the steady size add no pool miss; archive step drops a loaded chunk and reports its size, second call 0; idle spectrum step releases a spectrum not chosen (only while paused, PERF-006-R13) and keeps a chosen one; a warning before any visual exists frees 0 and creates nothing; the stored settings (`AppSettings.allKeys` values) and the chosen visual are identical before and after (PERF-006-R6), in `Apps/projectM-iOS/Tests/MemoryPressureAppTests.swift`
- [ ] PERF-006-T11 [US1] DEBUG probe and readouts under `-uitestMemoryPressure` (`memory:warning` posts the system notification, `memory:critical`, `memoryRecoveries`, `memoryFreedBytes`, `memoryRetiredBytes`, `memoryWarmUpContext`, `visualFrames`; relaxes the pool's idle eviction), in `Apps/projectM-iOS/Debug/UITestMemoryPanel.swift`, `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] PERF-006-T12 [US1] UI test (S2): projectM, Camera stand-in and Photo (after a rotation): inject, `visualFrames` advances, `sourceStarts` stays 1, `memoryRecoveries` 1, Photo frees > 0 bytes and ends with `memoryRetiredBytes` 0, projectM ends with `memoryWarmUpContext` no; each case < 30 s, in `Apps/projectM-iOS/UITests/MemoryPressureUITests.swift`

## Phase 3: User Story 2 - Repeated pressure sheds optional background work (P2)

**Goal**: escalation sheds the warm-up for the cool-down and restores it.
**Independent test**: T02 (policy with a test clock) and T07 (warm-up shed and restore).

- [ ] PERF-006-T13 [US2] App coordinator test with a test clock and an injected sleep-free restore: two warnings inside the window shed a fake optional step (no renderer needed), `restoreIfDue` before the end restores nothing, after the end restores once; the coordinator exposes `scheduledRestoreAt == shedUntil` after an escalation and nil after the restore, in `Apps/projectM-iOS/Tests/MemoryPressureAppTests.swift`

## Phase 4: User Story 3 - What was freed is visible to diagnostics (P3)

**Goal**: one log event per recovery; DEBUG readouts.
**Independent test**: T03 (summary text) and T12 (readouts).

- [X] PERF-006-T14 [US3] Report summary format test (names and counts only, estimated bytes marked `~`), in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/MemoryPressureRecoveryTests.swift` — Verified 2026-11-13: `testTheSummaryCarriesNamesAndCountsOnly` on the macOS host

## Phase 5: Polish and cross-cutting

- [ ] PERF-006-T15 Regression runs: PresentationLifecycle and Diagnostics packages (host and Linux shape), ANGLERendering on the simulator, app unit tests plus CameraUITests, PhotoLayerUITests, NativeVisualUITests; `check_compliance.py`, `validate_docs.py`; PosterBoard reports counted
- [ ] PERF-006-T16 Docs: spec status, test report `docs/test-reports/memory-warning-recovery.md` (what is real vs simulated, freed-bytes numbers, test counts), roadmap note
- [ ] PERF-006-T17 {device} D1 (iOS 27) and D3 (iPadOS 26.5) under real pressure (Xcode's Simulate Memory Warning while attached, or a memory-hungry companion app): the app survives, logs a memory recovery event, keeps rendering and playing (quickstart D)

## Analysis (speckit-analyze, 2026-11-13)

No CRITICAL or HIGH finding; constitution aligned (I, IV, VI, VII, X). Applied: R13 (GPU release safety) named in T05, T07, T10; R6 (stored settings unchanged) asserted in T10; spec edge cases "presentation resume during a shed" (T07) and "warning before any visual" (T10) given tests; T13 made concrete (`scheduledRestoreAt`). Coverage: R1-R16 and S1-S5 each have at least one task; S6 is T17 `{device}`.

## Dependencies

T01 → T02, T04 → T05, T06, T08, T09 → T10, T11 → T12; T03 before T04; T13 after T04; T15-T16 last;
T17 needs the owner and devices.

## Parallel opportunities

T01/T03 (different packages); T06/T08 (different modules); T07 alongside T10.

## Implementation strategy

MVP = Phase 1 + US1 (the acceptance). US2 is mostly covered by the policy in T01/T02; US3 by T03/T11.
