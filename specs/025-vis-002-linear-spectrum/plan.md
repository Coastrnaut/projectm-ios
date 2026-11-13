# Implementation Plan: VIS-002 Linear Spectrum

**Branch**: `feature/vis-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/025-vis-002-linear-spectrum/spec.md`

## Summary

A second native visual on VIS-001's infrastructure (ADR-0009), with FX-001's glow (ADR-0010) and
FX-019's envelope (ADR-0011) applied unchanged. No new package, target or dependency; the shared
pieces of the circular spectrum are factored out rather than copied (research VIS-002-D1).

1. **Package `Packages/VisualGenerators`, target `VisualGenerators`** (extended):
   - New: `LinearSpectrumConfiguration` (orientation, spacing, length scale, cap thickness, hold,
     fall rate, palette, background; clamped), `PeakCapTracker` (per-bar peak and hold, frame-time
     driven, preallocated), `LinearSpectrumLayout` (bar and cap rectangles in pixels, tessellation
     into `SpectrumVertex`, 17-area levels), `LinearSpectrumGenerator` (Metal, behind
     `#if canImport(Metal) && !VISUAL_NO_METAL`).
   - Shared (refactor, behavior unchanged): `FlatShapePass` (the runtime-compiled flat-triangle
     pipeline, three vertex buffers, one clear-and-draw pass) used by both generators;
     `SpectrumFlashAreas` made generic over an internal `FlashRegionLayout` protocol (regions with an
     area, a color and convex pixel quads) that both layouts adopt; a public `FlashAreaLevelSource`
     protocol so `FlashSafetyLimiter.gain(for:transfer:frameTime:enabled:)` accepts either layout;
     a public `SpectrumTextureGenerator` protocol (limiter, downstream luminance, bar count) so the
     app host drives either generator.
   - `VisualBandFeed` and `VisualEffects` are not touched (ANL-016 works in `VisualBandFeed`).
2. **App** (`Apps/projectM-iOS`):
   - `AppSettings`: `VisualChoice.linearSpectrum`; `linearSpectrumOrientation` and
     `linearSpectrumSpacing` with keys `settings.linearSpectrum.orientation` /
     `settings.linearSpectrum.spacing`, added to `allKeys`; `VisualChoice.isNative`.
   - `Visuals/CircularSpectrumHost.swift` → `Visuals/NativeSpectrumHost.swift`: the same host, now
     holding `any SpectrumTextureGenerator` and a `NativeSpectrumStyle` (circular, or linear with
     orientation and spacing). Changing the style between kinds builds the other generator off the
     frame path (pipeline compile) and keeps the band analyzer, glow chain and lifecycle; a change of
     orientation or spacing only updates the configuration.
   - `AppCoordinator` (localized): the host is created for any native choice; the fallback notice
     names the chosen visual; `visualSettingsChanged` passes the style.
   - Views: `VisualizerView` labels the native view per visual (`circularSpectrum` /
     `linearSpectrum`, value "Vertical, Glow off"); `SettingsView` shows Bars and Glow for both and
     Orientation/Spacing for the linear spectrum; `ControlsOverlay` names the shown visual.
3. **Shared files, minimal edits**: `scripts/run_device_tests.py` (two allowed keys). `project.yml`,
   `.github/workflows/ios-ci.yml` and `scripts/test_scripts.py` need no change (the package and the
   app target already exist and CI already tests `VisualGenerators` in every shape).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency complete), Xcode 27.2

**Primary Dependencies**: Metal, QuartzCore, UIKit, SwiftUI (public); the existing `FlashSafety`,
`VisualEffects`, `VisualBandFeed`. No third-party dependency.

**Storage**: two new UserDefaults keys (user settings, FR-065 amended by VIS-002-R11).

**Testing**: XCTest. CPU tests run on the host, Linux shape (`-Xswiftc -DVISUAL_NO_METAL -Xswiftc
-DANALYSIS_NO_ACCELERATE`) and the iOS 27.2 simulator; GPU tests at 64 × 64 / 128 × 128 skip without
Metal; app unit tests; one UI test. Budgets (owner rule 7): each test about 1-2 s (≤ 10 s), the
package suite under 1 minute, the UI test under 30 s.

