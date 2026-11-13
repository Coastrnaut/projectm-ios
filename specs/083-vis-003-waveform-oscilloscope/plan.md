# Implementation Plan: VIS-003 Waveform Oscilloscope

**Branch**: `feature/vis-003` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/083-vis-003-waveform-oscilloscope/spec.md`

## Summary

A third native visual on VIS-001/VIS-002's infrastructure (ADR-0009), with FX-001's glow
(ADR-0010) and FX-019's envelope (ADR-0011) applied unchanged, plus the smallest sample path to the
frame loop and a pure-Swift trigger stabilizer. No new package, target or dependency.

1. **Package `Packages/VisualGenerators`**:
   - Target `VisualGenerators` (pure Swift parts build on Linux):
     - `WaveformTrigger` — the stabilizer (research VIS-003-D2): midpoint level, hysteresis, fractional
       rising crossings, interval spread test, 64-point match against the previous window, free-run.
       All storage (crossings, scores, reference) allocated in `init`.
     - `WaveformFrameBuffer` — wait-free triple buffer of 4,096-sample histories (as
       `BandFrameBuffer`, which stays as is).
     - `OscilloscopeConfiguration` (window, thickness, amplitude, palette, background; clamped) and
       `OscilloscopeLayout` (trigger → resampled points → segment quads in pixels → tessellation into
       `SpectrumVertex`; `FlashRegionLayout` with one region per segment; 17-area levels through
       `SpectrumFlashAreas`).
     - `OscilloscopeGenerator` (Metal, behind `#if canImport(Metal) && !VISUAL_NO_METAL`):
       `SpectrumTextureGenerator` over `FlatShapePass`; its input vector is the sample history.
   - Target `VisualBandFeed`: `WaveformTap` — the pass-through `NormalizedPCMReader` +
     `AnalysisSessionReporting` wrapper that folds each read into the mono history and publishes it
     (research VIS-003-D1).
   - The two existing protocol docs (`TextureGenerator`, `SpectrumTextureGenerator`) gain one
     sentence: the input vector is the visual's input (bands for the spectra, samples for the
     oscilloscope). No signature changes.
2. **Package `Packages/RenderGoldens`** (tests only, plus a golden folder): `GeneratorGoldens/<class>/`
   with a manifest, a test that renders the sine fixture through `OscilloscopeGenerator` and decides
   with QA-002's `GoldenComparison`/`GoldenDecision`/`GoldenStore`, and an integrity test with
   `GoldenIntegrity.check(goldensRoot:runs:)` on the generator catalog (research VIS-003-D4).
3. **App** (`Apps/projectM-iOS`):
   - `AppSettings`: `VisualChoice.oscilloscope` (title "Oscilloscope", `isNative`), enum
     `OscilloscopeLine` (thin/medium/thick), `oscilloscopeLine` and `oscilloscopeWindowMilliseconds`
     with keys `settings.oscilloscope.line` / `settings.oscilloscope.window`, in `allKeys`.
   - `NativeSpectrumHost`: style `.oscilloscope(line:windowMilliseconds:)`; the host wraps its reader
     in a `WaveformTap` (always; the analyzer reads through it) and, for the oscilloscope, copies the
     newest history into a preallocated 4,096-float scratch and passes it to the generator instead of
     the bands; modulation still advances with the bands. Accessibility: label "Oscilloscope
     visualization", identifier `oscilloscope`, value "20 ms, Glow off".
   - `AppCoordinator`: `nativeSpectrumStyle` maps the choice; `SettingsView`: Line and Window pickers
     (identifiers `oscilloscopeLinePicker`, `oscilloscopeWindowPicker`), Bars hidden for the
     oscilloscope; `VisualizerView`: two `onChange` lines.
   - `ShowSceneSnapshot`, `SceneAutosaveCapture`: `case .oscilloscope` records no layer (as projectM).
   - `GuidedFirstScene` is not changed (its own enum of offered visuals).
4. **Shared files, minimal edits**: `scripts/run_device_tests.py` (two allowed keys). `project.yml`
   and CI need no change (the packages and the app exist; CI already tests both packages in every
   shape). A new UI test file is picked up by the UITests target's source folder.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency complete), Xcode 27.2

