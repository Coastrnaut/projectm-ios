# Tasks: FX-016 Lens Distortion

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/lens-distortion.md](contracts/lens-distortion.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (GPU acceptance, CPU reference, goldens, round trip, app and UI tests). Budgets:
unit test ≤ 10 s, suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [X] FX-016-T01 ADR-0117 (lens distortion pass, bounded radial polynomial k = 0.3 × strength, half-diagonal
  normalisation, zoom to fill, clamped bilinear taps with exact centre read, transparent-black fill, chain position) in
  `docs/adr/0117-lens-distortion.md` and its row in `docs/adr/README.md` — Verified 2026-11-15: docs/adr/0117-lens-distortion.md and README row; validate_docs OK

## Phase 2: Foundational

- [X] FX-016-T02 [P] `LensDistortion` in `Packages/Compositor/Sources/Compositor/LensDistortion.swift`: strength
  "−1…1, 0.3" (NaN → default, else clamped), zoomToFill "true"; `coefficient` (0.3 × strength), `isActive` (on, k ≠ 0,
  ≥ 2 × 2), `block`, `radialMap`, `sample` (source position, inside flag), `taps`, `referencePixel`, `reference`
  (contract C2); plain Swift (Linux) — Verified 2026-11-15: LensDistortionModelTests 5/5 on the host
- [X] FX-016-T03 [P] `LensDistortionModelTests` in `Packages/Compositor/Tests/CompositorTests/`: clamps; zero strength
  maps every pixel centre to itself; dense-grid safety at strength ±1, zoom on and off, at 1:1, 16:9, 9:16, 1:64, 64:1
  and 2 × 2 (every inside sample in 0…W × 0…H, every tap in 0…W − 1 × 0…H − 1, outside only for barrel with zoom off,
  all values finite); radial mapping strictly increasing at every strength step; reference output finite (FX-016-R2 to
  R6, R12, S2, S3) — Verified 2026-11-15: swift test --filter LensDistortionModelTests, 5 pass (dense grids at 1:1, 16:9, 9:16, 1:64, 64:1, 2 × 2, 2 × 4096, 4096 × 2; radial map strictly increasing at all 200 strength steps)
- [X] FX-016-T04 `OutputEffectKind.lensDistortion` (`fx.lensDistortion`, appended after `edgeOutline`) in
  `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`; update the existing whole-order assertions in
  `OutputEffectOrderTests` and add a position-based one (FX-016-R7) — Verified 2026-11-15: OutputEffectOrderTests 5/5 on the host; position asserts firstIndex(of: .lensDistortion) == 8

## Phase 3: User Stories 1-2 — the pass (P1)

**Goal**: a bounded barrel/pincushion warp on every compositor output, exact identity at zero, safe corners.
**Independent test**: GPU tests through the real compositor.

- [X] FX-016-T05 [US1] `LensDistortionPass` with `cmp_lens_distortion` in
  `Packages/Compositor/Sources/Compositor/LensDistortionPass.swift` (one pooled picture, released when unused) — Verified 2026-11-15: LensDistortionCompositeTests 4/4 on the host (real Metal device)
- [X] FX-016-T06 [US1] `Compositor.swift`: `lensDistortion` property, splice the source at the existing compile site,
  the `.lensDistortion` case in `encodeOutputEffects` (Color folded before it), release in deinit; add the source to
  `CompositorShaderSources.archived` in `CompositorShaders.swift` (FX-016-R6, R11, R13) — Verified 2026-11-15: Compositor package on the host: CompositorTests 760 tests, 0 failures (10 skipped), whole package 56.6 s; CompositorPipelineArchiveTests pass
- [X] FX-016-T07 [US1] [US2] `LensDistortionCompositeTests` in `Packages/Compositor/Tests/CompositorTests/`: off and
  strength 0 bit-identical with no pass and no picture; the pass encoded directly at strength 0 bit-identical (`@testable import Compositor`, as `OutputEffectOrderTests`); ±1 with
  zoom on and off equals the reference within half-float rounding, all finite, middle pixel exact; corners transparent
  black at +1 with zoom off; order and pool (FX-016-S1, S2, S4) — Verified 2026-11-15: LensDistortionCompositeTests 4/4 (host, 0.5 s): off/strength 0 bit-identical with no pass; pass run at k = 0 bit-identical on 37 × 29, 2 × 2, 3 × 64; ±1 zoom on/off GPU = reference, finite, middle exact, corners black only at barrel with zoom off
- [X] FX-016-T08 [US1] Existing compositor tests still pass (`EdgeOutlineCompositeTests`, `EffectOrderCompositeTests`,
  `CompositorPipelineArchiveTests`, the whole Compositor suite) — Verified 2026-11-15: EdgeOutlineCompositeTests, EffectOrderCompositeTests, CompositorPipelineArchiveTests pass in the full host run (760 tests)

## Phase 4: User Story 3 — chain, scenes, goldens (P2)

- [X] FX-016-T09 [US3] `SceneEffectSettings.lensDistortion` (property set after `init`) and the `fx.lensDistortion` entry
  (read, clamp, write, `isDefault`) in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift` and
  `SceneEffectChain+LensDistortion.swift`; `LensDistortionSceneEntryTests`; whole-order updates in
  `SceneEffectChainTests`; the new file in `SceneSourceSafetyTests` (FX-016-R10, S6) — Verified 2026-11-15: SceneFormat 222 tests on the host, 0 failures (LensDistortionSceneEntryTests 2/2, SceneEffectChainTests, SceneSourceSafetyTests)
- [X] FX-016-T10 [US3] RenderGoldens: `GoldenSceneRenderer.apply(effects:to:)` sets the warp;
  `LensDistortionSceneGoldenTests` (off and strength 0 render as no chain; a lens scene round-trips and differs from the
  plain one); `EffectChainSceneTests` order update; existing goldens unchanged (FX-016-S5) — Verified 2026-11-15: RenderGoldens 117 tests on the host, 0 failures, 1 skipped (LensDistortionSceneGoldenTests 2/2, EffectChainSceneTests), 33.9 s

## Phase 5: App (US1, US3)

- [X] FX-016-T11 [US1] `LensDistortionSetting` (three keys) in
  `Apps/projectM-iOS/Coordinators/LensDistortionSetting.swift` and `AppCoordinator+LensDistortion.swift`; wire into
  `AppCoordinator.swift` (init, the four compositor creations, scene apply, reset), `+SceneHistory`, `+EffectChain`,
  `SceneAutosaveCapture.applyEffects` (FX-016-R1, R9) — Verified 2026-11-15: app unit tests 1359/1359 on the own iOS 27.2 simulator (LensDistortionSettingTests 5/5, incl. the host compositor push)
- [X] FX-016-T12 [US1] Keys in `scripts/run_device_tests.py` `ALLOWED_KEYS`, FILE-005
  `LibrarySettingsPolicy.includedKeys`, the UI-test reset, `LibraryBackupAppTests` and `LibraryEraseAppTests` `appKeys`
  (FX-016-R9) — Verified 2026-11-15: LibraryBackupAppTests, LibraryEraseAppTests, LensDistortionSettingTests.testLensDistortionKeysAreBackedUpErasedAndNamed, SettingsTests pass (full app suite 1359)
- [X] FX-016-T13 [US1] `LensDistortionSection` (toggle, ACC-005 Strength slider with "+30%" readout, Zoom to fill
  toggle, help) in `Apps/projectM-iOS/Views/LensDistortionSection.swift`, one line in `SettingsView.swift`, the section
  ID in `UITestSettingsSection.swift`; Effect order row and name in `EffectChainView.swift`/`EffectChainSetting.swift`
  (FX-016-R8) — Verified 2026-11-15: LensDistortionUITests and EffectChainUITests pass on the own simulator
- [X] FX-016-T14 [US1] App tests `LensDistortionSettingTests` (persistence, clamp, readout, slider step, keys,
  scene/preset round trip, compositor push) and the whole-order updates in `EffectChainSettingTests` and the other
  effect setting tests; `SettingsTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests` pass (FX-016-S6, S7) — Verified 2026-11-15: LensDistortionSettingTests 5/5, EffectChainSettingTests, Chromatic/Directional/Radial/Echo/Mosaic/EdgeOutline setting tests, SettingsTests, LibraryBackupAppTests, LibraryEraseAppTests pass (full app unit suite 1359, 52 s)
- [X] FX-016-T15 [US1] UI test `LensDistortionUITests` (find, turn on, move Strength) under 30 s (FX-016-S7) — Verified 2026-11-15: LensDistortionUITests 1/1 (12.9 s)

## Phase 6: Polish

- [ ] FX-016-T16 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests),
  privacy manifest and network symbols on the Debug app, type check budget; test report in `docs/test-reports/lens-distortion.md`; spec status
- [ ] FX-016-T17 {device} On D1: Camera visual, Lens distortion at +100 % and −100 %, zoom on and off: bulge and pinch,
  corners show picture (black only at barrel with zoom off), no sparkles; frame rate with and without recorded
  (FX-016-S8)

## Dependencies

T02 → T03; T04, T05 → T06 → T07, T08 → T09 → T10; T09 → T11 → T12-T15 → T16. T17 after integration.

## Parallel opportunities

T02/T03 with T01; T09 can start after T04; the section view (T13) with the setting tests (T14).

## Implementation strategy

MVP is Phases 1-3 (the pass with its acceptance tests); then scenes and goldens; then the app.
