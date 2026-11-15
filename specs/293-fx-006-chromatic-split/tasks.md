# Tasks: FX-006 Chromatic Split

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/chromatic-split.md](contracts/chromatic-split.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (GPU acceptance, CPU reference, goldens, round trip, app and UI tests). Budgets:
unit test ≤ 10 s, suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [X] FX-006-T01 ADR-0104 (chromatic split placement, edge rule, chain position) in `docs/adr/0104-chromatic-split.md`
  and its row in `docs/adr/README.md` — Verified 2026-11-15: docs/adr/0104-chromatic-split.md and README row; validate_docs OK

## Phase 2: Foundational

- [X] FX-006-T02 [P] `ChromaticSplit` value in `Packages/Compositor/Sources/Compositor/ChromaticSplit.swift`: fields
  "amount 0…0.02, default 0.005", "angleDegrees 0…360, default 0, wraps", "isRadial default false"; clamp (NaN →
  default), `amountPixels`, `isActive`, edge-faded `vector`, clamped bilinear sample positions and the CPU
  `referencePixel`/`reference` (contract C2); plain Swift (Linux) — Verified 2026-11-15: ChromaticSplitModelTests 7/7 on the host; Linux-shape build OK
- [X] FX-006-T03 [P] `ChromaticSplitModelTests` in `Packages/Compositor/Tests/CompositorTests/`: clamp and wrap,
  zero/disabled inactive, linear and radial vectors, fade (border ring zero, full beyond the band), every sample in
  bounds at the maximum, reference zero identity and whole-pixel shift, alpha = max of the samples, a non-finite own pixel or
  neighbour (weight 0) never spreads, frames under 3 px pass through (FX-006-R3, R4, R6, R12) — Verified 2026-11-15: swift test --filter ChromaticSplitModelTests, 7 pass
- [X] FX-006-T04 `OutputEffectKind.chromatic` (`fx.chromatic`, appended) in
  `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`; update `OutputEffectOrderTests` (FX-006-R7) — Verified 2026-11-15: OutputEffectOrderTests pass (host)

## Phase 3: User Stories 1-3 — the pass (P1)

**Goal**: the split on every compositor output, exact pass-through at zero, edges inside the frame.
**Independent test**: GPU tests through the real compositor.

- [X] FX-006-T05 [US1] `ChromaticSplitPass` with `cmp_chromatic` in
  `Packages/Compositor/Sources/Compositor/ChromaticSplitPass.swift` (one pooled picture, released when unused) — Verified 2026-11-15: ChromaticSplitCompositeTests 5/5 on the host and the own iOS 27.2 simulator
- [X] FX-006-T06 [US1] `Compositor.swift`: `chromaticSplit` property, splice the source at the existing compile site,
  the order walk (Color folded before an active spatial effect), release in deinit; add the source to
  `CompositorShaderSources.archived` in `CompositorShaders.swift` (FX-006-R5, R7, R11, R13) — Verified 2026-11-15: Compositor suite on host and simulator (1123 tests, 0 failures); CompositorPipelineArchiveTests pass
- [X] FX-006-T07 [US2] [US3] `ChromaticSplitCompositeTests` in `Packages/Compositor/Tests/CompositorTests/`: zero and
  off bit-identical on random content (scene and screen output, no picture held); bounds at the maximum (unique
  border colours, four angles and radial): every channel value from inside, border ring unchanged; line pattern
  shift ±d; GPU = CPU reference; order (split before/after Trails differs; FX-020 results unchanged with split off)
  (FX-006-S1 to S4) — Verified 2026-11-15: ChromaticSplitCompositeTests 5/5 (host and simulator)
- [X] FX-006-T08 [US1] Existing compositor tests still pass (`EffectOrderCompositeTests`, `MotionFeedbackCompositeTests`,
  `CompositorPipelineArchiveTests`) — Verified 2026-11-15: EffectOrderCompositeTests, MotionFeedbackCompositeTests, CompositorPipelineArchiveTests pass

## Phase 4: User Story 4 — chain, scenes, goldens (P2)

- [X] FX-006-T09 [US4] `SceneEffectSettings.chromatic` and the `fx.chromatic` entry (read, clamp, write, `isDefault`)
  in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift`; round-trip tests in
  `SceneEffectChainTests` (FX-006-R10, S5) — Verified 2026-11-15: SceneFormat 207 tests on host and simulator
- [X] FX-006-T10 [US4] RenderGoldens: `GoldenSceneRenderer.apply(effects:to:)` sets the split; one new golden test
  rendering a split scene on host and simulator; all existing goldens unchanged (FX-006-S1) — Verified 2026-11-15: RenderGoldens 106 tests on host and simulator (EffectChainSceneTests 5/5)

## Phase 5: App (US1, US4)

- [X] FX-006-T11 [US1] `ChromaticSplitSetting` (four keys) in `Apps/projectM-iOS/Coordinators/ChromaticSplitSetting.swift`
  and `AppCoordinator+ChromaticSplit.swift`; wire into `AppCoordinator.swift` (init, the four compositor creations,
  scene apply), `AppCoordinator+SceneHistory.swift` and `+EffectChain.swift` (undo/redo, presets), `liveEffectSettings`, `SceneAutosaveCapture.applyEffects` (FX-006-R1, R9) — Verified 2026-11-15: app unit tests 1287/1287 on the own simulator
- [X] FX-006-T12 [US1] Keys in `scripts/run_device_tests.py` `ALLOWED_KEYS`, FILE-005 `LibrarySettingsPolicy.includedKeys`,
  the UI-test reset, `LibraryBackupAppTests` `appKeys` (FX-006-R9) — Verified 2026-11-15: LibraryBackupAppTests, LibraryEraseAppTests, ChromaticSplitSettingTests.testKeysAreBackedUpErasedAndNamed pass; test_scripts OK
- [X] FX-006-T13 [US1] `ChromaticSplitSection` (toggle, ACC-005 Amount and Angle sliders, Radial switch, help) in
  `Apps/projectM-iOS/Views/ChromaticSplitSection.swift`, one line in `SettingsView.swift`; Effect order row and name in
  `EffectChainView.swift`/`EffectChainSetting.swift` (FX-006-R8) — Verified 2026-11-15: ChromaticSplitUITests and EffectChainUITests pass on the own simulator
- [X] FX-006-T14 [US1] App tests `ChromaticSplitSettingTests` (persistence, clamp, compositor push, scene/preset round
  trip) and `EffectChainSettingTests`, `SettingsTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests` pass — Verified 2026-11-15: ChromaticSplitSettingTests 5/5, EffectChainSettingTests, SettingsTests, LibraryBackupAppTests, LibraryEraseAppTests pass
- [X] FX-006-T15 [US1] UI test `ChromaticSplitUITests` (turn on, move Amount, relaunch keeps it) under 30 s (FX-006-S6) — Verified 2026-11-15: ChromaticSplitUITests 1/1, 19.2 s

## Phase 6: Polish

- [X] FX-006-T16 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests),
  privacy manifest and network symbols on the Debug app, type-check budget — Verified 2026-11-15: all repo checks OK, 186 script tests, privacy manifest and network symbols OK; type-check note in the report
- [X] FX-006-T17 Test report in `docs/test-reports/chromatic-split.md`; spec status — Verified 2026-11-15: docs/test-reports/chromatic-split.md
- [ ] FX-006-T18 {device} On D1: Photo visual, split at 2% and radial, fringes look right, frame rate recorded
  (FX-006-S7)

## Dependencies

T02 → T03; T04, T05 → T06 → T07, T08 → T09 → T10; T09 → T11 → T12-T15 → T16 → T17. T18 after integration.

## Parallel opportunities

T02/T03 with T01; T09 scene work can start after T04; the section view (T13) with the setting tests (T14).

## Implementation strategy

MVP is Phases 1-3 (the pass with its acceptance tests); then scenes and goldens; then the app.
