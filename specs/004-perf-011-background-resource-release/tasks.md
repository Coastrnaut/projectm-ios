# Tasks: PERF-011 Background resource release

**Input**: `specs/004-perf-011-background-resource-release/` (spec, plan, research, data-model,
contracts, quickstart)

**Conventions**: task IDs are `PERF-011-T01…`. Tests come first within each story. Tags:
`{mac}` runs on the Mac host, `{sim}` needs an iOS simulator, `{merge}` needs the full app build
(preset submodules) and is run by the main session after the merge, `{device}` needs a physical
device and belongs to the final device stage. For a `{merge}` task the code and tests are written
in this run; only the evidence (build and test run) waits for the merge. A task is ticked only when its evidence was
produced, with " — Verified <date>: <how>".

## Phase 1: Setup

- [X] PERF-011-T01 {mac} Create the package `Packages/PresentationLifecycle` (`Package.swift`,
  swift-tools 6.0, platforms iOS 26.0 and macOS 15, library `PresentationLifecycle`, test target
  `PresentationLifecycleTests`, no dependencies). Evidence: `swift build --package-path
  Packages/PresentationLifecycle` succeeds. — Verified 2026-11-12: `swift build --package-path Packages/PresentationLifecycle` succeeded on the Mac Studio; also `xcodebuild -scheme PresentationLifecycle -destination generic/platform=iOS build` (exit 0).

## Phase 2: Foundational (blocks every story)

- [X] PERF-011-T02 {mac} Write `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/PresentationAvailabilityTests.swift`:
  the full 4-state × 4-signal table of data-model.md; initial state can present; unlock while
  backgrounded stays unavailable; foreground clears a lock (R1). Evidence: tests fail to compile
  or fail before T03. — Verified 2026-11-12: the tests were written before T03's types existed; they pass with T03 (5 tests).
- [X] PERF-011-T03 {mac} Implement `PresentationSignal` and `PresentationAvailability` in
  `Packages/PresentationLifecycle/Sources/PresentationLifecycle/PresentationAvailability.swift`
  (R1). Evidence: T02 tests pass with `swift test --package-path Packages/PresentationLifecycle`. — Verified 2026-11-12: `swift test --package-path Packages/PresentationLifecycle`: PresentationAvailabilityTests 5 of 5.

## Phase 3: User Story 3 - the mechanism later frame sources join (P2, built first because US1 and US2 adopt it)

**Independent test**: fake resources in `PresentationResourceRegistryTests`.

- [X] PERF-011-T04 [US3] {mac} Write `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/PresentationResourceRegistryTests.swift`
  with a recording fake resource: suspend in reverse registration order and resume in registration
  order; exactly once per transition and nothing on repeated signals; late registration is
  suspended at once and resumed with the others; unregister stops calls and does not resume;
  a deallocated resource is skipped and not kept alive; duplicate registration ignored;
  register/unregister from inside a callback; availability changed from inside a callback;
  `onTransition` counts; active/suspended counts and snapshot; a seeded 100-signal sequence through
  `PresentationAvailability` leaves strictly alternating calls and the final state (R2-R4, R12,
  R13; S1, S4, S5). — Verified 2026-11-12: 17 tests written first; the first run failed (10 failures, a fixture bug: the fakes were not retained), fixed in the tests.
- [X] PERF-011-T05 [US3] {mac} Implement `PresentationBoundResource`, `PresentationResourceRegistry`
  and `PresentationTransitionReport` in
  `Packages/PresentationLifecycle/Sources/PresentationLifecycle/PresentationResourceRegistry.swift`
  per plan "Registry". Evidence: T04 tests pass on the host. — Verified 2026-11-12: `swift test --package-path Packages/PresentationLifecycle`: 22 tests, 0 failures on the host; the same 22 pass on the iOS 27.2 simulator (iPhone 17).
- [X] PERF-011-T06 [P] [US3] {mac} Add `DiagnosticsLog.presentationTransition(canPresent:registered:activeBefore:activeAfter:)`
  to `Packages/Diagnostics/Sources/Diagnostics/Logging.swift` (one signpost event, public counts,
  no user content; R12) with a test in `Packages/Diagnostics/Tests/DiagnosticsTests/` that the
  formatted summary is as expected. Evidence: `swift test --package-path Packages/Diagnostics`. — Verified 2026-11-12: `swift test --package-path Packages/Diagnostics`: 10 tests, 0 failures (2 new in PresentationLogTests). The simulator smoke run logged `presentation unavailable active 2 -> 0 of 2` and `presentation available active 0 -> 2 of 2`.

## Phase 4: User Story 1 - nothing draws while the app cannot be seen (P1)

**Independent test**: simulator tests of the warm-up and the renderers; app tests after merge.

- [X] PERF-011-T07 [US1] {sim} Add `PresentationLifecycle` as a dependency of `Packages/Rendering/Package.swift`
  and `Packages/ANGLERendering/Package.swift`; add `presentationResources` (default empty) to
  `VisualizerRenderer` in `Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift`.
  Evidence: both packages build for the simulator. — Verified 2026-11-12: both packages built and tested on the iOS 27.2 simulator (see T19).
