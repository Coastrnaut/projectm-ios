# Implementation Plan: VIS-001 Circular Spectrum

**Branch**: `feature/vis-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/019-vis-001-circular-spectrum/spec.md`

## Summary

The app's first native visual, beside projectM and isolated from it (ADR-0009, new).

1. **New package `Packages/VisualGenerators`** (the roadmap's proposed name), one library product
   with two targets:
   - **`VisualGenerators`** (no package dependencies): the generator contract (`VisualFrameContext`,
     `TextureGenerator`), the circular spectrum's configuration, palette, CPU geometry
     (`CircularSpectrumLayout`: one `BarGeometry` per bar plus tessellation into a preallocated
     vertex array), the Reduce-flashing limiter (`FlashSafetyLimiter`), a lock-free triple buffer
     for band frames (`BandFrameBuffer`), and, behind `#if canImport(Metal)`, the Metal generator
     (`CircularSpectrumGenerator`) with its shader source as a Swift constant (research VIS-001-D3).
     Everything except the Metal file builds and is tested on Linux.
   - **`VisualBandFeed`** (depends on `AnalysisFeatures`, `AudioCore`): `SpectrumBandFeed`
     (SpectrumStream 2,048/512/mid → BandReducer → BandMath decibels into a preallocated vector) and
     `LiveBandAnalyzer` (a serial analysis queue with a timer that pulls a `NormalizedPCMReader`,
     the analysis tap, and publishes into a `BandFrameBuffer`; start/stop idempotent).
2. **Delta in AudioCore and CaptureKit** (VIS-001-R14): `AudioAnalyzer.init(…,
   analysisTapCapacityFrames: Int = 0)` builds its ring with that capacity; `CaptureManager.init(…,
   analysisTapCapacityFrames: Int = 0)` passes it on and exposes `analysisTap`. Defaults keep today's
   behavior exactly; projectM's `normalizedOutput` is unchanged.
3. **App** (`Apps/projectM-iOS`):
   - `AppSettings`: `visual` (`VisualChoice`: `projectM` default, `circularSpectrum`) and
     `circularSpectrumBars` (16/32/64/128, default 64), keys `settings.visual` and
     `settings.circularSpectrum.bars`, added to `allKeys`.
   - `Visuals/CircularSpectrumHost.swift`: a `CAMetalLayer` view (`bgra8Unorm_srgb`), a
     `CADisplayLink` frame loop (same frame-rate policy as ANGLE: `QualityGovernor`), the generator,
     the `LiveBandAnalyzer`; `pause()/resume()` (FR-046) and `PresentationBoundResource` (PERF-011),
     `reduceFlashing`, `metrics` (`FrameRateMeter`). `make(…)` throws when there is no Metal device
     or the pipeline fails (failure boundary).
   - `AppCoordinator`: creates the capture manager with the tap on
     (`NormalizedPCMRing.analysisTapDefaultCapacityFrames`); `showsNativeVisual`; the host is created
     on first use and registered with the presentation registry; every former
     `renderer?.pause()/resume()` goes through `pauseActiveVisual()/resumeActiveVisual()`, which
     keeps projectM paused while the native visual runs; fallback state `nativeVisualUnavailable`.
     DEBUG launch argument `-uitestNativeVisualFailure` forces the failure path.
   - Views: `VisualizerView` shows the host (identifier `circularSpectrum`) instead of
     `RendererHost` when the native visual is active, plus the fallback banner
     (`nativeVisualUnavailable`); `ControlsOverlay` drops preset navigation and names the visual;
     `SettingsView` gets a "Visual" section (segmented pickers `visualPicker`, `barsPicker`);
     `PerformanceOverlay` reads the active visual's metrics.
4. **Shared files, minimal edits**: `project.yml` (two package entries, one app dependency),
   `.github/workflows/ios-ci.yml` (add `VisualGenerators` to the five package loops),
   `scripts/run_device_tests.py` (two allowed UserDefaults keys); `AppCoordinator.swift` localized.
   `scripts/test_scripts.py` needs no change.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency complete), Xcode 27.2

