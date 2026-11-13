# Tasks: FX-001 Bloom

**Input**: Design documents in `specs/020-fx-001-bloom/` (spec.md, plan.md, research.md,
data-model.md, contracts/post-process-effect.md, quickstart.md), ADR-0010.

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the iOS 27.2 simulator "iPhone Air" (udid
`77E17861-E687-4274-8A84-14224F32BE3E`).

A task is ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>"
appended. Inside descriptions, "T07" is short for `FX-001-T07`. Logs go to `.build/scratch/`. Paths
below are relative to `Packages/VisualGenerators/` unless they start with `Apps/`, `scripts/`,
`docs/` or `specs/`. Story phases follow dependency order (US2 builds the effect US1 and US3 need);
story labels keep the spec's numbering.

## Phase 1: Setup

- [X] FX-001-T01 Confirm the baseline before any change: `swift test` for `Packages/VisualGenerators` on the host, with and without `-Xswiftc -DVISUAL_NO_METAL`; `python3 scripts/check_compliance.py`, `scripts/validate_docs.py`, `scripts/test_scripts.py`; record the counts here. — Verified 2026-11-13: at 8580d23 (worktree base), host `swift test` VisualGenerators 40 tests, 0 failures (3.0 s); with `-DVISUAL_NO_METAL` 37 tests, 0 failures; check_compliance OK; validate_docs OK (214 files); test_scripts.py 98 tests OK (1 skipped) (.build/scratch/fx001-T01-*.log).
- [X] FX-001-T02 Add target `VisualEffects` (dependency: `VisualGenerators`) to `Package.swift`, include it in the `VisualGenerators` library product, add it to `VisualGeneratorsTests`' dependencies; placeholder source `Sources/VisualEffects/BloomParameters.swift`. Evidence: `swift build` succeeds; `xcodebuild -list` still shows exactly one scheme, `VisualGenerators` (CI's `-scheme "$pkg"`). — Verified 2026-11-13: `swift build` succeeded with the placeholder; `xcodebuild -list` in the package lists exactly one scheme, `VisualGenerators`.

## Phase 2: Foundational (parameters, plan, luminance hook; blocks every story)