**Primary Dependencies**: Metal, QuartzCore, UIKit, SwiftUI (public); existing `FlashSafety`,
`VisualEffects`, `VisualBandFeed`, `AudioCore`, `GoldenImages`. No third-party dependency.

**Storage**: two new UserDefaults keys (user settings, FR-065 amended by VIS-003-R10).

**Testing**: XCTest. CPU tests on the host, the Linux shape (`-Xswiftc -DVISUAL_NO_METAL -Xswiftc
-DANALYSIS_NO_ACCELERATE`, plus `-DCOMPOSITOR_NO_METAL` for RenderGoldens) and the iOS 27.2
simulator; GPU tests skip without Metal; app unit tests; one UI test. Budgets (owner rule 7): each
test about 1-2 s (≤ 10 s), each package suite under 1 minute, the UI test under 30 s.

**Target Platform**: iOS/iPadOS 26+ (app), macOS 15 host for package tests, Linux for CPU parts.

**Project Type**: mobile app + Swift packages.

**Performance Goals**: per frame, the trigger scans ≤ 4,096 samples once and scores ≤ 32 candidates
at 64 points; layout and tessellation of ≤ 1,023 segments; the flash area model over ≤ 1,023 quads
(mostly inside one tile). Frame time on devices is `{device}` (VIS-003-T17).

**Constraints**: no allocation, lock or I/O per frame (Constitution VII); explicit closure types and
no long untyped numeric expressions (Linux type-checker); no C stdio globals; no wall-clock
assertions; no main-actor mutation in `setUp`/`tearDown`.

**Scale/Scope**: about 8 new source files, 6 new test files, 8 edited app files.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, QuartzCore, UIKit, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator knows nothing of capture or projectM; the tap wrapper lives in `VisualBandFeed` beside the analyzer; projectM's ring is untouched. |
| VII Real-time safety | The wrapper runs on the analysis worker (never an audio callback), fixed storage, one atomic exchange; the frame path allocates nothing (tested by fixed capacities and stable addresses). |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, golden and UI tests; device GPU timing and allocations stay `{device}`. |
| Privacy | Samples live only in memory (a 16 KB rolling buffer); nothing stored or sent. Two setting keys added to the allowed list. |

No deviation; no ADR needed (ADR-0009 gets a short amendment naming the third visual and the sample
path, as VIS-002 amended it).

## Project Structure

### Documentation (this feature)

```text
specs/083-vis-003-waveform-oscilloscope/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/waveform-oscilloscope.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  WaveformTrigger.swift, WaveformFrameBuffer.swift,
  OscilloscopeConfiguration.swift, OscilloscopeLayout.swift, OscilloscopeGenerator.swift
Packages/VisualGenerators/Sources/VisualBandFeed/WaveformTap.swift
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  WaveformTriggerTests.swift, WaveformFrameBufferTests.swift, OscilloscopeLayoutTests.swift,
  OscilloscopeFlashTests.swift, OscilloscopeRenderTests.swift, WaveformTapTests.swift,
  WaveformFixtures.swift
Packages/RenderGoldens/GeneratorGoldens/{macos,ios-simulator}/
Packages/RenderGoldens/Tests/RenderGoldensTests/OscilloscopeGoldenTests.swift
Apps/projectM-iOS/{Coordinators/AppSettings.swift, Coordinators/AppCoordinator.swift,
  Coordinators/ShowSceneSnapshot.swift, Coordinators/SceneAutosaveCapture.swift,
  Visuals/NativeSpectrumHost.swift, Views/SettingsView.swift, Views/VisualizerView.swift}
Apps/projectM-iOS/Tests/{SettingsTests.swift, NativeVisualTests.swift}
Apps/projectM-iOS/UITests/OscilloscopeUITests.swift
scripts/run_device_tests.py
docs/adr/0009-*.md (amendment)
```

**Structure Decision**: extend the existing packages and app; no new target.

## Complexity Tracking

None.
