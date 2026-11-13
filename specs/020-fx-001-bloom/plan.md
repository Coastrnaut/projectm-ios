# Implementation Plan: FX-001 Bloom

**Branch**: `feature/fx-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/020-fx-001-bloom/spec.md`

## Summary

The first post-processing effect and the effect infrastructure later FX and CMP rows build on
(ADR-0010, new).

1. **New target `VisualEffects` in `Packages/VisualGenerators`** (research FX-001-D1), added to the
   package's one library product; depends only on the `VisualGenerators` target.
   - CPU (all platforms): `BloomParameters` (ranges, clamping, the threshold formula),
     `BloomPlan` (downsample D, blur radius R, normalized weights, halo extent E for a size),
     `BloomLuminanceModel` (a `FrameLuminanceTransfer`), `EffectIdentifier`, `EffectDescription`,
     `EffectChainDescription` (versioned Codable, FX-020).
   - Metal (`#if canImport(Metal) && !VISUAL_NO_METAL`): `PostProcessEffect`, `EffectChain`,
     `BloomEffect` (three compute passes + one render pass; shader source a Swift constant compiled
     at runtime, ADR-0009 decision 3). Contract: [contracts/post-process-effect.md](contracts/post-process-effect.md).
2. **Deltas in target `VisualGenerators`** (FX-001-R10, research FX-001-D4):
   - `FrameLuminanceTransfer` protocol.
   - `CircularSpectrumLayout.meanLuminance(gain:transfer:)`: per-bar flat-color luminance through a
     transfer.
   - `FlashSafetyLimiter.gain(frameTime:enabled:luminanceAtGain:)`: largest gain within the rise
     bound by 24 bisection steps; the existing `gain(barsLuminance:…)` is unchanged.
   - `CircularSpectrumGenerator.downstreamLuminance: (any FrameLuminanceTransfer)?`; nil keeps the
     VIS-001 path bit for bit.
3. **App** (`Apps/projectM-iOS`):
   - `AppSettings`: `glowEnabled`, `glowIntensity`, `glowRadius`, `glowThreshold` with four keys
     (data-model.md), `glowParameters`; added to `allKeys`.
   - `CircularSpectrumHost`: builds a `BloomEffect` and an `EffectChain` at creation (failure →
     `glowUnavailable`, DEBUG `-uitestGlowFailure`); `glow: BloomParameters` (sets the effect's
     parameters and the generator's `downstreamLuminance`); per frame `chain.prepare(size)` (no-op
     unless resized) and `chain.encode(output: drawable.texture, …) { generator.encode(into: $0, …) }`;
     the view's accessibility value names the glow state.
   - `AppCoordinator` (localized): passes `settings.glowParameters` to the host on creation and on
     change (`glowSettingsChanged()`); `glowUnavailable`; announces the failure when Glow is turned
     on.
   - `SettingsView`: "Glow" toggle and three sliders in the Visual section for Circular Spectrum;
     unavailable footer. `VisualizerView`: `onChange` for the four settings.
4. **Shared files**: `scripts/run_device_tests.py` (four allowed keys). No change to `project.yml`,
   `.github/workflows/ios-ci.yml` or `scripts/test_scripts.py` (the package's product and test
   target are unchanged in name).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency complete), Xcode 27.2

**Primary Dependencies**: Metal, QuartzCore, UIKit, SwiftUI (public). No third-party dependency.

**Storage**: four UserDefaults keys (user settings, FR-065).

**Testing**: XCTest; `swift test` on the Mac host (Metal available) and with `-DVISUAL_NO_METAL`;
`xcodebuild test` on the iOS 27.2 simulator; app unit and UI tests on the simulator. Linux CI builds
the package with Metal compiled out.

**Target Platform**: iOS/iPadOS 26.0+ (app), macOS 15+ (package host tests), Linux (CPU tests).

**Project Type**: mobile app + Swift packages.

**Performance Goals**: bounded GPU cost per frame: one full-resolution read and write for the
threshold, two blurs of at most 33 taps at 1/D² of the pixels, one full-resolution composite; device
frame rates are `{device}` checks (final phase).

**Constraints**: no per-frame allocation; deterministic output; projectM untouched; no networking.

