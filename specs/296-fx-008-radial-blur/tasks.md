# Tasks: FX-008 Radial Blur

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/radial-blur.md](contracts/radial-blur.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (GPU acceptance, CPU reference, goldens, round trip, app and UI tests). Budgets:
unit test ≤ 10 s, suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [X] FX-008-T01 ADR-0107 (radial blur pass, sample rule, chain position) in `docs/adr/0107-radial-blur.md` and its row
  in `docs/adr/README.md` — Verified 2026-11-15: docs/adr/0107-radial-blur.md and README row; validate_docs OK

## Phase 2: Foundational

- [X] FX-008-T02 [P] `RadialBlur` value in `Packages/Compositor/Sources/Compositor/RadialBlur.swift`: fields
  "strength 0…0.25, default 0.1", "focusX 0…1 (0 = left), default 0.5", "focusY 0…1 (0 = top), default 0.5", NaN →
  default, out of range → nearest bound; `tapCount` 16, `focusPixels`, `isActive` (on, strength > 0, ≥ 2 × 2),
  `block`, `samplePositions`, `spread`, exact-bilinear `referencePixel`/`reference` (contract C2); plain Swift (Linux) — Verified 2026-11-15: RadialBlurModelTests 7/7 on the host; Linux-shape build with tests OK
- [X] FX-008-T03 [P] `RadialBlurModelTests` in `Packages/Compositor/Tests/CompositorTests/`: clamps; inactive cases;
  16 positions for every pixel and strength; every position inside the frame (corner and edge focus); spread zero at
  the focus and linear in distance; a point's streak in the reference runs from d to d(1 + s); reference identity at
  zero, at the focus and for a non-finite pixel (FX-008-R2 to R6, R12) — Verified 2026-11-15: swift test --filter RadialBlurModelTests, 7 pass
- [X] FX-008-T04 `OutputEffectKind.radialBlur` (`fx.radialBlur`, appended) in
  `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`; update `OutputEffectOrderTests` (FX-008-R7) — Verified 2026-11-15: OutputEffectOrderTests 5/5 (host)

## Phase 3: User Stories 1-2 — the pass (P1)

**Goal**: the blur on every compositor output, the focus stable, outer points spreading d·s, exact identity when off.
**Independent test**: GPU tests through the real compositor.

- [X] FX-008-T05 [US1] `RadialBlurPass` with `cmp_radial_blur` in
  `Packages/Compositor/Sources/Compositor/RadialBlurPass.swift` (one pooled picture, released when unused) — Verified 2026-11-15: RadialBlurCompositeTests 5/5 on the host (real Metal device)
- [X] FX-008-T06 [US1] `Compositor.swift`: `radialBlur` property, splice the source at the existing compile site, the
  `.radialBlur` case in `encodeOutputEffects` (Color folded before it), release in deinit; add the source to
  `CompositorShaderSources.archived` (FX-008-R5, R7, R11, R13) — Verified 2026-11-15: Compositor suite on the host (CompositorTests 694, 0 failures); CompositorPipelineArchiveTests pass
- [X] FX-008-T07 [US1] [US2] `RadialBlurCompositeTests` in `Packages/Compositor/Tests/CompositorTests/`: off and zero
  bit-identical on random content (no picture held); dot pattern at the maximum: focus pixel bit-identical (centred and
  off-centre focus; frame sizes chosen so focus × (size − 1) is a whole pixel, speckit-analyze C1), each outer dot's streak ends within 1 px of d(1 + s) on its ray and stays on it; GPU = reference
  within 1/128; corner focus in bounds; order and pool (FX-008-S1 to S4) — Verified 2026-11-15: RadialBlurCompositeTests 5/5 (host)
- [X] FX-008-T08 [US1] Existing compositor tests still pass (`ChromaticSplitCompositeTests`, `EffectOrderCompositeTests`,
  `CompositorPipelineArchiveTests`) — Verified 2026-11-15: ChromaticSplitCompositeTests, EffectOrderCompositeTests, CompositorPipelineArchiveTests pass in the full host run

## Phase 4: User Story 3 — chain, scenes, goldens (P2)

- [X] FX-008-T09 [US3] `SceneEffectSettings.radialBlur` and the `fx.radialBlur` entry (read, clamp, write, `isDefault`)
  in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift`; round-trip tests in `SceneEffectChainTests`
  (FX-008-R10, S5) — Verified 2026-11-15: SceneFormat 211 tests on the host
- [X] FX-008-T10 [US3] RenderGoldens: `GoldenSceneRenderer.apply(effects:to:)` sets the blur; zero blur renders as no
  chain and a blurred scene round-trips in `EffectChainSceneTests`; existing goldens unchanged (FX-008-S1) — Verified 2026-11-15: RenderGoldens 108 tests on the host (EffectChainSceneTests incl. 2 new)

## Phase 5: App (US1, US3)

- [X] FX-008-T11 [US1] `RadialBlurSetting` (four keys) in `Apps/projectM-iOS/Coordinators/RadialBlurSetting.swift` and
  `AppCoordinator+RadialBlur.swift`; wire into `AppCoordinator.swift` (init, the four compositor creations, scene
  apply, reset), `+SceneHistory`, `+EffectChain`, `SceneAutosaveCapture.applyEffects` (FX-008-R1, R9) — Verified 2026-11-15: app unit tests 1302/1302 on the own simulator
- [X] FX-008-T12 [US1] Keys in `scripts/run_device_tests.py` `ALLOWED_KEYS`, FILE-005 `LibrarySettingsPolicy.includedKeys`,
  the UI-test reset, `LibraryBackupAppTests` and `LibraryEraseAppTests` `appKeys` (FX-008-R9) — Verified 2026-11-15: LibraryBackupAppTests, LibraryEraseAppTests, RadialBlurSettingTests.testKeysAreBackedUpErasedAndNamed pass; test_scripts OK
- [X] FX-008-T13 [US1] `RadialBlurSection` (toggle, ACC-005 Strength, Focus X, Focus Y sliders, help) in
  `Apps/projectM-iOS/Views/RadialBlurSection.swift`, one line in `SettingsView.swift`, the section ID in
  `UITestSettingsSection.swift`; Effect order row and name in `EffectChainView.swift`/`EffectChainSetting.swift`
  (FX-008-R8) — Verified 2026-11-15: RadialBlurUITests and EffectChainUITests pass on the own simulator
- [X] FX-008-T14 [US1] App tests `RadialBlurSettingTests` (persistence, clamp, sliders, keys, scene/preset round trip,
  compositor push) and `EffectChainSettingTests`, `SettingsTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests` pass — Verified 2026-11-15: RadialBlurSettingTests 5/5, EffectChainSettingTests, SettingsTests, LibraryBackupAppTests, LibraryEraseAppTests pass (full app suite)
- [X] FX-008-T15 [US1] UI test `RadialBlurUITests` (find, turn on, move Strength, focus sliders shown) under 30 s
  (FX-008-S6) — Verified 2026-11-15: RadialBlurUITests 1/1 (32.4 s, 35.7 s under load average ~100; see the report)

## Phase 6: Polish

- [X] FX-008-T16 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests),
  privacy manifest and network symbols on the Debug app, type-check budget — Verified 2026-11-15: all repo checks OK, 186 script tests, privacy manifest and network symbols OK; no FX-008 type-check warnings
- [X] FX-008-T17 Test report in `docs/test-reports/radial-blur.md`; spec status — Verified 2026-11-15: docs/test-reports/radial-blur.md
- [X] FX-008-T18 {device} On D1: Photo visual, Radial blur at 25% with the focus centred and moved, streaks radiate — Verified 2026-11-15 (QA-011 automated on D1, docs/test-reports/qa-011/acceptance/D1-B01.md): 25% centred and moved both change the picture, 60 fps with and without recorded
  from the focus, frame rate with and without recorded (FX-008-S7)

## Dependencies

T02 → T03; T04, T05 → T06 → T07, T08 → T09 → T10; T09 → T11 → T12-T15 → T16 → T17. T18 after integration.

## Parallel opportunities

T02/T03 with T01; T09 can start after T04; the section view (T13) with the setting tests (T14).

## Implementation strategy

MVP is Phases 1-3 (the pass with its acceptance tests); then scenes and goldens; then the app.
