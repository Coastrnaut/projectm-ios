# Tasks: FX-002 Tone Mapping

**Input**: design documents in `specs/122-fx-002-tone-mapping/` (spec, plan, research, data-model,
contracts/tone-map.md, quickstart)

**Tests**: requested by the roadmap row (snapshot and shader unit tests) and the spec (FX-002-S1-S5, S7).
Budgets (owner rule 7): unit test about 1-2 s, at most 10 s; package suite under 1 minute.

Format: `- [ ] FX-002-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac
cannot finish.

## Phase 1: Setup

- [X] FX-002-T01 Audit the output pass: run the current `cmp_output` on NaN, ±Inf, negative, over-range and
  alpha edge values in `bgra8Unorm_srgb`, `rgba16Float` and `bgra8Unorm` with
  `Packages/Compositor/Tests/CompositorTests/OutputPassRig.swift`; record the table in spec.md's audit (log
  `.autonomous/logs-fx-002/audit.log`). — Verified 2026-11-14: audit.log (the old `cmp_output` through OutputPassRig): NaN → 0 and +Inf → 1 on the 8-bit screen, passed through unchanged in `rgba16Float`; table in spec.md.

## Phase 2: Foundational

- [X] FX-002-T02 Create `Packages/Compositor/Sources/Compositor/ToneMap.swift`: `ToneMap.Pixel`
  (`SIMD4<Double>`), `luminanceWeights` (0.2126, 0.7152, 0.0722), `sanitize` ("non-finite or negative colour
  channels → 0; alpha non-finite → 0, then clamped to 0…1"), `map` (contract C1 steps 1-4, typed steps),
  `isNonFinite`; plain Swift, builds on Linux. — Verified 2026-11-14: ToneMap.swift builds in the Linux shape and on the host; ToneMapReferenceTests 6/6.
- [X] FX-002-T03 Write `Packages/Compositor/Tests/CompositorTests/ToneMapReferenceTests.swift` (CPU): hand-checked
  values, identity for in-range pixels, special values, output luminance = min(Y, 1), ray monotonicity over a
  grid of hues and 0…64, 10,000 random colours in range and NaN-free (FX-002-S5, under 2 s). — Verified 2026-11-14: ToneMapReferenceTests 6/6 in the Linux shape (0.08 s; reference-linux-shape.log).
- [X] FX-002-T04 Add `cmp_tone_map` to `Packages/Compositor/Sources/Compositor/CompositorShaders.swift` as a
  Swift string constant (`toneMapSource`) spliced into `source`; `cmp_output` applies it before the gain and
  counts non-finite pixels into `device atomic_uint *` at buffer index 1 (research D4). — Verified 2026-11-14: testSpecialValuesThroughTheOutputPassMatchTheReference and testInRangeHalfFloatOutputIsBitIdentical pass (tonemap-gpu.log).

## Phase 3: User Story 1 - Bright layers look right, never broken (P1)

**Goal**: over-range, NaN and infinite values reach the screen in range, ordered and hue-kept. **Independent
test**: the reference gradient through the real output pass.

- [X] FX-002-T05 [US1] Bind a counter buffer (screen pass) and a sink buffer (recording, capture) at fragment
  buffer index 1 in `Packages/Compositor/Sources/Compositor/Compositor.swift` and
  `Packages/Compositor/Sources/Compositor/SceneTransitionBus.swift`; add `nonFiniteOutputPixels` to both. — Verified 2026-11-14: testNonFiniteCounterCountsTheScreenPassOnly: 64 for the screen pass of 64 NaN pixels, recording and capture not counted; bus 64.
- [X] FX-002-T06 [US1] `Packages/Compositor/Tests/CompositorTests/ToneMapOutputTests.swift`: special values
  through the real `cmp_output` (OutputPassRig) in `bgra8Unorm_srgb` and `rgba16Float` equal the reference. — Verified 2026-11-14: testSpecialValuesThroughTheOutputPassMatchTheReference (16 pixels, both formats, counter 5).
- [X] FX-002-T07 [US1] Same file: a `ValueLayer` (0…16, four hue rows, alpha 1, blitted from a shared buffer)
  through `Compositor.composite` into both formats: monotonic per channel along each row, no NaN, 0…1, matches
  the reference within one 8-bit step / 0.002 (FX-002-S1). — Verified 2026-11-14: testReferenceGradientIsOrderedInRangeAndNaNFree: ordered, NaN-free, 0…1 in both formats; worst difference 0.0022 (sRGB, limit 0.0039) and 0.00048 (half, limit 0.002). The first run found a one-ulp dip in the half output; fixed by the exact-max form (research D1).
- [X] FX-002-T08 [US1] Same file: the non-finite counter counts the NaN/Inf pixels of a frame once (screen pass
  only) and stays 0 for the gradient; the same for `SceneTransitionBus.nonFiniteOutputPixels` (FX-002-R7). — Verified 2026-11-14: testNonFiniteCounterCountsTheScreenPassOnly (NaN injected into a reused composite) and testOverflowingStackSaturatesToWhite (a real overflow saturates at 65504: counter 0, white).
- [X] FX-002-T09 [US1] Run the RenderGoldens suite: zero golden changes (FX-002-S2), and the Compositor suite. — Verified 2026-11-14: RenderGoldens 39/39 (26 s), no golden file changed (`git status` clean); Compositor 583 tests in 8 bundles (CompositorTests 396), 0 failures, 7 skipped (25 s).

## Phase 4: User Story 2 - Recordings and captures match the screen (P1)

- [X] FX-002-T10 [US2] Same file: one gradient frame shown into `bgra8Unorm_srgb`, `encodeOutput` into a
  `bgra8Unorm_srgb` recording target and `requestFrameCapture`; capture (sRGB-encoded) and recording equal the
  screen within one 8-bit step (FX-002-S4). — Verified 2026-11-14: testRecordingAndCaptureMatchTheScreenForAnOverRangeFrame: recording bytes equal the screen, capture within 0.0022 encoded.

## Phase 5: User Story 3 - The flash limiter judges what the viewer sees (P1)

- [X] FX-002-T11 [US3] Make `CompositeFlashGuard`'s sample read go through `cmp_tone_map` (spliced
  `CompositorShaders.toneMapSource`) in `Packages/Compositor/Sources/Compositor/CompositeFlashGuard.swift`;
  nothing else in the guard changes (ACC-012 coordination). — Verified 2026-11-14: testFlashLimiterMeasuresTheToneMappedFrame; CompositeFlashGuardTests and the golden strobe scene still pass.
- [X] FX-002-T12 [US3] Same test file: 1↔16 grey frames at 60 fps for 1 s keep `lastFlashGain` at 1 and the
  output white; 0↔16 lowers the gain below 1 and the output is gain × mapped value (FX-002-S3). — Verified 2026-11-14: testFlashLimiterMeasuresTheToneMappedFrame: 1↔16 minimum gain 1.0, 0↔16 minimum gain 0.095, shown = gain within 0.002.

## Phase 6: Polish

- [X] FX-002-T13 GPU timing (FX-002-S7): the output pass at 1920 × 1080 with the previous and the new
  `cmp_output` (the previous shader kept as a string constant in the test file only), 50 frames each, median GPU time printed and recorded in research.md (no threshold). — Verified 2026-11-14: testOutputPassGPUTimeIsRecorded: previous 0.037 ms, tone-mapped 0.070 ms median (Mac, 1920 × 1080, over-range composite; a second run 0.068 / 0.127 ms under load); recorded in research D7.
- [X] FX-002-T14 Linux shape: the reference tests with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL
  -DANALYSIS_NO_ACCELERATE`; regressions VisualGenerators, SceneFormat, ImportFuzz. — Verified 2026-11-14: Compositor in the Linux shape: 208 tests in 8 bundles pass (10 s); VisualGenerators 134 (34 s), SceneFormat 112 (18 s), ImportFuzz 16 (25 s) on the host.