**Scale/Scope**: one effect, one chain, one host integration, four settings.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Metal compute and render passes, `makeLibrary(source:options:)`, `setBytes`, blits | Pass |
| II–III Capture | Not touched | Pass (n/a) |
| IV Truthful labeling | The unavailable notice says exactly what is shown | Pass |
| V No universal claims | No compatibility text | Pass |
| VI Modular boundaries | Effects know nothing of generators, projectM or the app; the generator knows only the luminance protocol; the app wires them | Pass |
| VII Real-time safety | Audio untouched; frame path allocation- and lock-free (intermediates only on resize) | Pass |
| VIII ProjectM fidelity | projectM frames are not post-processed (needs CMP-001) | Pass |
| IX Dependencies | None added | Pass |
| X Evidence | Host and simulator GPU tests reported as such, skipped where no GPU; device GPU checks are `{device}` | Pass |
| Privacy | Four user-setting keys (FX-001-R11 amends FR-065's list as VIS-001-R11 did; allowed list updated); nothing leaves the device | Pass with a recorded amendment |
| Accessibility (FR-070, FR-072) | Labeled toggle and sliders with values; Reduce flashing bound holds on the composited frame | Pass |

Post-design re-check: unchanged, all pass. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/020-fx-001-bloom/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── checklists/requirements.md
└── contracts/post-process-effect.md
docs/adr/0010-post-processing-effects.md
```

### Source Code (repository root)

```text
Packages/VisualGenerators/
  Package.swift                                   (+ target VisualEffects in the product; tests depend on it)
  Sources/VisualGenerators/
    FrameLuminanceTransfer.swift                  (new: protocol + identity)
    CircularSpectrumLayout.swift                  (+ meanLuminance(gain:transfer:))
    FlashSafetyLimiter.swift                      (+ gain(frameTime:enabled:luminanceAtGain:))
    CircularSpectrumGenerator.swift               (+ downstreamLuminance)
  Sources/VisualEffects/
    BloomParameters.swift  BloomPlan.swift  BloomLuminanceModel.swift  EffectChainDescription.swift
    PostProcessEffect.swift  EffectChain.swift  BloomEffect.swift   (Metal)
  Tests/VisualGeneratorsTests/
    BloomParametersTests  BloomPlanTests  BloomLuminanceModelTests  EffectChainDescriptionTests
    GlowFlashSafetyTests (CPU model)  FlashSafetyLimiterTests (+ bisection)
    BloomRenderTests  EffectChainRenderTests  BloomFlashSafetyRenderTests   (Metal, XCTSkip)
    RenderTestSupport.swift (offscreen textures, read-back, synthetic inputs)
Apps/projectM-iOS/
  Visuals/CircularSpectrumHost.swift   Coordinators/AppSettings.swift, AppCoordinator.swift
  Views/SettingsView.swift, VisualizerView.swift
  Tests/SettingsTests.swift (+ glow keys), Tests/NativeVisualTests.swift (+ host glow)
  UITests/GlowUITests.swift (new)
scripts/run_device_tests.py  (+ four allowed keys)
```

**Structure Decision**: a new target in the existing package (research FX-001-D1); CMP-001 may move
it into `Packages/Compositor`.

## Test design (deterministic)

- **Synthetic inputs** (`RenderTestSupport`): textures uploaded with `replace(region:)` from Float
  arrays (rgba16Float via `Float16`, bgra8Unorm_srgb via sRGB-encoded bytes), sizes 96×64 to 256×256,
  patches aligned and unaligned to D.
- **Black**: all-black input at the parameter corners {intensity 0.01, 1} × {radius 0.005, 0.06} ×
  {threshold 0.1, 1} × {knee 0, 1} and both formats: every output byte is 0.
- **Bright patch**: a white (and a colored) 12×12 patch on black: pixel next to each edge > 0;
  every pixel at Chebyshev distance ≥ E is exactly 0; no pixel outside the patch exceeds the patch
  per channel (+1 half-float ulp); along the patch's centre row and column moving outward values do
  not increase (tolerance 1e-3); Σ(out − in) ≤ k·Σ P(in) + 1e-3·pixels.
- **Below threshold**: a 0.3-brightness patch at T = 0.7, K = 0.35: output equals input (≤ 1/255
  on `bgra8Unorm_srgb`, exact on `rgba16Float`).
- **Gradient**: horizontal 0…1 ramp: output ≥ input − 1e-3, finite, unchanged (as above) farther than
  E from every pixel above T − K.
- **Identity and determinism**: intensity 0 / disabled → byte-equal; two runs → byte-equal.
- **Chain**: no active effect → the source drew into the output itself (pointer identity); one
  effect → output equals a direct effect encode; resize reallocates exactly once per new size.
- **Reduce flashing** (CPU, every host): generator layout + `BloomLuminanceModel` (k = 1, T = 0.1)
  with alternating 0/1 bands for 600 frames at frame times 1/120…0.2 s: modeled final luminance
  rises ≤ 0.25·min(dt, 0.1) + 1e-9. (GPU): generator (`rgba16Float`, ring within 0.7 radius units
  so the halo stays in frame) → chain → offscreen, 120 alternating frames at 1/60 s, mean measured
  luminance rises ≤ 0.25·dt + 0.002.
- Skips: `XCTSkip` when `MTLCreateSystemDefaultDevice()` is nil or the pipeline cannot be built
  (reported with the reason), never a failure for environment reasons. No wall-clock assertions; GPU
  waits are `waitUntilCompleted` on test command buffers.
- Red run first: tests written against missing symbols fail to compile (recorded in tasks.md).

## Persistence and rollback

- Persistence: the four keys of data-model.md; absent keys are today's state (Glow off), so no
  migration. Cleared with the other settings by `-uitestResetNotice`.
- Runtime rollback: if the bloom cannot be built, the circular spectrum renders without it
  (FX-001-R13); turning Glow off returns to VIS-001's direct drawing.
- Code rollback: revert the feature's commits; stored glow keys are then ignored (unknown keys are
  harmless) and the VIS-001 limiter path is untouched by the nil default.

## Complexity Tracking

None.
