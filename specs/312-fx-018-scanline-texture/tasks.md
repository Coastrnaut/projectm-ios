# Tasks: FX-018 Scanline texture

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/scanlines.md](contracts/scanlines.md), [quickstart.md](quickstart.md)

Tests are requested by the brief (shader unit test, GPU acceptance, CPU reference, goldens, round trip, app and UI
tests). Budgets: unit test ≤ 10 s, suite < 1 min, UI test < 30 s. Never assert raw `MTLTexture.allocatedSize`.

## Phase 1: Setup

- [X] FX-018-T01 ADR-0123 (scanline pass, integer line rule anchored at pixel 0, darken-only single factor, chain
  position after Vignette and before Film grain) in `docs/adr/0123-scanline-texture.md` and its row in
  `docs/adr/README.md` — Verified 2026-11-15: docs/adr/0123-scanline-texture.md and README row; validate_docs OK

## Phase 2: Foundational

- [X] FX-018-T02 [P] `Scanlines` value in `Packages/Compositor/Sources/Compositor/Scanlines.swift`: spacing "2…16
  pixels (step 1)" default 3, thickness "1…15 pixels (step 1); used as min(thickness, spacing − 1)" default 1,
  intensity "0…1 (step 0.01)" default 0.5, isVertical default false (NaN → default; ±Inf and out of range → nearest
  bound; spacing and thickness rounded); `isActive` (on, intensity > 0, ≥ 2 × 2); `block` (16 bytes), `isDark`,
  `factor`, `reference` (contract C2); plain Swift (Linux) — Verified 2026-11-15: ScanlinesModelTests 5/5 on the host and in the Linux shape (-DCOMPOSITOR_NO_METAL, own scratch path)
- [X] FX-018-T03 [P] `ScanlinesModelTests` in `Packages/Compositor/Tests/CompositorTests/`: clamps; effective
  thickness; inactive cases; the rule anchored at index 0 for every spacing; zero intensity is identity; finite output
  for finite and HDR input (FX-018-R2 to R5, R12) — Verified 2026-11-15: swift test --filter ScanlinesModelTests, 5 pass (0.006 s)
- [X] FX-018-T04 `OutputEffectKind.scanlines` (`fx.scanlines`, appended after Vignette) in
  `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`; update `OutputEffectOrderTests` (FX-018-R7) — Verified 2026-11-15: OutputEffectOrderTests 5/5 (host and Linux shape)

## Phase 3: User Stories 1-2 — the pass (P1)

**Goal**: exact scanlines on every compositor output, exact identity at zero intensity and off.
**Independent test**: GPU tests through the real compositor.

- [X] FX-018-T05 [US1] `ScanlinesPass` with `cmp_scanlines` in
  `Packages/Compositor/Sources/Compositor/ScanlinesPass.swift` (one pooled picture, released when unused; one exact
  read per pixel, an integer modulo and at most one multiply, no loop: FX-018-R6) — Verified 2026-11-15: ScanlinesCompositeTests 6/6 on the host (real Metal device); shader is one read, a modulo, at most one multiply
- [X] FX-018-T06 [US1] `Compositor.swift`: `scanlines` property, splice the source at the existing compile site, the
  `.scanlines` case in `encodeOutputEffects` (Color folded before it), release in deinit; add the source to
  `CompositorShaderSources.archived` (FX-018-R4, R7, R11, R13) — Verified 2026-11-15: Compositor package suite on the host: CompositorTests 787 tests, 0 failures (10 skipped), 56 s; CompositorPipelineArchiveTests pass
- [X] FX-018-T07 [US1] [US2] `ScanlinesCompositeTests` (the shader unit test) in
  `Packages/Compositor/Tests/CompositorTests/`: off and intensity 0 (several spacings, thicknesses, both
  orientations) bit-identical on random content with no picture held; the pass run directly with intensity 0
  bit-identical; for every spacing 2…16 at 37 × 23, 61 × 97 (portrait) and 129 × 45 (landscape), plus spacings 2, 3
  and 16 at 3840 × 2160, a uniform picture has exactly the rows c mod p < t darkened by one factor, all other pixels
  bit-identical and the measured pitch = p for every pair of bands; vertical columns the same; random content equals
  the half-rounded reference (untouched pixels exact, darkened within one half step, research D5); HDR input gives finite output; order and pool (FX-018-S1 to S3) — Verified 2026-11-15: ScanlinesCompositeTests 6/6 in 0.61 s (4K case 0.34 s): identity off/zero and shader at 0 bit-identical; spacings 2…16 at 37×23, 61×97, 129×45 both orientations, 2/3/16 at 3840×2160: exact rows, one factor, pitch = spacing; reference within one half step; finite HDR

## Phase 4: User Story 3 — scenes and the chain (P2)

- [X] FX-018-T08 [US3] `fx.scanlines` entry: `SceneEffectSettings.scanlines` (set after `init`), read/write in
  `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain+Scanlines.swift` with one case per switch in
  `SceneEffectChain.swift`; tests for round trip, clamping and old scenes byte-identical in
  `Packages/SceneFormat/Tests/SceneFormatTests/ScanlinesSceneEntryTests.swift`; the source-safety list names the new
  file; update `SceneEffectChainTests` if it lists the order (FX-018-R10, S4) — Verified 2026-11-15: SceneFormat suite 226 tests, 0 failures (2.8 s), incl. ScanlinesSceneEntryTests 2/2, SceneSourceSafetyTests and the order lists in SceneEffectChainTests