**Primary Dependencies**: Metal and QuartzCore (public); `AnalysisFeatures` (ANL-001/002) and
`AudioCore`; Synchronization (`Atomic`) for the triple buffer. No third-party dependency.

**Storage**: two UserDefaults keys (user settings, FR-065).

**Testing**: XCTest. `swift test` for `VisualGenerators`, `AudioCore`, `CaptureKit` on the macOS host
(Metal available there, so the render test runs on the host GPU); `xcodebuild test -scheme
VisualGenerators` on the iOS 27.2 iPhone Air simulator; Linux in CI (geometry, palette, limiter,
buffer, band feed; the Metal file compiles out). App unit and UI tests on the simulator.

**Target Platform**: iOS/iPadOS 26.0+; the package also macOS 15+ and Linux (non-Metal parts).

**Project Type**: SwiftPM packages plus the XcodeGen iOS app.

**Performance Goals**: at most 128 bars × 4 arc segments × 6 vertices = 3,072 vertices (72 KiB) per
frame; analysis about 86 spectra per second of audio (hop 512). Reported, never asserted.

**Constraints**: no allocation, lock, log or I/O in our per-frame code (layout, tessellation,
limiter, buffer exchange, encoding into preallocated buffers; Metal's own command objects are the
system's); nothing on the audio callback; analysis on its own queue; nothing to projectM
(Constitution VIII, ADR-0008 decision 5); GPU tests skip cleanly without a Metal device.

**Scale/Scope**: about 1,100 lines of package Swift, 350 lines of app Swift, 900 lines of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Metal, QuartzCore, UIKit, SwiftUI, Synchronization; runtime compile through `MTLDevice.makeLibrary(source:options:)`, a public API | Pass |
| II Capture feasibility | No capture change; the tap copies normalized audio already produced | Pass (n/a) |
| III ScreenCaptureKit | Not touched | Pass (n/a) |
| IV Truthful labeling | The source indicator and banners are unchanged; the native visual shows no source name of its own; the fallback notice says exactly what is shown | Pass |
| V No universal claims | No compatibility text | Pass |
| VI Modular boundaries | Generators know nothing of projectM, capture or the app; the band feed reads only `NormalizedPCMReader`; the app wires them | Pass |
| VII Real-time safety | Audio callback untouched; the tap write is on the existing work queue (preallocated SPSC); analysis on its own serial queue; frame path allocation- and lock-free | Pass |
| VIII ProjectM fidelity | projectM's reader, presets and engine untouched; analysis results go only to the native generator (ADR-0008 decision 5) | Pass |
| IX Dependencies | None added | Pass |
| X Evidence | Host, simulator and Linux tests; render check on host and simulator GPUs reported as such; device GPU checks are `{device}` tasks | Pass |
| Privacy | Two user-setting keys; no audio stored or sent; no network | Pass |
| Accessibility (FR-070, FR-072) | Labeled controls and visual; Reduce flashing honored with documented bounds | Pass |

Post-design re-check: unchanged, all pass. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/019-vis-001-circular-spectrum/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── checklists/requirements.md
└── contracts/visual-generator.md
docs/adr/0009-native-visual-generators.md
```

### Source Code (repository root)

```text
Packages/VisualGenerators/
  Package.swift
  Sources/VisualGenerators/
    VisualGenerator.swift            (VisualFrameContext, TextureGenerator, VisualGeneratorError)
    CircularSpectrumConfiguration.swift (SpectrumBarCount, RingDirection, configuration, clamping)
    VisualPalette.swift              (palettes, sRGB↔linear, relative luminance)
    CircularSpectrumLayout.swift     (BarGeometry, layout, tessellation, mean luminance)
    FlashSafetyLimiter.swift         (Reduce-flashing slew and luminance gain)
    BandFrameBuffer.swift            (lock-free triple buffer)
    CircularSpectrumGenerator.swift  (#if canImport(Metal): pipeline, shader source, encode)
  Sources/VisualBandFeed/
    SpectrumBandFeed.swift  LiveBandAnalyzer.swift
  Tests/VisualGeneratorsTests/
    GeometryTestSupport.swift (independent angle oracle) ConfigurationTests  PaletteTests
    CircularSpectrumGeometryTests (impulse × count × size × offset matrix)  TessellationTests
    FlashSafetyLimiterTests  BandFrameBufferTests  CircularSpectrumRenderTests (Metal, skips)
    BandFeedTests (AUD-016 sines → bands → lit bar)  LiveBandAnalyzerTests
Packages/AudioCore/   AudioAnalyzer.swift (+ tap capacity), Tests (+ tap test)
Packages/CaptureKit/  CaptureManager.swift (+ tap capacity, analysisTap), Tests (+ tap test)
Apps/projectM-iOS/
  Visuals/CircularSpectrumHost.swift   Coordinators/AppSettings.swift, AppCoordinator.swift
  Views/VisualizerView.swift, ControlsOverlay.swift, SettingsView.swift, PerformanceOverlay.swift
  Tests/SettingsTests.swift (+), Tests/NativeVisualTests.swift (new)
  UITests/NativeVisualUITests.swift (new)
```

**Structure Decision**: a new package, because the roadmap layout names `VisualGenerators` and no
existing package fits (Rendering and ANGLERendering are projectM adapters, iOS-only; AnalysisFeatures
must not draw). The band feed is a second target in the same package so the generator target stays
dependency-free for CMP-001.

## Test design (deterministic)

- Geometry oracle: the tests recompute θ(k) = start + d·(k + 0.5)·360/N + offset in Double, without
  calling the layout, and compare modulo 360° within 0.01°; "lit" = outer radius > inner radius.
- Matrix: 4 bar counts × every band (240 impulses) × 5 sizes (1179×2556, 2556×1179, 2064×2752,
  2752×2064, 1640×2360) × 6 offsets {−90, 0, 37.5, 90, 180, 450}; plus counter-clockwise and a start
  angle; plus containment (every vertex in the output) and isotropy (radius unit equal on both axes,
  checked through the tessellated vertices in pixels).
- Render test (Metal): offscreen `bgra8Unorm_srgb` texture 600×1200 and 1200×600, blit to a shared
  buffer, sample rays every 0.25° at radii across the bar; assert every lit sample is within the bar's
  half-width plus 1.5 pixels at that radius (at most 2°) of θ(k), the centre ray is lit, the
  neighbouring bars' centre rays are dark, and silence leaves every sample dark. `XCTSkip` when
  `MTLCreateSystemDefaultDevice()` is nil (and when the pipeline cannot be built under CI), never fail
  for environment reasons.
- Band feed: AUD-016 `ToneGenerator` sines at 100, 440, 1,000, 1,500 Hz (amplitude 0.5, stereo, 1 s),
  fed through a fake `NormalizedPCMReader` into `SpectrumBandFeed`; for every bar count the largest
  band is `BandLayout.band(containingFrequency:)`, and the layout's longest bar is that band.
- Limiter: alternating all-zero/all-one bands for 600 frames at frame times 1/120…0.2 s; luminance
  rises bounded by 0.25·min(dt, 0.1) (+1e-6), slew bounded by 4·min(dt, 0.1); off = pass-through.
- `LiveBandAnalyzer`: start/stop idempotent, a frame published after audio arrives (waits with a 30 s
  ceiling on an expectation, never a frame budget), nothing published after stop.
- No wall-clock assertions anywhere; no randomness. Linux: test classes not `@MainActor`.
- Red run first: tests written against missing symbols fail to compile (recorded in tasks.md).

## Persistence and rollback

- Persistence: `settings.visual` (string `projectM` | `circularSpectrum`; unknown or absent →
  projectM) and `settings.circularSpectrum.bars` (integer 16/32/64/128; anything else → 64). No
  migration: absent keys are today's state. Both are user settings (FR-065), cleared with the other
  settings by `-uitestResetNotice`, and added to the device privacy check's allowed list.
- Runtime rollback: if the native visual cannot be created, the app shows projectM (VIS-001-R16).
- Code rollback: revert the feature's commits. The AudioCore/CaptureKit deltas default to the old
  behavior, so removing the app's opt-in alone also restores today's audio path exactly; removing the
  stored keys returns every user to projectM.

## Complexity Tracking

None.
