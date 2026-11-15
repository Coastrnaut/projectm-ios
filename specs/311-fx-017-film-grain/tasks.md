# Tasks: FX-017 Film grain

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/film-grain.md](contracts/film-grain.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (GPU acceptance, CPU reference, exact GPU hash, goldens, round trip, app and UI
tests). Budgets: unit test ≤ 10 s, suite < 1 min, UI test < 30 s. Never assert raw texture byte sizes.

## Phase 1: Setup

- [ ] FX-017-T01 ADR-0122 (film grain pass last in the chain, PCG integer hash, exact noise, additive bounded blend with
  the zero floor, grain frame ≤ 24 Hz from the injected clock, static under Reduce Motion and Reduce flashing) in
  `docs/adr/0122-film-grain.md` and its row in `docs/adr/README.md`

## Phase 2: Foundational

- [ ] FX-017-T02 [P] `FilmGrain` in `Packages/Compositor/Sources/Compositor/FilmGrain.swift`: value and ranges (data
  model), clamps, `isActive`, `grainFrame`, `effective(reduceMotion:)`, `block`, `pcg`, `hash`, `noise`,
  `referencePixel`, `reference` (contract C2); plain Swift (Linux)
- [ ] FX-017-T03 [P] `FilmGrainModelTests` in `Packages/Compositor/Tests/CompositorTests/`: clamps (NaN, ±Inf,
  fractions); hash fixed vectors and determinism; noise exact multiples of 2⁻²³ in [−1, 1); size-2 cells share a value;
  monochrome channels equal, colour red equals monochrome; grain frame 0 when static or Reduce flashing, ≤ 24 steps per
  second at 120 Hz, wraps at 2³²; mean over a uniform grey within 0.005 and every change within the bound; opacity 0
  reference is the input (FX-017-R2 to R6, R13, S3, S4)
- [ ] FX-017-T04 `OutputEffectKind.filmGrain` (`fx.filmGrain`, appended after `vignette`) in
  `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`; update the existing whole-order assertions in
  `OutputEffectOrderTests` and add a position-based one (FX-017-R8)

## Phase 3: User Stories 1-3 — the pass (P1, P2)

**Goal**: deterministic seeded grain on every compositor output, exact identity at opacity zero, capped temporal steps.
**Independent test**: GPU tests through the real compositor.

- [ ] FX-017-T05 [US1] `FilmGrainPass` with `cmp_grain_hash`, `cmp_grain_noise` and `cmp_film_grain` in
  `Packages/Compositor/Sources/Compositor/FilmGrainPass.swift` (one pooled picture, released when unused)
- [ ] FX-017-T06 [US1] `Compositor.swift`: `filmGrain` property, splice the source at the existing compile site, the
  `.filmGrain` case in `encodeOutputEffects` (Color folded before it; grain frame from the frame context), release in
  deinit; add the source to `CompositorShaderSources.archived` in `CompositorShaders.swift` (FX-017-R7, R12, R14)
- [ ] FX-017-T07 [US1] [US2] [US3] `FilmGrainCompositeTests` in `Packages/Compositor/Tests/CompositorTests/`: off and
  opacity 0 (several seeds, sizes, colour, temporal) bit-identical with no pass and no picture; the pass encoded
  directly at opacity 0 bit-identical; GPU hash and noise equal the CPU exactly (test kernel through
  `CompositorShaders.library`); output equals the reference within one half-float step; two renders and two frame
  times identical when static; seeds differ; temporal: different 1⁄24 s steps differ, same step identical, Reduce
  flashing static; uniform grey mean within 0.005, bound held, all finite; order last and pool release (FX-017-S1 to S4)
- [ ] FX-017-T08 [US1] Existing compositor tests still pass (`VignetteCompositeTests`, `EffectOrderCompositeTests`,
  `CompositorPipelineArchiveTests`, the whole Compositor suite)

## Phase 4: User Story 4 — chain, scenes, goldens (P2)

- [ ] FX-017-T09 [US4] `SceneEffectSettings.filmGrain` (property set after `init`) and the `fx.filmGrain` entry (read,
  clamp, write, `isDefault`) in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift` and
  `SceneEffectChain+FilmGrain.swift`; `FilmGrainSceneEntryTests`; whole-order updates in `SceneEffectChainTests`; the new
  file in `SceneSourceSafetyTests` (FX-017-R11, S5)
- [ ] FX-017-T10 [US4] RenderGoldens: `GoldenSceneRenderer.apply(effects:to:)` sets the grain;
  `FilmGrainSceneGoldenTests` (off and opacity 0 render as no chain; a grain scene round-trips and renders identically
  twice; stored golden images in `GeneratorGoldens/FilmGrain/` for macos and ios-simulator, with their integrity test);
  `EffectChainSceneTests` order update; existing goldens unchanged (FX-017-S1, S2, S5)

## Phase 5: App (US1, US3, US4)

- [ ] FX-017-T11 [US1] `FilmGrainSetting` (six keys) in `Apps/projectM-iOS/Coordinators/FilmGrainSetting.swift` and
  `AppCoordinator+FilmGrain.swift` (effective value under Reduce Motion); wire into `AppCoordinator.swift` (init, the
  four compositor creations, scene apply, reset, Reduce Motion change), `+SceneHistory`, `+EffectChain`,
  `SceneAutosaveCapture.applyEffects` (FX-017-R1, R4, R10)
- [ ] FX-017-T12 [US1] Keys in `scripts/run_device_tests.py` `ALLOWED_KEYS`, FILE-005
  `LibrarySettingsPolicy.includedKeys`, the UI-test reset, `LibraryBackupAppTests` and `LibraryEraseAppTests` `appKeys`
  (FX-017-R10)
- [ ] FX-017-T13 [US1] `FilmGrainSection` (toggle, ACC-005 Opacity slider "30%", Size and Color pickers, Seed stepper,
  Vary over time toggle, help) in `Apps/projectM-iOS/Views/FilmGrainSection.swift`, one line in `SettingsView.swift`, the
  section ID in `UITestSettingsSection.swift`; Effect order row and name in `EffectChainView.swift` and
  `EffectChainSetting.swift` (FX-017-R9)
- [ ] FX-017-T14 [US1] App tests `FilmGrainSettingTests` (persistence, clamp, readout, keys, scene/preset round trip,
  compositor push, Reduce Motion makes the pushed grain static) and the whole-order updates in `EffectChainSettingTests`
  and the other effect setting tests; `SettingsTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests` pass (FX-017-S6)
- [ ] FX-017-T15 [US1] UI test `FilmGrainUITests` (find, turn on, move Opacity, step Seed) under 30 s; `EffectChainUITests`
  pass (FX-017-S6)

## Phase 6: Polish

- [ ] FX-017-T16 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy
  manifest and network symbols on the Debug app, type-check budget; test report in `docs/test-reports/film-grain.md`;
  spec status
- [ ] FX-017-T17 {device} On D1: Photo visual, Film grain at 100 %, sizes 1-3, colour and monochrome, Vary over time on
  (gentle, no strobing) and with Reduce Motion on (still); frame rate with and without recorded (FX-017-S7)

## Dependencies

T02 → T03; T04, T05 → T06 → T07, T08 → T09 → T10; T09 → T11 → T12-T15 → T16. T17 after integration.

## Parallel opportunities

T02/T03 with T01; T09 can start after T04; the section view (T13) with the setting tests (T14).

## Implementation strategy

MVP is Phases 1-3 (the pass with its acceptance tests); then scenes and goldens; then the app.