- [X] FX-001-T03 [P] Write `Tests/VisualGeneratorsTests/BloomParametersTests.swift`: defaults (enabled false, intensity 0.5, radius 0.02, threshold 0.7, knee 0.5); clamping "intensity 0…1", "radius 0.005…0.06", "threshold 0.1…1", "knee 0…1", NaN → default, ±∞ → bound; `isPassThrough` for disabled or intensity 0; the threshold contribution: 0 for every brightness ≤ T − K (sampled), exactly `b − T` over `b` above T + K, continuous and nondecreasing across the knee, 0 ≤ w ≤ 1; `thresholded(c)` ≤ c per channel; black → 0; NaN/∞ components → 0. — Verified 2026-11-13: written before the production files; red run in T07; BloomParametersTests 6 tests pass after T08.
- [X] FX-001-T04 [P] Write `Tests/VisualGeneratorsTests/BloomPlanTests.swift`: D is the smallest of {2, 4, 8} with ⌈ρ·min(W,H)/D⌉ ≤ 16, R = clamp(round(ρ·min/D), 1, 16); reduced size ⌈W/D⌉ × ⌈H/D⌉; weights: R + 1 values, w0 + 2·Σ = 1 within 1e-6, strictly decreasing, all > 0; halo extent (R + 2)·D; table for 1179×2556, 2064×2752, 256×256, 1×1 at radius 0.005, 0.02, 0.06; equal inputs give equal plans. — Verified 2026-11-13: written before the production files; red run in T07; BloomPlanTests 4 tests pass after T08.
- [X] FX-001-T05 [P] Write `Tests/VisualGeneratorsTests/BloomLuminanceModelTests.swift` and extend `FlashSafetyLimiterTests.swift`: the model is `Y(c)` when pass-through and `Y(c) + k·Y(P(c))` otherwise, nondecreasing in a uniform scale of c; `CircularSpectrumLayout.meanLuminance(gain:transfer:)` with the identity transfer equals `meanRelativeLuminance(gain:)` within 1e-6 (Float colors) for every palette and bar count; `gain(frameTime:enabled:luminanceAtGain:)`: disabled → 1; first frame → 1; a linear model reproduces the closed-form gain of `gain(barsLuminance:…)` within 1e-6; the recorded luminance never exceeds the ceiling; background above the ceiling → 0. — Verified 2026-11-13: written before the production files; red run in T07; BloomLuminanceModelTests 4 tests pass after T08.
- [X] FX-001-T06 [P] Write `Tests/VisualGeneratorsTests/EffectChainDescriptionTests.swift`: round trip of a one-bloom chain through JSON equals the original; the JSON contains `"formatVersion":1` and `"id":"fx.bloom"`; decoding clamps out-of-range parameters; an unknown id decodes as `.unknown` and is excluded from `activeEffects`; `formatVersion` 2 and 17 effects fail decoding; disabled bloom is not active. — Verified 2026-11-13: written before the production files; red run in T07; EffectChainDescriptionTests 4 tests pass after T08.
- [X] FX-001-T07 Record the red run of T03-T06 (`swift build --build-tests` fails on missing symbols) in `.build/scratch/fx001-red-T03-T06.log`. — Verified 2026-11-13: `swift build --build-tests` failed with `cannot find 'EffectChainDescription' in scope` and `cannot find 'BloomParameters' in scope` (.build/scratch/fx001-red-T03-T06.log).
- [X] FX-001-T08 Implement `Sources/VisualEffects/BloomParameters.swift`, `BloomPlan.swift`, `BloomLuminanceModel.swift`, `EffectChainDescription.swift`; `Sources/VisualGenerators/FrameLuminanceTransfer.swift`; `CircularSpectrumLayout.meanLuminance(gain:transfer:)`; `FlashSafetyLimiter.gain(frameTime:enabled:luminanceAtGain:)` (24 bisection steps, no allocation). Evidence: T03-T06 pass on the host and with `-DVISUAL_NO_METAL`; every VIS-001 test still passes. — Verified 2026-11-13: host `swift test` 58 tests (40 VIS-001 + 18 new), 0 failures; `-DVISUAL_NO_METAL` 55 tests, 0 failures (.build/scratch/fx001-T08-*.log). First run found a real boundary bug (b = T − K gave 4.6e-16, not 0); fixed by computing b − (T − K).

## Phase 3: User Story 2 - black stays black, the halo is bounded (P1)

**Goal**: the roadmap acceptance. **Independent test**: `BloomRenderTests`, `EffectChainRenderTests`.

