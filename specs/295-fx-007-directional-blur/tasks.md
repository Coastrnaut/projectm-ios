# Tasks: FX-007 Directional Blur

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/directional-blur.md](contracts/directional-blur.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (GPU acceptance through the real compositor, CPU reference, goldens, scene round
trip, app and UI tests). Budgets: unit test ≤ 10 s, suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [X] FX-007-T01 ADR-0106 (directional blur pass, fixed 16-tap kernel, clamped samples, chain position) in
  `docs/adr/0106-directional-blur.md` and its row in `docs/adr/README.md` — Verified 2026-11-15: docs/adr/0106-directional-blur.md and README row

## Phase 2: Foundational

- [X] FX-007-T02 [P] `DirectionalBlur` value in `Packages/Compositor/Sources/Compositor/DirectionalBlur.swift`: fields
  "radius 0…0.02, default 0.005", "angleDegrees 0…180, default 0, folds mod 180"; clamp (NaN → default),
  `radiusPixels`, `isActive`, `tapCount` 16, `unitOffsets`, Gaussian `weights` (σ = radius ÷ 2, sum 1), the shader
  block, clamped sample positions and the CPU `referencePixel`/`reference` (contract C2); plain Swift (Linux) — Verified 2026-11-15: DirectionalBlurModelTests 8/8 on the host; Compositor builds in the Linux shape (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE)
- [X] FX-007-T03 [P] `DirectionalBlurModelTests` in `Packages/Compositor/Tests/CompositorTests/`: clamp and fold,
  zero/disabled inactive, 16 taps at every radius with weights summing to 1 and symmetric offsets reaching ±radius,
  0° taps vary only in x and 90° only in y, every sample position inside the frame at the maximum, reference zero
  identity, energy kept on a line, a non-finite own pixel passes and non-finite samples never spread
  (FX-007-R2 to R7, R13, S3) — Verified 2026-11-15: swift test --filter DirectionalBlurModelTests, 8 pass
- [X] FX-007-T04 `OutputEffectKind.directionalBlur` (`fx.directionalBlur`, appended after `chromatic`) in
  `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`; update `OutputEffectOrderTests` (FX-007-R8) — Verified 2026-11-15: OutputEffectOrderTests 5/5 on the host

## Phase 3: User Stories 1-3 — the pass (P1)

**Goal**: the blur on every compositor output, exact identity at radius zero, horizontal at 0°, fixed cost.
**Independent test**: GPU tests through the real compositor.

- [X] FX-007-T05 [US1] `DirectionalBlurPass` with `cmp_directional_blur` (constant `cmp_dirblur_taps = 16`) in
  `Packages/Compositor/Sources/Compositor/DirectionalBlurPass.swift` (one pooled picture, released when unused) — Verified 2026-11-15: DirectionalBlurCompositeTests 5/5 on the host (Metal)
- [X] FX-007-T06 [US1] `Compositor.swift`: `directionalBlur` property, splice the source at the existing compile site,
  the `.directionalBlur` case in `encodeOutputEffects` (Color folded before it), release in deinit; add the source to
  `CompositorShaderSources.archived` in `CompositorShaders.swift` (FX-007-R7, R8, R12, R14) — Verified 2026-11-15: whole Compositor package on the host, 0 failures (1:22); CompositorPipelineArchiveTests pass
- [X] FX-007-T07 [US1] [US2] [US3] `DirectionalBlurCompositeTests` in `Packages/Compositor/Tests/CompositorTests/`:
  radius 0 and off bit-identical on random content (scene and screen output, no picture held); at 0° a short vertical
  line spreads only horizontally (rows outside unchanged, row energy within 1%) and at 90° only vertically; maximum
  radius keeps every value within the frame's range; GPU ≈ CPU reference; the shader source declares 16 taps; the
  picture returns when turned off (FX-007-S1 to S5) — Verified 2026-11-15: DirectionalBlurCompositeTests 5/5 on the host (radius 0 bit-identical, 0° rows / 90° columns, energy ±1%, range, GPU vs CPU ≤ 1/256, tap constant, pool)
- [X] FX-007-T08 [US1] Existing compositor tests still pass (`ChromaticSplitCompositeTests`,
  `EffectOrderCompositeTests`, `MotionFeedbackCompositeTests`, `CompositorPipelineArchiveTests`) — Verified 2026-11-15: ChromaticSplitCompositeTests, EffectOrderCompositeTests, MotionFeedbackCompositeTests, CompositorPipelineArchiveTests pass in the full Compositor run

## Phase 4: User Story 4 — chain, scenes, goldens (P2)

- [X] FX-007-T09 [US4] `SceneEffectSettings.directionalBlur` and the `fx.directionalBlur` entry (read, clamp, write,
  `isDefault`) in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift`; round-trip tests in
  `SceneEffectChainTests` (FX-007-R11, S6) — Verified 2026-11-15: swift test --filter SceneEffectChain, 15 pass
- [X] FX-007-T10 [US4] RenderGoldens: `GoldenSceneRenderer.apply(effects:to:)` sets the blur; zero blur renders exactly
  as no chain, save/reload keeps values and picture, in `EffectChainSceneTests` (FX-007-S1, S6) — Verified 2026-11-15: swift test --filter EffectChainScene (RenderGoldens), 7 pass

## Phase 5: App (P2)

- [X] FX-007-T11 [US1] `DirectionalBlurSetting` in `Apps/projectM-iOS/Coordinators/DirectionalBlurSetting.swift` (keys
  `settings.directionalBlur.enabled`, `.radius`, `.angle`; written only when changed; clamped on read) and
  `AppCoordinator+DirectionalBlur.swift`; wire in `AppCoordinator.swift` (init, connect, the four hosts, UI-test
  reset), `AppCoordinator+EffectChain.swift`, `AppCoordinator+SceneHistory.swift`, `SceneAutosaveCapture.swift`
  (FX-007-R1, R10) — Verified 2026-11-15: DirectionalBlurSettingTests 5/5 on the own iOS 27.2 simulator; app unit tests 1302, 0 failures
- [X] FX-007-T12 [US1] `DirectionalBlurSection` in `Apps/projectM-iOS/Views/DirectionalBlurSection.swift` (toggle, ACC-005
  Radius and Angle sliders) added beside the Chromatic split section in `SettingsView.swift`; Effect order row and
  name in `EffectChainView.swift` and `EffectChainSetting.swift`; section id in `UITestSettingsSection.swift`
  (FX-007-R9) — Verified 2026-11-15: DirectionalBlurUITests (18.8 s) and EffectChainUITests (row present) pass on the own simulator; type-check run shows no FX-007 warning
- [X] FX-007-T13 [US1] Keys in `LibrarySettingsPolicy.includedKeys` (`LibrarySettings.swift`), `ALLOWED_KEYS`
  (`scripts/run_device_tests.py`), `LibraryBackupAppTests` and `LibraryEraseAppTests` key lists (FX-007-R10) — Verified 2026-11-15: LibraryBackupAppTests, LibraryEraseAppTests, SettingsTests pass; LibraryBackup package 88 pass; scripts 186 OK
- [X] FX-007-T14 [US1] `DirectionalBlurSettingTests` in `Apps/projectM-iOS/Tests/` (defaults, persistence, clamp,
  readouts, slider steps, keys backed up, scene and preset round trip through the app paths, a real host's
  compositor) and the updated `EffectChainSettingTests`; run `LibraryBackupAppTests`, `LibraryEraseAppTests`,
  `SettingsTests` — Verified 2026-11-15: DirectionalBlurSettingTests 5/5, EffectChainSettingTests, ChromaticSplitSettingTests, LibraryBackupAppTests, LibraryEraseAppTests, SettingsTests pass (33 tests)
- [X] FX-007-T15 [US1] `DirectionalBlurUITests` in `Apps/projectM-iOS/UITests/` (off by default, turn on, readouts,
  drag Radius to 2.0%; under 30 s) and the Effect order row check in `EffectChainUITests` (FX-007-S7) — Verified 2026-11-15: DirectionalBlurUITests 1/1 (18.8 s), EffectChainUITests 1/1 (13.5 s)

## Phase 6: Polish

- [X] FX-007-T16 Repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`,
  `check_status_events`, `test_scripts`, `check_privacy_manifest`, `check_network_symbols`), type-check budget, test
  report `docs/test-reports/directional-blur.md`, spec status — Verified 2026-11-15: all six repo checks OK, check_privacy_manifest and check_network_symbols OK on the Debug app; docs/test-reports/directional-blur.md
- [ ] FX-007-T17 {device} On D1 open Photo, turn on Directional blur at 2% and 45°: the streak looks right and the
  frame rate stays at the visual's normal rate (FX-007-S8)

## Dependencies

T01 → T02/T03/T04 → T05 → T06 → T07/T08 → T09 → T10 → T11 → T12/T13 → T14/T15 → T16. T17 last, on a device.
T02 and T03 are parallel (different files). The app phase needs T09 (scene settings).

## Implementation strategy

MVP is Phase 3 (the pass and its acceptance tests: radius zero identity, horizontal at 0°); then chain and scenes,
then the app.
