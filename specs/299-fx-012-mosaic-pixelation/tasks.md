# Tasks: FX-012 Mosaic Pixelation

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/mosaic.md](contracts/mosaic.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (GPU acceptance, CPU reference, goldens, round trip, app and UI tests). Budgets:
unit test ≤ 10 s, suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [ ] FX-012-T01 ADR-0110 (mosaic pass, centre-pixel rule, grid anchors, chain position) in
  `docs/adr/0110-mosaic-pixelation.md` and its row in `docs/adr/README.md`

## Phase 2: Foundational

- [ ] FX-012-T02 [P] `Mosaic` value and `MosaicShape` in `Packages/Compositor/Sources/Compositor/Mosaic.swift`:
  blockSize 1…64 (default 8; Double clamp: NaN → default, rounded, nearest bound), shape square/hexagon; `isActive`
  (on, size ≥ 2, ≥ 2 × 2), `squareCell`, `hexCell`, `samplePixel`, `block`, `reference` (contract C2); plain Swift
  (Linux)
- [ ] FX-012-T03 [P] `MosaicModelTests` in `Packages/Compositor/Tests/CompositorTests/`: clamps; inactive cases
  (size 1); square cell assignment and centre pixels incl. partial edge blocks; hex cell assignment (centres map to
  themselves, a pixel at a known offset maps to the expected neighbour), every sample pixel inside the frame;
  reference identity at size 1 (FX-012-R2 to R6, R12)
- [ ] FX-012-T04 `OutputEffectKind.mosaic` (`fx.mosaic`, appended) in
  `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`; update `OutputEffectOrderTests` (FX-012-R7)

## Phase 3: User Stories 1-2 — the pass (P1)

**Goal**: flat squares or hexagons on every compositor output, exact identity at size 1 and off.
**Independent test**: GPU tests through the real compositor.

- [ ] FX-012-T05 [US1] `MosaicPass` with `cmp_mosaic` in `Packages/Compositor/Sources/Compositor/MosaicPass.swift`
  (one pooled picture, released when unused)
- [ ] FX-012-T06 [US1] `Compositor.swift`: `mosaic` property, splice the source at the existing compile site, the
  `.mosaic` case in `encodeOutputEffects` (Color folded before it), release in deinit; add the source to
  `CompositorShaderSources.archived` (FX-012-R4, R7, R11, R13)
- [ ] FX-012-T07 [US1] [US2] `MosaicCompositeTests` in `Packages/Compositor/Tests/CompositorTests/`: off and size 1
  (both shapes) bit-identical on random content with no picture held; size 8 squares on random content: every 8 × 8
  block uniform and equal to its centre pixel, adjacent blocks differ; hexagons at size 12: cells uniform at points
  away from borders; GPU = reference (squares exact everywhere, hexagons away from borders); order and pool
  (FX-012-S1 to S4)
- [ ] FX-012-T08 [US1] Existing compositor tests still pass (`RadialBlurCompositeTests`, `EffectOrderCompositeTests`,
  `CompositorPipelineArchiveTests`)

## Phase 4: User Story 3 — chain, scenes, goldens (P2)

- [ ] FX-012-T09 [US3] `SceneEffectSettings.mosaic` and the `fx.mosaic` entry (read, clamp, write, `isDefault`) in
  `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift`; round-trip tests in a new
  `MosaicSceneEntryTests` and order updates in `SceneEffectChainTests` (FX-012-R10, S5)
- [ ] FX-012-T10 [US3] RenderGoldens: `GoldenSceneRenderer.apply(effects:to:)` sets the mosaic; size 1 renders as no
  chain and a mosaic scene round-trips in `EffectChainSceneTests`; existing goldens unchanged (FX-012-S1)

## Phase 5: App (US1, US3)

- [ ] FX-012-T11 [US1] `MosaicSetting` (three keys) in `Apps/projectM-iOS/Coordinators/MosaicSetting.swift` and
  `AppCoordinator+Mosaic.swift`; wire into `AppCoordinator.swift` (init, the four compositor creations, scene apply,
  reset), `+SceneHistory`, `+EffectChain`, `SceneAutosaveCapture.applyEffects` (FX-012-R1, R9)
- [ ] FX-012-T12 [US1] Keys in `scripts/run_device_tests.py` `ALLOWED_KEYS`, FILE-005 `LibrarySettingsPolicy.includedKeys`,
  the UI-test reset, `LibraryBackupAppTests` and `LibraryEraseAppTests` `appKeys` (FX-012-R9)
- [ ] FX-012-T13 [US1] `MosaicSection` (toggle, ACC-005 Block size slider, Square/Hexagon picker, help) in
  `Apps/projectM-iOS/Views/MosaicSection.swift`, one line in `SettingsView.swift`, the section ID in
  `UITestSettingsSection.swift`; Effect order row and name in `EffectChainView.swift`/`EffectChainSetting.swift`
  (FX-012-R8)
- [ ] FX-012-T14 [US1] App tests `MosaicSettingTests` (persistence, clamp, slider, keys, scene/preset round trip,
  compositor push) and `EffectChainSettingTests`, `ChromaticSplitSettingTests`, `SettingsTests`,
  `LibraryBackupAppTests`, `LibraryEraseAppTests` pass
- [ ] FX-012-T15 [US1] UI test `MosaicUITests` (find, turn on, move Block size, switch to Hexagon) under 30 s
  (FX-012-S6)

## Phase 6: Polish

- [ ] FX-012-T16 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests),
  privacy manifest and network symbols on the Debug app, type-check budget
- [ ] FX-012-T17 Test report in `docs/test-reports/mosaic-pixelation.md`; spec status
- [ ] FX-012-T18 {device} On D1: Photo visual, Mosaic at 8 and 64 in both shapes, blocks flat and discrete, frame rate
  with and without recorded (FX-012-S7)

## Dependencies

T02 → T03; T04, T05 → T06 → T07, T08 → T09 → T10; T09 → T11 → T12-T15 → T16 → T17. T18 after integration.

## Parallel opportunities

T02/T03 with T01; T09 can start after T04; the section view (T13) with the setting tests (T14).

## Implementation strategy

MVP is Phases 1-3 (the pass with its acceptance tests); then scenes and goldens; then the app.