- [X] FX-001-T09 [US2] Write `Tests/VisualGeneratorsTests/RenderTestSupport.swift` (Metal: device or `XCTSkip`, offscreen textures in both formats from Float arrays, read-back to Float arrays, synthetic inputs: black, patch, gradient) and `BloomRenderTests.swift`: (a) all-black input at the 16 parameter corners {intensity 0.01, 1} × {radius 0.005, 0.06} × {threshold 0.1, 1} × {knee 0, 1}, both formats: every output component is exactly 0; (b) a white 12×12 patch (aligned and unaligned to D) and a colored patch on black, rgba16Float: the pixel next to each patch edge > 0; every pixel at Chebyshev distance ≥ E is exactly 0; no pixel outside the patch exceeds the patch per channel (+1e-3); centre row and column do not increase moving outward (tolerance 1e-3); Σ(out − in) ≤ k·Σ P(in) + 1e-3 per pixel; (c) a 0.3-brightness patch at T 0.7, K 0.35: output equals input exactly (rgba16Float) and within 1/255 (bgra8Unorm_srgb); (d) a 0…1 horizontal ramp: output ≥ input − 1e-3, finite, and unchanged farther than E from every pixel above T − K; (e) intensity 0 and disabled: byte-equal to the input in both formats; (f) two runs byte-equal; (g) an unsupported pixel format throws; mismatched sizes return false. Print one `FX-001 halo:` line per case (D, R, E, max halo, farthest non-zero distance). — Verified 2026-11-13: written before BloomEffect; red run in T11; 7 BloomRenderTests pass on the host GPU after T12 (black at 16 corners × 2 formats × 2 fills; 12 patch cases from D = 2 to D = 8: farthest non-zero pixel 3…75 px, always < E = 6…80 px, added energy ≤ bound; below-threshold exact; ramp; identity; determinism). First run caught a test bug (the ramp was compared with the unrounded input instead of the half-float texture contents), fixed in the test.
- [X] FX-001-T10 [US2] Write `Tests/VisualGeneratorsTests/EffectChainRenderTests.swift` (FX-001-R2, R12, R14, S7): no active effect → the source receives the output texture itself and nothing else is encoded; one bloom → output byte-equal to a direct `BloomEffect.encode` of the same source image; resizing reallocates once per new size and the next frame is correct at the new size; a disabled effect between two calls toggles direct drawing; changing `BloomEffect.parameters` between frames needs no new `prepare` (no texture recreated, R12). — Verified 2026-11-13: written before EffectChain; red run in T11; 5 EffectChainRenderTests pass on the host GPU after T12.
- [X] FX-001-T11 [US2] Record the red run of T09-T10 in `.build/scratch/fx001-red-T09-T10.log`. — Verified 2026-11-13: `swift build --build-tests` failed with `cannot find 'BloomEffect' in scope` and `cannot find 'EffectChain' in scope` (.build/scratch/fx001-red-T09-T10.log).
- [X] FX-001-T12 [US2] Implement `Sources/VisualEffects/PostProcessEffect.swift` (protocol per contracts/post-process-effect.md), `BloomEffect.swift` (shader constant: threshold+downsample, horizontal and vertical blur compute kernels, composite and copy render passes; `setBytes` uniforms; private `rgba16Float` working textures created in `prepare` only on size change), `EffectChain.swift`. Evidence: T09-T10 pass on the host GPU; halo table saved to `.build/scratch/fx001-halo.txt`. — Verified 2026-11-13: host `swift test` 70 tests, 0 failures, 0 skipped (6.7 s) on the Mac Studio GPU; `-DVISUAL_NO_METAL` 55 tests, 0 failures; halo table in .build/scratch/fx001-halo.txt (.build/scratch/fx001-T12-*.log).
- [X] FX-001-T13 [US2] {sim} Run the package on the simulator (`xcodebuild test -scheme VisualGenerators`, quickstart §2). Evidence: `** TEST SUCCEEDED **`, GPU tests run or are reported skipped with the reason. — Verified 2026-11-13: `xcodebuild test -scheme VisualGenerators` on iPhone Air iOS 27.2 (77E17861…): 70 tests, 0 failures, no test skipped (the simulator has a Metal device), `** TEST SUCCEEDED **` (.build/scratch/fx001-T13-sim.log). Simulator results are not device evidence.

## Phase 4: User Story 3 - Reduce flashing holds with the glow on (P1)

**Goal**: FX-001-R10. **Independent test**: `GlowFlashSafetyTests`, `BloomFlashSafetyRenderTests`.