- [X] FX-018-T09 [US3] RenderGoldens: apply `effects.scanlines` in `GoldenSceneRenderer.swift`;
  `ScanlinesSceneGoldenTests` (intensity 0 and off render exactly as no chain; a scanline scene saved and reloaded
  renders the same picture with dark rows exactly at c mod p < t); update `EffectChainSceneTests` if it lists the order
  (FX-018-S1, S4) — Verified 2026-11-15: RenderGoldens suite 128 tests, 0 failures (1 on-demand skip), 39 s wall incl. build; ScanlinesSceneGoldenTests 2/2 (intensity 1 lines exactly black at the predicted rows/columns, all other pixels equal to the plain frame); EffectChainSceneTests with Scanlines in the order
- [X] FX-018-T10 [US1] [US3] App setting: `ScanlinesSetting` (five keys, "absent or malformed → default, out of range →
  nearest bound", lowering spacing lowers a larger thickness), `AppCoordinator+Scanlines.swift`, the compositor pushes
  in `AppCoordinator.swift`, the UI-test reset, scene and preset apply (`SceneAutosaveCapture`,
  `AppCoordinator+EffectChain`, `+SceneHistory`), keys in `LibrarySettings.swift`, `scripts/run_device_tests.py`,
  `LibraryBackupAppTests`, `LibraryEraseAppTests` (FX-018-R1, R9) — Verified 2026-11-15: own iOS 27.2 simulator (FX18): ScanlinesSettingTests 5/5, LibraryBackupAppTests, LibraryEraseAppTests, SettingsTests pass (70 app tests in 13 suites, 0 failures, 0.66 s); LibraryBackup package 88 tests, 0 failures
- [X] FX-018-T11 [US1] [US3] UI: `ScanlinesSection.swift` (toggle, three ACC-005 sliders, orientation picker, help text)
  in Settings, the Effect order row and name in `EffectChainSetting`/`EffectChainView`; `ScanlinesSettingTests`
  (persistence with a reloaded store, clamping, thickness follows spacing, scene apply); the spoken values ("3 pixels",
  "50 percent") and the disabled Thickness slider at spacing 2; update the order tests that
  list every kind; `ScanlinesUITests` under 30 s; `EffectChainUITests` still pass (FX-018-R8, S5) — Verified 2026-11-15: ScanlinesUITests.testScanlinesControls passed in 13.4 s (readouts "3 px", "1 px", "50%", spoken "3 pixels", spacing dragged to "16 px"); EffectChainUITests.testReorderEffects passed (17.7 s); EffectChainSettingTests and the Chromatic/Directional/Radial/Echo/Mosaic/Lens/Vignette setting tests pass with Scanlines appended

## Phase 5: Polish

- [X] FX-018-T12 Repo checks (`test_scripts`, `check_compliance`, `validate_docs`, `check_motion_policy`,
  `check_permission_catalog`, `check_status_events`), package suites (Compositor, SceneFormat, LibraryBackup,
  RenderGoldens), the Linux-shape build of the model, the app's `SettingsTests`, backup and erase tests — Verified 2026-11-15: six repo checks OK (test_scripts 186 tests OK), check_privacy_manifest OK and check_network_symbols OK on the Debug app; Compositor 787, SceneFormat 226, LibraryBackup 88, RenderGoldens 128 (0 failures); Linux-shape model tests 10/10; app SettingsTests, backup and erase tests pass
- [X] FX-018-T13 Type-check budget on the new app files (`-warn-long-function-bodies=300`,
  `-warn-long-expression-type-checking=150`), no warnings from the new files — Verified 2026-11-15: build-for-testing with -warn-long-function-bodies=300 -warn-long-expression-type-checking=150: no warning in any new or FX-018-edited body (existing bodies near 300 ms under load listed in the report)
- [X] FX-018-T14 Test report `docs/test-reports/scanline-texture.md`; spec status Implemented — Verified 2026-11-15: docs/test-reports/scanline-texture.md; spec status Implemented; validate_docs OK
- [X] FX-018-T15 Own simulator and derived data deleted; PosterBoard reports counted before and after (in the report) — Verified 2026-11-15: xcrun simctl delete of "FX18 iPhone 17" and rm of the worktree derived data and Linux-shape scratch path; PosterBoard reports 25 before, 25 after (in the report)
- [ ] FX-018-T16 {device} On D1, Photo visual: Scanlines at spacing 2, 3 and 16, intensity 100 %, both orientations:
  even lines, no crawl or flicker; frame rate with and without it (FX-018-S6)

## Dependencies

T02 → T03, T05; T04 → T06; T05 → T06 → T07, T09; T08 → T09, T10; T10 → T11; all → T12-T15. T16 needs a device.
Parallel: T02 with T04; T08 with T05-T07.

## Implementation Strategy

MVP: T02-T07 (the pass and its proof). Then scenes (T08-T09), then the app (T10-T11), then polish.
