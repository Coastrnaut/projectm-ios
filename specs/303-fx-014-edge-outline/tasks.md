# Tasks: FX-014 Edge Outline

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/edge-outline.md](contracts/edge-outline.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (GPU acceptance, CPU reference, goldens, round trip, app and UI tests). Budgets:
unit test ≤ 10 s, suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [X] FX-014-T01 ADR-0114 (edge outline pass, Sobel on linear luminance, mask rule, overlay identity, chain position,
  ACC-012 colour cap) in `docs/adr/0114-edge-outline.md` and its row in `docs/adr/README.md` — Verified 2026-11-15: docs/adr/0114-edge-outline.md and README row; validate_docs OK

## Phase 2: Foundational

- [X] FX-014-T02 [P] `EdgeOutline`, `EdgeOutlineMode`, `EdgeOutlineColor` in
  `Packages/Compositor/Sources/Compositor/EdgeOutline.swift`: threshold "0.02…1, 0.2" (NaN → default, else clamped),
  width "1…3, 1" (rounded, clamped), colour sRGB 0…1 each clamped with hex "RRGGBB" parse/format (unreadable → white),
  mode overlay/outlineOnly; `isActive` (on, ≥ 2 × 2), `limited(by: SafetyClamp)`, `block`, `luminance`, `strength`,
  `mask`, `reference` (contract C2); plain Swift (Linux) — Verified 2026-11-15: EdgeOutlineModelTests 4/4 on the host
- [X] FX-014-T03 [P] `EdgeOutlineModelTests` in `Packages/Compositor/Tests/CompositorTests/`: clamps and hex; sRGB →
  linear; flat picture strength 0 everywhere incl. the border; a vertical step outlined on 2 × width columns; threshold
  at or above the step's contrast → mask 0; ACC-012 limit scales the colour (FX-014-R2 to R6, R13, R15) — Verified 2026-11-15: swift test --filter EdgeOutlineModelTests, 4 pass
- [X] FX-014-T04 `OutputEffectKind.edgeOutline` (`fx.edgeOutline`, appended after `mosaic`) in
  `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`; update the existing whole-order assertions in
  `OutputEffectOrderTests` and add a position-based one (FX-014-R7) — Verified 2026-11-15: OutputEffectOrderTests pass (host), position asserts firstIndex(of: .edgeOutline) == 7

## Phase 3: User Stories 1-2 — the pass (P1)

**Goal**: outlines along edges on every compositor output, no outline on flat pictures, exact identity when off.
**Independent test**: GPU tests through the real compositor.

- [X] FX-014-T05 [US1] `EdgeOutlinePass` with `cmp_edge_outline` in
  `Packages/Compositor/Sources/Compositor/EdgeOutlinePass.swift` (one pooled picture, released when unused) — Verified 2026-11-15: EdgeOutlineCompositeTests 4/4 on the host (real Metal device)
- [X] FX-014-T06 [US1] `Compositor.swift`: `edgeOutline` property, splice the source at the existing compile site, the
  `.edgeOutline` case in `encodeOutputEffects` (Color folded before it), release in deinit; add the source to
  `CompositorShaderSources.archived` in `CompositorShaders.swift` (FX-014-R8, R12, R14) — Verified 2026-11-15: Compositor package on the host: CompositorTests 741 tests, 0 failures (10 skipped); CompositorPipelineArchiveTests pass
- [X] FX-014-T07 [US1] [US2] `EdgeOutlineCompositeTests` in `Packages/Compositor/Tests/CompositorTests/`: flat pictures
  (several colours) bit-identical in overlay and black in outline-only; 8-pixel checkerboard: outlined pixels = the
  reference mask (boundaries only), widths 1 and 3; threshold above the contrast draws nothing; off bit-identical with
  no picture held; order and pool (FX-014-S1 to S4) — Verified 2026-11-15: EdgeOutlineCompositeTests 4/4 (host): flat pictures bit-identical (overlay) and black (outline only), checkerboard mask = reference at widths 1 and 3, threshold 0.3 > contrast 0.25 draws nothing, off bit-identical
- [X] FX-014-T08 [US1] Existing compositor tests still pass (`MosaicCompositeTests`, `EffectOrderCompositeTests`,
  `CompositorPipelineArchiveTests`) — Verified 2026-11-15: MosaicCompositeTests, EffectOrderCompositeTests, CompositorPipelineArchiveTests pass in the full host run

## Phase 4: User Story 3 — chain, scenes, goldens (P2)

- [X] FX-014-T09 [US3] `SceneEffectSettings.edgeOutline` and the `fx.edgeOutline` entry (read, clamp, write,
  `isDefault`) in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift` and
  `SceneEffectChain+EdgeOutline.swift`; `EdgeOutlineSceneEntryTests`; whole-order updates in `SceneEffectChainTests`;
  the new file in `SceneSourceSafetyTests` (FX-014-R11, S5) — Verified 2026-11-15: SceneFormat 218 tests on the host (EdgeOutlineSceneEntryTests 2/2, SceneSourceSafetyTests)
- [X] FX-014-T10 [US3] RenderGoldens: `GoldenSceneRenderer.apply(effects:to:)` sets the outline;
  `EdgeOutlineSceneGoldenTests` (disabled entry renders as no chain; an outline scene round-trips and differs from the
  plain one); `EffectChainSceneTests` order update; existing goldens unchanged (FX-014-S4) — Verified 2026-11-15: RenderGoldens 115 tests on the host (EdgeOutlineSceneGoldenTests 2/2, EffectChainSceneTests)

## Phase 5: App (US1, US3)

- [ ] FX-014-T11 [US1] `EdgeOutlineSetting` (five keys) in `Apps/projectM-iOS/Coordinators/EdgeOutlineSetting.swift`
  and `AppCoordinator+EdgeOutline.swift` (effective value under the safety clamp); wire into `AppCoordinator.swift`
  (init, the four compositor creations, the safety-clamp re-apply, scene apply, reset), `+SceneHistory`, `+EffectChain`,
  `SceneAutosaveCapture.applyEffects` (FX-014-R1, R10, R15)
- [ ] FX-014-T12 [US1] Keys in `scripts/run_device_tests.py` `ALLOWED_KEYS`, FILE-005
  `LibrarySettingsPolicy.includedKeys`, the UI-test reset, `LibraryBackupAppTests` and `LibraryEraseAppTests`
  `appKeys` (FX-014-R10)
- [ ] FX-014-T13 [US1] `EdgeOutlineSection` (toggle, ACC-005 Threshold slider, Width and Mode pickers, ColorPicker,
  help) in `Apps/projectM-iOS/Views/EdgeOutlineSection.swift`, one line in `SettingsView.swift`, the section ID in
  `UITestSettingsSection.swift`; Effect order row and name in `EffectChainView.swift`/`EffectChainSetting.swift`
  (FX-014-R9)
- [ ] FX-014-T14 [US1] App tests `EdgeOutlineSettingTests` (persistence, clamp, slider, keys, scene/preset round trip,
  compositor push, ACC-012 cap) and the whole-order updates in `EffectChainSettingTests` and the other effect setting
  tests; `SettingsTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests` pass
- [ ] FX-014-T15 [US1] UI test `EdgeOutlineUITests` (find, turn on, move Threshold, choose Outline only) under 30 s
  (FX-014-S6)

## Phase 6: Polish

- [ ] FX-014-T16 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests),
  privacy manifest and network symbols on the Debug app, type-check budget
- [ ] FX-014-T17 Test report in `docs/test-reports/edge-outline.md`; spec status
- [ ] FX-014-T18 {device} On D1: Camera visual, Edge outline at threshold 0.2, widths 1 and 3, both modes: outlines
  follow edges, flat areas clean; frame rate with and without recorded (FX-014-S7)

## Dependencies

T02 → T03; T04, T05 → T06 → T07, T08 → T09 → T10; T09 → T11 → T12-T15 → T16 → T17. T18 after integration.

## Parallel opportunities

T02/T03 with T01; T09 can start after T04; the section view (T13) with the setting tests (T14).

## Implementation strategy

MVP is Phases 1-3 (the pass with its acceptance tests); then scenes and goldens; then the app.