- [X] FX-001-T14 [US3] Write `Tests/VisualGeneratorsTests/GlowFlashSafetyTests.swift` (CPU, every host): a layout plus `BloomLuminanceModel` (k = 1, T = 0.1) and the limiter, alternating 0/1 bands for 600 frames at frame times {1/120, 1/60, 1/30, 0.2}, every palette: modeled final luminance rises ≤ 0.25·min(dt, 0.1) + 1e-8 each frame (Float rounding of the VIS-001 path's gain); turning the model on mid-run (glow switched on) obeys the same bound; with Reduce flashing off the gain is 1. And `BloomFlashSafetyRenderTests.swift` (Metal): `CircularSpectrumGenerator` (rgba16Float, 64 bars, innerRadius 0.3, lengthScale 0.4, `downstreamLuminance` set) → `EffectChain` with bloom (intensity 1, radius 0.06, threshold 0.1) → 256×256 offscreen, 120 alternating frames at 1/60 s, Reduce flashing on: measured mean relative luminance rises ≤ 0.25/60 + 0.002 per frame; print the largest rise. — Verified 2026-11-13: written before the generator change; red run in T15; GlowFlashSafetyTests 4 pass (every palette and frame time: worst rise exactly 1.000 of the bound, peak composited luminance 0.23 spectrum / 0.31 ice / 0.45 mono); BloomFlashSafetyRenderTests 1 passes on the host GPU (Apple M5 Max): measured worst rise 0.00253 per frame against the bound 0.00417 (+0.002 allowance unused), peak 0.476, measured never above the model. First run: 3 cases exceeded by 1e-7 of the bound at the switch frame, from the VIS-001 path's Float rounding of its gain; the test's absolute tolerance went from 1e-9 to 1e-8.
- [X] FX-001-T15 [US3] Record the red run of T14 (missing `downstreamLuminance`) in `.build/scratch/fx001-red-T14.log`. — Verified 2026-11-13: `swift build --build-tests` failed with `missing argument for parameter 'luminanceAtGain' in call` for `limiter.gain(for:transfer:…)` (.build/scratch/fx001-red-T14.log).
- [X] FX-001-T16 [US3] Add `downstreamLuminance: (any FrameLuminanceTransfer)?` to `Sources/VisualGenerators/CircularSpectrumGenerator.swift` (nil keeps the VIS-001 path) using `meanLuminance(gain:transfer:)` and the bisection gain. Evidence: T14 passes on the host (CPU and GPU) and with `-DVISUAL_NO_METAL` (CPU); VIS-001's tests unchanged and passing. — Verified 2026-11-13: host `swift test` 75 tests, 0 failures (10.1 s); `-DVISUAL_NO_METAL` 59 tests, 0 failures; the 40 VIS-001 tests unchanged and passing (.build/scratch/fx001-T16-*.log).

## Phase 5: User Story 1 - turn on a glow in Settings (P1)

**Goal**: the observable behavior. **Independent test**: `SettingsTests`, `NativeVisualTests`, `GlowUITests`.

- [ ] FX-001-T17 [US1] Write app unit tests in `Apps/projectM-iOS/Tests/SettingsTests.swift`: glow defaults (off, 0.5, 0.02, 0.7) with empty defaults; values persist through a new `AppSettings` on the same suite; out-of-range and NaN stored values clamp / fall back; `allKeys` contains the four keys `settings.circularSpectrum.glow`, `settings.circularSpectrum.glowIntensity`, `settings.circularSpectrum.glowRadius`, `settings.circularSpectrum.glowThreshold`; `glowParameters` maps them. And in `Apps/projectM-iOS/Tests/NativeVisualTests.swift`: a host made with a device applies glow parameters (glow state on/off, accessibility value "Glow on"/"Glow off"), and a host made with the glow forced to fail renders (is created) with `glowUnavailable` and value "Glow unavailable".
- [ ] FX-001-T18 [US1] Write `Apps/projectM-iOS/UITests/GlowUITests.swift` {sim}: Glow toggle (`glowToggle`) exists only for Circular Spectrum and is off by default; turning it on shows `glowIntensitySlider`, `glowRadiusSlider`, `glowThresholdSlider` (labels "Intensity", "Radius", "Threshold", each with a percentage value for VoiceOver; FR-070) and the circular spectrum's value becomes "Glow on"; adjusting a slider, relaunching: toggle on and slider value kept; `sourceStarts` stays 1; with `-uitestGlowFailure` the circular spectrum stays on screen, its value is "Glow unavailable" and `glowUnavailableFooter` is shown.
- [ ] FX-001-T19 [US1] Record the red run of T17-T18 (app build fails on missing symbols) in `.build/scratch/fx001-red-T17-T18.log`.
- [ ] FX-001-T20 [US1] Implement: `Apps/projectM-iOS/Coordinators/AppSettings.swift` (four settings, keys, `glowParameters`); `Apps/projectM-iOS/Visuals/CircularSpectrumHost.swift` (bloom + chain at creation, failure → `glowUnavailable`, `glow` setter updating the effect and `generator.downstreamLuminance`, chain in the frame path, accessibility value); `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (pass parameters on creation and change, `glowUnavailable`, announcement, DEBUG `-uitestGlowFailure`); `Apps/projectM-iOS/Views/SettingsView.swift` (toggle, sliders with labels and values, footer); `Apps/projectM-iOS/Views/VisualizerView.swift` (`onChange`). Evidence: T17 and T18 pass {sim}.
- [ ] FX-001-T21 [US1] Add the four keys to the allowed UserDefaults list in `scripts/run_device_tests.py`. Evidence: `python3 scripts/test_scripts.py` passes.

## Phase 6: User Story 4 - never black when the glow fails (P2)

- [ ] FX-001-T22 [US4] Confirm the failure path end to end: T17's forced-failure host test and T18's `-uitestGlowFailure` UI test pass; the announcement text is "Glow isn't available on this device." (FX-001-R13). Evidence: the two tests' results in the T20 logs.

## Phase 7: Polish and cross-cutting

- [ ] FX-001-T23 {sim} Regression: all app unit tests, `NativeVisualUITests`, `SettingsUITests`, `VisualizerUITests`, `GlowUITests` on the simulator (known environmental failure: `PresetTests.testBundledIncludedScopeMatchesRelease1_0`). Evidence: counts and log path.
- [ ] FX-001-T24 {sim} Screenshot of the circular spectrum with Glow on and the reference track to `.build/scratch/fx-001-bloom.png` (not evidence of device behavior).
- [ ] FX-001-T25 `python3 scripts/check_compliance.py`, `scripts/validate_docs.py`, `scripts/test_scripts.py`; count new `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` since the start of the run (owner rule 5); record test runtimes.
- [ ] FX-001-T26 Record the evidence summary (commands, counts, runtimes, skips, PosterBoard count, open tasks) in this file's "Evidence summary" section; update `specs/020-fx-001-bloom/quickstart.md` if a command changed. (`docs/FEATURE_ROADMAP_AUTONOMOUS.md` and its status belong to the main session's integration.)
- [ ] FX-001-T27 {device} On D1, D2, D3 with the reference track: frame rate with Glow off vs on at default and maximum radius (performance overlay), appearance after rotation, Reduce flashing on. Final device phase only; not run in this row.

## Dependencies

- T01 → T02 → T03-T06 (parallel) → T07 → T08 → US2 (T09-T13) → US3 (T14-T16) → US1 (T17-T21) → US4 (T22) → Polish.
- US1 needs the effect (US2) and the limiter hook (US3); US4 uses US1's host and settings.

## Parallel examples

- T03, T04, T05, T06 are separate test files.
- T09 and T10 are separate test files once T08 is done.
- T17 and T18 (unit vs UI tests) in parallel.

## Implementation strategy

MVP = Phases 1-4 (a correct, bounded, Reduce-flashing-safe bloom in the package, tested on host and
simulator), then the app integration (US1, US4). Commit after each phase; the last commit on the
branch carries code and no `[skip ci]`.

## Evidence summary

(Filled during `/speckit-implement`.)
