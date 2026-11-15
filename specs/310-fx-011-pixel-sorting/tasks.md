# Tasks: FX-011 Pixel Sorting Approximation

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/pixel-sort.md](contracts/pixel-sort.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (GPU vs CPU reference, threshold dependence, budget model, identity, goldens, round
trip, settings, one UI test). Budgets: unit test ≤ 10 s, suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [ ] FX-011-T01 ADR-0121 (pixel sort as one compute dispatch, tiles and segments, stable rank-and-scatter, frame budget
  B and span reduction, chain position before Vignette) in `docs/adr/0121-pixel-sort.md` and its row in
  `docs/adr/README.md`

## Phase 2: Foundational

- [ ] FX-011-T02 [P] `PixelSort` in `Packages/Compositor/Sources/Compositor/PixelSort.swift`: threshold, span, direction
  with clamping and span snapping; `luminance`, `qualifies`, `plan(width:height:budget:)` (contract C3), `block`,
  `reference` (contract C2, Swift stable sort per segment); plain Swift (Linux)
- [ ] FX-011-T03 [P] `PixelSortModelTests` in `Packages/Compositor/Tests/CompositorTests/`: clamping and snapping; plan
  over sizes 1 × 1 … 16384 × 16384 (common displays, 7680 × 4320, extremes) × every span: workload ≤ B, effective span
  the largest admissible, skip exactly when W·H·4 > B, inactive when off or too small; reference: segments
  non-decreasing, non-qualifying pixels unchanged, permutation per tile, thresholds 0.5 and 0.2 give different outputs
  (FX-011-R2 to R7, R13, S1, S2, S4)
- [ ] FX-011-T04 `OutputEffectKind.pixelSort` (`fx.pixelSort`, declared between `lensDistortion` and `vignette`) in
  `OutputEffectOrder.swift`; update whole-order assertions in `OutputEffectOrderTests` and add a position-based one
  (FX-011-R8)

## Phase 3: User Stories 1-2 — the pass (P1)

**Goal**: segments sorted by luminance on every compositor output within the frame budget.
**Independent test**: GPU tests through the real compositor.

- [ ] FX-011-T05 [US1] `PixelSortPass` with `cmp_pixel_sort` in `PixelSortPass.swift` (one pooled picture, one dispatch,
  fixed loops of `span` steps)
- [ ] FX-011-T06 [US1] [US2] `Compositor.swift`: `pixelSort` property and counters, the source at the existing compile
  site, the `.pixelSort` case in `encodeOutputEffects` (Color folded before it; plan; skip counted), release in deinit;
  source in `CompositorShaderSources.archived` (FX-011-R5 to R7, R12, R14)
- [ ] FX-011-T07 [US1] [US2] `PixelSortCompositeTests`: GPU equals the CPU reference bit for bit at thresholds 0.5 and
  0.2, both directions, with a partial last tile; the two outputs differ; non-qualifying pixels unchanged; off
  bit-identical with no dispatch and no picture; one dispatch per active frame and workload ≤ B; a lowered budget skips
  with zero dispatches and identical output; finite output for finite random input; archive key contains the source
  (FX-011-S1 to S4)

## Phase 4: User Story 3 — scenes and goldens (P2)

- [ ] FX-011-T08 [US3] `fx.pixelSort` scene entry: `SceneEffectSettings.pixelSort` (set after init) in
  `SceneEffectChain.swift`, read/write in `SceneEffectChain+PixelSort.swift`; `PixelSortSceneEntryTests` (round trip,
  clamping and span snapping reported, off not written); update `SceneEffectChainTests`, `SceneSourceSafetyTests`
  (FX-011-R11, S6)
- [ ] FX-011-T09 [US3] Golden renderer applies `pixelSort`; `PixelSortSceneGoldenTests` (off equals no chain; a saved
  pixel-sort scene reloads and renders the same picture; sorted output differs from unsorted) and update
  `EffectChainSceneTests` (FX-011-S5)

## Phase 5: App

- [ ] FX-011-T10 [US1] `PixelSortSetting` (four keys), `AppCoordinator+PixelSort.swift`, coordinator wiring (push to the
  compositors, scene and preset apply, autosave capture, effect-chain toggle), keys in `LibrarySettings`,
  `scripts/run_device_tests.py` ALLOWED_KEYS, the UI-test reset, `LibraryBackupAppTests`, `LibraryEraseAppTests`;
  `PixelSortSettingTests` (defaults, clamping, persistence through a reloaded store) (FX-011-R10, S7)
- [ ] FX-011-T11 [US1] Settings → Pixel sort section (`PixelSortSection.swift`: toggle, ACC-005 Threshold slider, Span
  and Direction pickers, footer) and the Effect order row (`EffectChainSetting`, `EffectChainView`) (FX-011-R9)
- [ ] FX-011-T12 [US1] `PixelSortUITests` (find, turn on, change threshold; < 30 s) and existing app tests that list the
  whole order (FX-011-S7)

## Phase 6: Polish

- [ ] FX-011-T13 Test report `docs/test-reports/pixel-sort.md` (commands, counts, times)
- [ ] FX-011-T14 Repo checks: `test_scripts.py`, `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
  `check_permission_catalog.py`, `check_status_events.py`, privacy manifest and network symbols on the Debug app
- [ ] FX-011-T15 Package suites (Compositor, SceneFormat, LibraryBackup, RenderGoldens) and the app's affected tests on
  the own simulator; spec status Implemented
- [ ] FX-011-T16 {device} GPU frame time with Pixel sort on (span 32 and 64, both directions) on D1, and on a 4K external
  display if available (FX-011-S8)

## Dependencies

T01 → T02/T03/T04 → T05 → T06 → T07 → T08 → T09 → T10 → T11 → T12 → T13-T15; T16 last.