- [X] PERF-011-T08 [US1] {sim} Write `Packages/ANGLERendering/Tests/ANGLERenderingTests/PresetWarmUpControllerTests.swift`
  (fake `PresetWarming` worker): suspend cancels a request waiting for its delay and calls
  `stop()` once; a second suspend does nothing; a request while suspended starts nothing; disabled
  starts nothing (R7). Real `PresetPrewarmer` on an EGL display: after warming one preset and
  `stop()`, `isRunning` and `hasGraphicsContext` are false and the queue is empty. — Verified 2026-11-12: PresetWarmUpControllerTests, 16 tests (12 with the fake worker, 4 with the real prewarmer), pass on the iOS 27.2 simulator.
- [X] PERF-011-T09 [US1] {sim} Make `PresetPrewarmer.stop()` restartable with safe points and add
  `isRunning`/`hasGraphicsContext` in `Packages/ANGLERendering/Sources/ANGLERendering/PresetPrewarmer.swift`;
  add `PresetWarming` and `PresetWarmUpController` in
  `Packages/ANGLERendering/Sources/ANGLERendering/PresetWarmUpController.swift`; route
  `ANGLERenderer.prewarm`, `prewarmEnabled`, `prewarmDelay`, `prewarmedCount` through it (R7).
  Evidence: T08 and the existing prewarm tests pass. — Verified 2026-11-12: ANGLERendering suite on the iOS 27.2 simulator: 42 tests, 0 failures, including the three existing prewarm tests.
- [X] PERF-011-T10 [US1] {sim} Add to `Packages/ANGLERendering/Tests/ANGLERenderingTests/ANGLERendererTests.swift`:
  after `suspendForPresentationLoss()` the renderer has no window surface, no display link,
  `renderFrame` returns false and `presentedFrameCount` does not change; `resume()`, a window
  change and `layoutIfNeeded()` while suspended create neither link nor surface; `setPreset` while
  suspended succeeds; `presentationResources` is `[renderer, warm-up]`; deinit while suspended
  does not crash (R5, R6, R13; S1, S2). — Verified 2026-11-12: ANGLERendererTests on the iOS 27.2 simulator: 20 tests (12 new), 0 failures.
- [X] PERF-011-T11 [US1] {sim} Implement suspension in
  `Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift` per plan "Renderers" (R5,
  R6). Evidence: T10 tests pass. — Verified 2026-11-12: as T10; the app's simulator smoke run returned from the background to a drawing visualization (same process).
- [X] PERF-011-T12 [P] [US1] {sim} Fallback renderer: test in
  `Packages/Rendering/Tests/RenderingTests/GLESRendererTests.swift` and implementation in
  `Packages/Rendering/Sources/Rendering/GLESRenderer.swift` so its display link and `renderFrame`
  obey suspension independently of `pause()` (R9). Evidence: Rendering tests pass on the simulator. — Verified 2026-11-12: `xcodebuild -scheme Rendering-Package test` on the iOS 27.2 simulator: 28 tests, 0 failures (GLESRendererTests 9, 3 new).
- [X] PERF-011-T13 [US1] {merge} Extend `Apps/projectM-iOS/Tests/LifecycleCoordinatorTests.swift`:
  background and lock suspend registered fake resources in every source mode and on the chooser;
  the capture matrix tests stay as they are (R10, R11; S6). — Verified 2026-11-12: run in this worktree after all (the app builds here with the 28 included presets only): `xcodebuild test -only-testing:projectM-iOSTests` on the iOS 27.2 simulator, LifecycleCoordinatorTests 20 of 20 (10 existing unchanged in meaning, 10 new). The main session should repeat it after the merge with the full library.