**Target Platform**: iOS/iPadOS 26+ (app), macOS 15 host for package tests, Linux for CPU parts.

**Project Type**: mobile app + Swift packages.

**Performance Goals**: no allocation per frame; at most 128 × 12 = 1,536 vertices per frame (vs
3,072 for the circular spectrum); area levels in one pass over at most 256 rectangles.

**Constraints**: Constitution I (public APIs), VI (modular boundaries: projectM isolated), VII
(no allocation, lock or I/O on the frame path), X (evidence; simulator is not device evidence).

**Scale/Scope**: one visual, two settings, ~600 lines of package code, ~150 lines of app changes.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Metal, QuartzCore, UIKit, SwiftUI; shader source compiled with `makeLibrary(source:)` as in VIS-001. `check_compliance.py` runs. |
| II-V Capture | Not affected: no capture or source change; no compatibility claim. |
| VI Modular boundaries | Pass: `VisualGenerators` stays app- and projectM-free; the app host is the only integration point. |
| VII Real-time safety | Pass: all per-frame storage allocated at init (layout, peak tracker, areas, vertex buffers). |
| VIII projectM fidelity | Pass: projectM is untouched and paused while a native visual shows. |
| IX Dependencies | Pass: none added. |
| X Evidence | Pass: test-first; simulator results are reported as simulator results; GPU device checks are `{device}`. |
| Privacy | Two user-setting keys, added to the device privacy check's allowed list; no network. |

Post-design re-check: unchanged (pass).

## Rollback

Every step is a separate commit on `feature/vis-002`. Reverting the app commits leaves the package
additions unused; reverting the refactor commit restores VIS-001's files byte for byte (the tests
that pin the refactor are VIS-001's, FX-001's and FX-019's, unchanged). The two new keys are
ignored by older builds; a stored `settings.visual = linearSpectrum` reads as projectM in a build
without this row (VIS-001-R11's unknown → projectM rule).

## Project Structure

### Documentation (this feature)

```text
specs/025-vis-002-linear-spectrum/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/linear-spectrum.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/VisualGenerators/Sources/VisualGenerators/
├── LinearSpectrumConfiguration.swift   (new)
├── PeakCapTracker.swift                (new)
├── LinearSpectrumLayout.swift          (new)
├── LinearSpectrumGenerator.swift       (new, Metal)
├── FlatShapePass.swift                 (new, Metal; shared pass from CircularSpectrumGenerator)
├── SpectrumTextureGenerator.swift      (new; shared protocols)
├── SpectrumFlashAreas.swift            (generic over FlashRegionLayout)
├── CircularSpectrumLayout.swift        (adopts FlashRegionLayout, FlashAreaLevelSource)
├── CircularSpectrumGenerator.swift     (uses FlatShapePass)
└── FlashSafetyLimiter.swift            (gain(for:) generic)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
├── LinearSpectrumLayoutTests.swift     (new: count, bounds, spacing, orientation)
├── PeakCapTrackerTests.swift           (new: hold/fall with an injected clock)
├── LinearSpectrumRenderTests.swift     (new: GPU, one reference per orientation)
└── LinearSpectrumFlashTests.swift      (new: FX-019 strobe through the linear spectrum)
Apps/projectM-iOS/
├── Visuals/NativeSpectrumHost.swift    (renamed from CircularSpectrumHost.swift)
├── Coordinators/AppSettings.swift, AppCoordinator.swift
├── Views/SettingsView.swift, VisualizerView.swift, ControlsOverlay.swift
├── Tests/SettingsTests.swift, NativeVisualTests.swift
└── UITests/LinearSpectrumUITests.swift (new)
scripts/run_device_tests.py             (two allowed keys)
```

**Structure Decision**: extend the existing package and app; no new targets.

## Complexity Tracking

None: no constitution violation.
