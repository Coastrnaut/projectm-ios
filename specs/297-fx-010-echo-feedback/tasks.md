# Tasks: FX-010 Echo Feedback

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/echo-feedback.md](contracts/echo-feedback.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (cap, bounded memory over a long run, GPU vs CPU echo maths, off identity, scene
round trip, app and UI tests). Budgets: unit test ≤ 10 s, suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [X] FX-010-T01 ADR-0108 (echo pass, ring of the cap at a bounded history size, sample-and-hold schedule, brighter-of
  blend with capped weights, chain position, resets) in `docs/adr/0108-echo-feedback.md` and its row in
  `docs/adr/README.md` — Verified 2026-11-15: docs/adr/0108-echo-feedback.md and its README row

## Phase 2: Foundational

- [X] FX-010-T02 [P] `EchoFeedback` and `EchoSchedule` in `Packages/Compositor/Sources/Compositor/EchoFeedback.swift`:
  fields "count 0…4 (cap), default 3, > 4 → 4", "delaySeconds 0.01…0.5, default 0.1", "decay 0.1…0.9, default 0.6",
  "weightCap 0…1, default 1"; clamps (NaN → default), `isActive`, `weights(valid:)` (sum ≤ weightCap),
  `limited(by: SafetyClamp)`, `historySize(width:height:)`, `historyBytesBound`, the schedule (research D3), CPU
  `downsample` and `referencePixel`/`reference` (contract C2, C3); plain Swift (Linux) — Verified 2026-11-15: EchoFeedbackModelTests 10/10 on the host; Compositor builds and the model tests pass in the Linux shape (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE)
- [X] FX-010-T03 [P] `EchoFeedbackModelTests` in `Packages/Compositor/Tests/CompositorTests/`: cap (5, 8, 1000 → 4),
  clamps, weights decay^k and their cap, ACC-012 limits, history sizes per device class and the bound, schedule at
  delay = one frame and two frames, resets, references (FX-010-R2 to R6, R10, R15) — Verified 2026-11-15: swift test --filter EchoFeedbackModelTests, 10 pass (cap 5/8/1000/Int.max → 4, weights ≤ cap with ratio = decay, ACC-012, history sizes D1-D3/4K and the 29,491,200-byte bound, schedule, references)
- [X] FX-010-T04 `OutputEffectKind.echo` (`fx.echo`, appended last) in
  `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`; update `OutputEffectOrderTests` (FX-010-R9) — Verified 2026-11-15: OutputEffectOrderTests 5/5 on the host (echo appended, older stored orders read with Echo last)

## Phase 3: User Stories 1-3 — the pass (P1)

**Goal**: delayed copies on every compositor output, capped count, bounded memory, exact off.
**Independent test**: GPU tests through the real compositor.

- [X] FX-010-T05 [US1] `EchoPass` with `cmp_echo` (`constant uint cmp_echo_cap = 4`, loop bound
  `min(e.count, cmp_echo_cap)`) and `cmp_echo_capture` in `Packages/Compositor/Sources/Compositor/EchoPass.swift`
  (ring of 4 at the history size, one output picture, all pooled and released when unused) — Verified 2026-11-15: EchoCompositeTests 5/5 on the host (Metal)
- [X] FX-010-T06 [US1] `Compositor.swift`: `echoFeedback` property and diagnostics, splice the source at the existing
  compile site, the `.echo` case in `encodeOutputEffects`, resets (research D7), release in deinit; add the source to
  `CompositorShaderSources.archived` (FX-010-R8, R11, R16) — Verified 2026-11-15: whole Compositor package on the host, 710 tests, 0 failures (22.3 s of tests); CompositorPipelineArchiveTests pass
- [X] FX-010-T07 [US1] [US2] [US3] `EchoCompositeTests` in `Packages/Compositor/Tests/CompositorTests/`: off and 0
  echoes bit-identical on random content, no picture held; a request for 8 echoes draws exactly 4 (shader loop bound
  is the cap); a moving dot gives N copies at the expected delays matching the CPU reference, ratios = decay, weight
  sum ≤ 1; 600 frames with setting changes and resizes keep 4 history pictures, identities change only at
  history-size changes, total `allocatedSize` ≤ bound, no per-frame allocation; a reset shows no echo of old content;
  turning off returns every picture (FX-010-S1 to S4) — Verified 2026-11-15: EchoCompositeTests 5/5: off/0 echoes/cap 0 bit-identical (scene and screen, no picture held); 8 requested → exactly 4 copies, ratios 0.6, GPU vs CPU ≤ 2/1024, never a 5th; never brighter than 1 on white; 600 frames: 4 pictures, identities stable except at size-class changes and the off/on, allocatedSize ≤ 4 × heap size, allocations only at frames [0, 200, 300, 450, 510]; reset bit-identical to the new scene alone
- [X] FX-010-T08 [US1] Existing compositor tests still pass (`EffectOrderCompositeTests`,
  `MotionFeedbackCompositeTests`, `DirectionalBlurCompositeTests`, `CompositorPipelineArchiveTests`) — Verified 2026-11-15: EffectOrderCompositeTests, MotionFeedbackCompositeTests, DirectionalBlurCompositeTests, CompositorPipelineArchiveTests pass in the full Compositor run (710, 0 failures)

## Phase 4: User Story 4 — chain, scenes, goldens (P2)

- [X] FX-010-T09 [US4] `SceneEffectSettings.echo` and the `fx.echo` entry (read, clamp, write, `isDefault`) in
  `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift`; round-trip and clamp tests in
  `SceneEffectChainTests` (FX-010-R14, S5) — Verified 2026-11-15: swift test (SceneFormat), 212 pass incl. testEchoEntryRoundTripsAndTheCountIsCapped
- [X] FX-010-T10 [US4] RenderGoldens: `GoldenSceneRenderer.apply(effects:to:)` sets Echo; an inactive echo renders
  exactly as no chain, save/reload keeps values, in `EffectChainSceneTests` (FX-010-S4, S5) — Verified 2026-11-15: swift test --filter EffectChainScene (RenderGoldens), 8 pass incl. testInactiveEchoRendersExactlyAsNoChainAndReloads

## Phase 5: App (P2)

- [X] FX-010-T11 [US1] `EchoSetting` in `Apps/projectM-iOS/Coordinators/EchoSetting.swift` (keys
  `settings.echo.enabled`, `.count`, `.delay`, `.decay`; written only when changed; clamped on read) and
  `AppCoordinator+Echo.swift` (effective value under ACC-012); wire in `AppCoordinator.swift` (init, connect, the four
  hosts, `applyReduceFlashing`, UI-test reset), `AppCoordinator+EffectChain.swift`, `AppCoordinator+SceneHistory.swift`,
  `SceneAutosaveCapture.swift` (FX-010-R1, R10, R13) — Verified 2026-11-15: EchoSettingTests 5/5 on the own iOS 27.2 simulator; app unit tests 1316, 1 failure (ExternalDisplayCoordinatorTests.testInfoPlistConfiguresOnlyTheExternalDisplayRole, pre-existing from UIX-008 multi-window, unrelated)
- [X] FX-010-T12 [US1] `EchoSection` in `Apps/projectM-iOS/Views/EchoSection.swift` (toggle, ACC-005 Echoes, Delay and
  Fade sliders) beside the Directional blur section in `SettingsView.swift`; Effect order row and name in
  `EffectChainView.swift` and `EffectChainSetting.swift`; section id in `UITestSettingsSection.swift` (FX-010-R12) — Verified 2026-11-15: EchoUITests 1/1 (19.0 s) and EffectChainUITests (Echo row present, 15.5 s) on the own simulator; type-check run shows no FX-010 warning (the one EffectChainView.swift:21 warning also appears on the commit before the app change)
- [X] FX-010-T13 [US1] Keys in `LibrarySettingsPolicy.includedKeys` (`LibrarySettings.swift`), `ALLOWED_KEYS`
  (`scripts/run_device_tests.py`), `LibraryBackupAppTests` and `LibraryEraseAppTests` key lists (FX-010-R13) — Verified 2026-11-15: LibraryBackupAppTests 5/5, LibraryEraseAppTests 3/3, SettingsTests 9/9 on the simulator; LibraryBackup package 88 pass; test_scripts 186 OK
- [X] FX-010-T14 [US1] `EchoSettingTests` in `Apps/projectM-iOS/Tests/` (defaults, persistence, clamp incl. count
  > 4, readouts, ACC-012 effective value, scene and preset round trip through the app paths, a real host's compositor);
  run `LibraryBackupAppTests`, `LibraryEraseAppTests`, `SettingsTests`, `EffectChainSettingTests` — Verified 2026-11-15: EchoSettingTests 5/5, EffectChainSettingTests 6/6, ChromaticSplitSettingTests, DirectionalBlurSettingTests 5/5, LibraryBackupAppTests, LibraryEraseAppTests, SettingsTests pass
- [X] FX-010-T15 [US1] `EchoUITests` in `Apps/projectM-iOS/UITests/` (off by default, turn on, readouts, drag Echoes to
  4; under 30 s) and the Effect order row check in `EffectChainUITests` (FX-010-S6) — Verified 2026-11-15: EchoUITests.testEchoControls passed (18.99 s), EffectChainUITests.testReorderEffects passed (15.50 s)

## Phase 6: Polish

- [ ] FX-010-T16 Repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`,
  `check_status_events`, `test_scripts`, `check_privacy_manifest`, `check_network_symbols`), type-check budget, test
  report `docs/test-reports/echo-feedback.md`, spec status
- [ ] FX-010-T17 {device} On D1 open Camera, turn on Echo with 4 echoes at 200 ms, wave a hand: four fading copies
  trail it and the frame rate stays at the visual's normal rate (FX-010-S7)

## Dependencies

T01 → T02/T03/T04 → T05 → T06 → T07/T08 → T09 → T10 → T11 → T12/T13 → T14/T15 → T16. T17 last, on a device.
T02 and T03 are parallel (different files). The app phase needs T09 (scene settings).

## Parallel example

T02 (model) and T03 (its tests) in different files; T12 (view) and T13 (key lists) once T11 exists.

## Implementation strategy

MVP is Phase 3 (the pass and its acceptance tests: cap, bounded memory, echo maths, off identity); then chain and
scenes, then the app.