- [X] PERF-011-T14 [US1] {merge} Drive the registry from
  `Apps/projectM-iOS/Coordinators/LifecycleCoordinator.swift` (availability, loss: visualization
  then registry; then forward to `CaptureManager`), own and fill it in
  `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (register `renderer.presentationResources`,
  `onTransition` → `DiagnosticsLog.presentationTransition`), and add the package to the
  `projectM-iOS` target in `project.yml` (R10, R12). Evidence: the app builds and T13 passes. — Verified 2026-11-12: unsigned simulator build of `projectM-iOS` succeeded in this worktree (`xcodegen generate`, `xcodebuild build`), T13 passes, RendererLab also builds; smoke run on the simulator: background → `active 2 -> 0`, return → `active 0 -> 2`, picture drawing. Not run on a device.

## Phase 5: User Story 2 - the picture comes back cleanly (P1)

- [X] PERF-011-T15 [US2] {sim} Add to `PresetWarmUpControllerTests.swift`: resume reissues the last
  request (made before or during suspension) after the delay, once; presets already warmed are not
  warmed again; the real prewarmer warms a second preset after `stop()` (restart) (R8; S3).
  Implementation is T09; fix it there if these fail. — Verified 2026-11-12: the R8 tests in PresetWarmUpControllerTests pass (part of the 16; see T08).
- [X] PERF-011-T16 [US2] {sim} Add to `ANGLERendererTests.swift`: after suspend and resume the
  surface has the view's size, the display link is back exactly when the view is in a window, the
  same preset still lights pixels, a user pause set before or during suspension survives, a size
  change while suspended yields the new size on resume, Reduce flashing still limits after resume,
  and ten suspend/resume flips end in a working renderer (R5, R6, R13; S3, S4). Implementation is
  T11; fix it there if these fail. — Verified 2026-11-12: the resume tests in ANGLERendererTests pass (part of the 20; see T10).
- [X] PERF-011-T17 [US2] {merge} Add to `LifecycleCoordinatorTests.swift`: foreground resumes the
  registry before the visualization; unlock while backgrounded resumes nothing (visualization and
  registry) but is still forwarded to the capture layer; foreground after a lock without an unlock
  resumes; background-then-lock-then-foreground calls each fake once; a user pause is kept
  (R1, R3, R10; S3, S6). Implementation is T14. — Verified 2026-11-12: part of LifecycleCoordinatorTests, 20 of 20 on the simulator (see T13); also 20 of 20 on the macOS host in a scratch package holding only LifecycleCoordinator.swift.

## Phase 6: Polish and verification

- [X] PERF-011-T18 [P] {mac} Add `PresentationLifecycle` to the five package loops (Linux tests,
  macOS host tests, generic-iOS compile, iOS 26 and iOS 27 simulator tests) in `.github/workflows/ios-ci.yml`.
  Evidence: the workflow file parses (`python3 -c "import yaml…"`) and the Linux-relevant code
  uses no Apple-only API. — Verified 2026-11-12: the workflow parses (`ruby -ryaml`; Python has no yaml module here), five loops changed; the package's tests pass on the host and the iOS 27.2 simulator and it compiles for generic iOS. Not run on Linux or in CI (nothing pushed).
- [X] PERF-011-T19 {mac} Run `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`,
  `python3 scripts/test_scripts.py`, `swift test` for `PresentationLifecycle` and `Diagnostics`,
  and the simulator suites of `Rendering` and `ANGLERendering` (quickstart A and B); record counts
  here. — Verified 2026-11-12: `check_compliance.py` OK; `validate_docs.py` OK (68 files); `test_scripts.py` 88 tests OK (1 skipped) after two fixes (a `project.yml` comment tripped the diagnostic-project test; the setup_mac test hard-coded feature 002 as the newest spec); PresentationLifecycle 22 (host and simulator); Diagnostics 10 (host); Rendering 28 and ANGLERendering 42 (iOS 27.2 simulator, iPhone 17).
- [ ] PERF-011-T20 {merge} Build `projectM-iOS` and run its unit tests (`LifecycleCoordinatorTests`,
  `IdleTimerPolicyTests`, `PresetTests`) and UI tests on a simulator (quickstart C). — Open: partly run here on 2026-11-12 (app build succeeded; unit tests 49 run, 48 pass; `PresetTests.testBundledIncludedScopeMatchesRelease1_0` fails only because this worktree has no preset submodules: 28 presets instead of more than 12,000). The full unit and UI test run needs the preset packs and is the main session's after the merge.
- [ ] PERF-011-T21 {device} S7 on D1: GPU time zero and lower memory 10 s after backgrounding with
  System/App Capture running; frames within 2 s of return (quickstart D1, D2). Final device stage. — Open: `{device}`, final device stage; not attempted.
- [ ] PERF-011-T22 {device} S8 on D1-D3: app switcher card and first frame after return, lock and
  unlock, rotation while away, Control Center (quickstart D3, D4). Final device stage. — Open: `{device}`, final device stage; not attempted.

## Dependencies

- T01 → T02 → T03 → T04 → T05. T06 is independent of T02-T05.
- T07 needs T05. T08 → T09; T10 → T11 (T11 needs T09). T12 needs T07.
- T13 → T14 (needs T05, T06, T11). T15 needs T09; T16 needs T11; T17 needs T14.
- T19 after all code tasks; T20 after the merge; T21 and T22 after T20, in the final device stage.

## Parallel opportunities

T06 with T02-T05; T12 with T08-T11; T18 with anything. One agent works alone here, so they run in
sequence.

## Implementation strategy

MVP is Phases 1-4 (the registry plus User Story 1); Phase 5 proves the return. Commit after each
phase or coherent step. Requirement coverage: R1 T02-T03, T17; R2-R4 T04-T05; R5-R6 T10-T11, T16;
R7 T08-T09; R8 T15; R9 T12; R10 T13-T14, T17; R11 T13, T20; R12 T04-T06, T14; R13 T04, T10, T16;
R14 no code (nothing persisted; T19 compliance and review). Success criteria: S1 T04, T10;
S2 T08, T10; S3 T15-T17; S4 T04, T16; S5 T02, T04; S6 T13, T17, T20; S7 T21; S8 T22.