- [X] FX-002-T15 App unit tests on an own simulator ("FX2 iPhone 17", iOS 27.2, `-only-testing:projectM-iOSTests`,
  derived data `.autonomous/derived-data-fx-002`); PosterBoard count before and after; delete the simulator. — Verified 2026-11-14: projectM-iOSTests 556/556, 0 failures (37.7 s of tests; app-unit-tests.log) on own simulator C3DDF6C0 (iOS 27.2), which exercises the compositor hosts (camera, photo, text, video) with the new shader on the simulator GPU; PosterBoard reports 25 → 25; simulator deleted.
- [X] FX-002-T16 `docs/adr/0047-output-tone-map.md` (next free number above the integration branch's highest and
  above 0045/0046 reserved for FILE-011 and ACC-012) and the compositor header notes in `Compositor.swift`. — Verified 2026-11-14: docs/adr/0047-output-tone-map.md and its README row; validate_docs OK; header notes in Compositor.swift and SceneTransitionBus.swift.
- [X] FX-002-T17 Checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
  `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`; remove the audit scratch test;
  `git diff` shows no new `makeRenderCommandEncoder`, `makeTexture` or per-frame `makeBuffer` in the frame path
  (FX-002-R9). — Verified 2026-11-14: the five check scripts OK, test_scripts 153 OK (1 skipped); AuditScratchTests removed; the source diff adds only the two 4-byte buffers at init (no pass, texture or per-frame buffer).
- [ ] FX-002-T18 {device} On D1, a scene with a glowing spectrum layer over a bright photo: no hue-shifted
  clipping or broken pixels; frame rate as before (FX-002-S6, last stage).

## Dependencies

T01 → T02 → T03; T04 → T05 → T06-T08, T10; T04 → T11 → T12; T09 after T05 and T11; T13-T17 after the stories.
US1, US2 and US3 share T04 and are otherwise independent.

## Parallel examples

T02/T03 (CPU) can run beside T04 (shader). T06, T07, T08, T10, T12 are in one file: sequential.

## Implementation strategy

MVP = Phase 2 + US1 (the acceptance). Then US3 (safety), US2, polish.
