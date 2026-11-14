# Implementation Plan: ANL-003 Spectral Smoothing

**Branch**: `feature/anl-003` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/085-anl-003-spectral-smoothing/spec.md`

## Summary

A per-band one-pole attack/release follower (`BandSmoother`) in the analysis package, applied by
the native spectrum host once per display frame to the newest band vector before it is drawn. The
analysis pipeline, bus, onset detector and modulation inputs are untouched. Two user settings with
"Instant" defaults keep today's picture bit-identical. No new package, target or dependency.

1. **Package `Packages/AnalysisFeatures`** (pure Swift, builds on Linux and with
   `-DANALYSIS_NO_ACCELERATE`; no Accelerate needed for 128 scalar updates):
   - `BandSmoother.swift`: `SmoothingTimes` (attack, release seconds; clamped 0…2, NaN → 0) and
     `BandSmoother` (state for 128 bands allocated in `init`; `update(target:count:frameInterval:generation:)`
     returns the smoothed vector; `reset()`), contract C1.
   - Tests `BandSmootherTests.swift` (steps, frame rates, jitter, independence, instant, resets,
     non-finite input, no reallocation).
2. **Package `Packages/VisualGenerators`**, target `VisualBandFeed`: `LiveBandFrameInfo` gains
   `session` (the bus frame's capture-session generation, `frame.time.session`). Test
   `BandSmoothingPipelineTests.swift`: a synthetic 1 kHz tone switched on and off through
   `SpectrumBandFeed` (the real ANL-001/002 band path with the live settings) and the smoother at
   60 fps.
3. **App** (`Apps/projectM-iOS`):
   - `AppSettings`: `spectrumAttackMilliseconds`, `spectrumReleaseMilliseconds` with choices
     `[0, 25, 50, 100]` / `[0, 100, 250, 500]`, keys `settings.spectrum.attack` /
     `settings.spectrum.release`, in `allKeys`, and `spectrumSmoothing: SmoothingTimes`.
   - `NativeSpectrumHost`: owns a `BandSmoother`; `smoothing` property; per frame, after
     `readLatest`, `update` with the real display-link interval and the frame's session; the
     smoothed vector goes to the generator, the raw vector to `applyModulation`. `reset()` on
     resume and bar-count change (the band count change also snaps by rule).
   - `AppCoordinator`: sets `host.smoothing` at creation and in `visualSettingsChanged`.
   - `SettingsView`: Attack and Release segmented pickers next to Bars, only for the two spectra
     (identifiers `smoothingAttackPicker`, `smoothingReleasePicker`).
   - `VisualizerView`: two `onChange` lines.
   - Tests: `SpectralSmoothingAppTests.swift` (defaults, persistence, invalid → 0, mapping to
     `SmoothingTimes`) and UI test `SpectralSmoothingUITests.swift` (rows shown, persisted across
     relaunch, hidden for the oscilloscope).
4. **Shared**: `scripts/run_device_tests.py` gains the two keys in `ALLOWED_KEYS`. VIS-001-R9's
   wording is amended in spec 019 by a note. `project.yml` and CI need no change.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency complete), Xcode 27.2; CI also
builds with Xcode 26 and Linux Swift.

**Primary Dependencies**: Foundation (`exp`, `log`), existing AnalysisFeatures, VisualBandFeed,
SwiftUI/UIKit/QuartzCore in the app. No third-party dependency.

**Storage**: two Int UserDefaults keys (FR-065 amendment).

**Testing**: XCTest; `swift test` per package (host, and `-Xswiftc -DANALYSIS_NO_ACCELERATE` /
`-Xswiftc -DVISUAL_NO_METAL`); app unit and UI tests on a dedicated iOS 27.2 simulator
"ANL3 iPhone 17" (created and deleted for this row).

**Target Platform**: iOS/iPadOS 26.0+; packages also macOS 15 and Linux.

**Performance Goals**: two `exp` calls and 128 multiply-adds per display frame; zero allocations.

**Constraints**: owner rule 7 budgets (unit ≈1–2 s, suite < 1 min, UI test < 30 s); explicit
closure types and short typed arithmetic steps (Xcode 26 / Linux type-checker time-outs); no C
stdio globals; no wall-clock assertions.

**Scale/Scope**: ≤ 128 bands; one host.

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: Foundation math and SwiftUI only. |
| VI. Modular boundaries | Pass: the smoother is in the analysis package, independent of the app and Metal; the app wires it. |
| VII. Real-time audio safety | Pass: nothing runs on the audio callback; the frame update allocates and locks nothing. |
| VIII. Upstream projectM fidelity | Pass: nothing reaches projectM. |
| X. Evidence-based quality | Pass: acceptance by deterministic unit tests with injected intervals; simulator UI test for settings; no performance claims. |
| Privacy (FR-065) | Amended by exactly two user-setting keys, added to the device check's allowed list. |

Post-design re-check: unchanged, all pass. No ADR needed (no default overridden; the user opts in).

## Project Structure

```text
specs/085-anl-003-spectral-smoothing/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/band-smoother.md
└── checklists/requirements.md
Packages/AnalysisFeatures/Sources/AnalysisFeatures/BandSmoother.swift
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/BandSmootherTests.swift
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift          (session field)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/BandSmoothingPipelineTests.swift
Apps/projectM-iOS/Coordinators/AppSettings.swift, AppCoordinator.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Views/SettingsView.swift, VisualizerView.swift
Apps/projectM-iOS/Tests/SpectralSmoothingAppTests.swift
Apps/projectM-iOS/UITests/SpectralSmoothingUITests.swift
scripts/run_device_tests.py
```

**Structure Decision**: existing packages and app; no new target.

## Complexity Tracking

None.
