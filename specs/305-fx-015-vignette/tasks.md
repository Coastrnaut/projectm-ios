# Tasks: FX-015 Vignette

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/vignette.md](contracts/vignette.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (shader unit test, GPU acceptance, CPU reference, goldens, round trip, app and UI
tests). Budgets: unit test ≤ 10 s, suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [ ] FX-015-T01 ADR-0116 (vignette pass, falloff rule, darken-only, chain position) in `docs/adr/0116-vignette.md`
  and its row in `docs/adr/README.md`

## Phase 2: Foundational

- [ ] FX-015-T02 [P] `Vignette` value in `Packages/Compositor/Sources/Compositor/Vignette.swift`: intensity "0…1
  (step 0.01)" default 0.5, softness "0.1…0.9 (step 0.05)" default 0.5, centerX/centerY "0…1 (step 0.05)" default
  0.5 (NaN → default; ±Inf and out of range → nearest bound); `isActive` (on, intensity > 0, ≥ 2 × 2); `block`
  (32 bytes), `weight`, `factor`, `reference` (contract C2); plain Swift (Linux)
- [ ] FX-015-T03 [P] `VignetteModelTests` in `Packages/Compositor/Tests/CompositorTests/`: clamps; inactive cases;
  zero intensity is identity at centre and corners; the centre pixel exact at any intensity and softness (clear
  core); weight monotonic along centre→corner rays; centre control moves the brightest pixel; finite outputs for
  finite and HDR input (FX-015-R2 to R5, R12)
- [ ] FX-015-T04 `OutputEffectKind.vignette` (`fx.vignette`, appended last) in
  `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`; update `OutputEffectOrderTests` (FX-015-R7)

## Phase 3: User Stories 1-2 — the pass (P1)

**Goal**: smooth edge darkening on every compositor output, exact identity at zero intensity and off.
**Independent test**: GPU tests through the real compositor.

- [ ] FX-015-T05 [US1] `VignettePass` with `cmp_vignette` in
  `Packages/Compositor/Sources/Compositor/VignettePass.swift` (one pooled picture, released when unused)
- [ ] FX-015-T06 [US1] `Compositor.swift`: `vignette` property, splice the source at the existing compile site, the
  `.vignette` case in `encodeOutputEffects` (Color folded before it), release in deinit; add the source to
  `CompositorShaderSources.archived` (FX-015-R4, R7, R11, R13)
- [ ] FX-015-T07 [US1] [US2] `VignetteCompositeTests` (the shader unit test) in
  `Packages/Compositor/Tests/CompositorTests/`: off and intensity 0 (several softness and centre values)
  bit-identical on random content with no picture held, centre and corners included; on a uniform picture the
  centre pixel is exact at intensities 0.3 and 1, brightness never rises centre→corner and corners are darker;
  moving the centre moves the brightest pixel; GPU ≈ reference; HDR input gives finite output; order and pool
  (FX-015-S1 to S4)

## Phase 4: User Story 3 — scenes and the chain (P2)

- [ ] FX-015-T08 [US3] `fx.vignette` entry: `SceneEffectSettings.vignette`, read/write in
  `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain+Vignette.swift` with one case per switch in
  `SceneEffectChain.swift`; tests for round trip, clamping and old scenes byte-identical in
  `Packages/SceneFormat/Tests/SceneFormatTests/VignetteSceneEntryTests.swift`; the source-safety list names the new
  file (FX-015-R10, S5)
- [ ] FX-015-T09 [US3] RenderGoldens: apply `effects.vignette` in `GoldenSceneRenderer.swift`;
  `VignetteSceneGoldenTests` (intensity 0 and off render exactly as no chain; a vignette scene saved and reloaded
  renders the same picture, darker at the corners, centre unchanged); update `EffectChainSceneTests` if it lists the
  order (FX-015-S1, S5)
- [ ] FX-015-T10 [US1] [US3] App setting: `VignetteSetting` (five keys, "absent or malformed → default, out of range →
  nearest bound"), `AppCoordinator+Vignette.swift`, the compositor pushes in `AppCoordinator.swift`, the UI-test
  reset, scene and preset apply (`SceneAutosaveCapture`, `AppCoordinator+EffectChain`, `+SceneHistory`), keys in
  `LibrarySettings.swift`, `scripts/run_device_tests.py`, `LibraryBackupAppTests`, `LibraryEraseAppTests`
  (FX-015-R1, R9)
- [ ] FX-015-T11 [US1] [US3] UI: `VignetteSection.swift` (toggle, four ACC-005 sliders, help text) in Settings, the
  Effect order row and name in `EffectChainSetting`/`EffectChainView`; `VignetteSettingTests` (persistence with a
  reloaded store, clamping, scene apply); update the order tests that list every kind; `VignetteUITests` under 30 s
  (FX-015-R8, S6)

## Phase 5: Polish

- [ ] FX-015-T12 Repo checks (`test_scripts`, `check_compliance`, `validate_docs`, `check_motion_policy`,
  `check_permission_catalog`, `check_status_events`), package suites (Compositor, SceneFormat, LibraryBackup,
  RenderGoldens), the Linux-shape build of the model, the app's `SettingsTests`, backup and erase tests
- [ ] FX-015-T13 Test report `docs/test-reports/vignette.md`; spec status Implemented
- [ ] FX-015-T14 Type-check budget on the new app files (`-warn-long-function-bodies=300`,
  `-warn-long-expression-type-checking=150`), no warnings from the new files
- [ ] FX-015-T15 {device} On D1, Photo visual: Vignette at intensity 100 % with softness 10 % and 90 % and the centre
  moved: edges darken smoothly and the middle is unchanged; frame rate with and without it (FX-015-S7)

## Dependencies

T02 → T03, T05; T04 → T06; T05 → T06 → T07, T09; T08 → T09, T10; T10 → T11; all → T12-T14. T15 needs a device.
Parallel: T02 with T04; T08 with T05-T07.

## Implementation Strategy

MVP: T02-T07 (the pass and its proof). Then scenes (T08-T09), then the app (T10-T11), then polish.
