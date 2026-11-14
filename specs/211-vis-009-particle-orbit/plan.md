# Implementation Plan: VIS-009 Particle Orbit

**Branch**: `feature/vis-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/211-vis-009-particle-orbit/spec.md`

## Summary

A ninth native visual beside VIS-001 to VIS-008: a ring of up to 256 seeded particles circling the output's
centre, whose radius follows the mapped bass, around a centre square that pulses on beats.
`ParticleOrbitSimulation` (pure Swift, every platform) owns preallocated per-slot phases, speeds and offsets,
a beat queue of 16 and VIS-008's SplitMix64; it advances in fixed 1/240 s steps on the injected frame clock
(VIS-008's integer-nanosecond schedule), slewing the radius toward the frame's target with a bounded one-pole
step and decaying the beat pulse. `ParticleOrbitLayout` turns it into flat squares (the FX-019 regions);
`ParticleOrbitGenerator` draws them with the shared `FlatShapePass` under the envelope gain. "Mapped bass":
a new MOD-001 parameter `visual.particleOrbit.radius`; `ParticleOrbitRadiusDrive` (VisualParameters) picks,
per frame, the base and the bass: unbound → the Radius setting and ANL-007's kick envelope; bound → the
MOD-002 modulator's value and no built-in bass. The host feeds it after `applyModulation`, and drains VIS-006's
bus subscription through `BeatRingTrigger` into the orbit's beat queue. The app adds the Visual choice
"Particle Orbit" with one setting key (Radius). Proof: radius-tracking acceptance (synthetic bass timeline,
with and without a MOD-002 binding), the fixed work bound over 600 frames, determinism, flash-envelope tests,
a GPU render test, one golden per platform class, app tests and a short UI test.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal (`FlatShapePass`), FlashSafety (envelope), ParameterGraph (modulator, in
`VisualParameters` only), AnalysisFeatures (beat events via `BeatRingTrigger`, host only). No new dependency.

**Storage**: One UserDefaults key (`settings.particleOrbit.radius`); one permanent catalog ID.

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host and Linux shape
`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`), `Packages/RenderGoldens` golden (macOS host,
iOS Simulator), app unit tests and one UI test on "VIS9 iPhone 17".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Project Type**: iOS app with SwiftPM packages.

**Performance Goals**: ≤ 1,024 particle steps and ≤ 1,542 vertices per 60 Hz frame (Clarifications); no
allocation per frame; frame rate on D1 is `{device}`.

**Constraints**: Owner rule 7 test budgets; no wall-clock assertions; type-check budget; deterministic
arithmetic (+, −, ×, ÷, `exp` of constants, `sin`/`cos` of phases).

**Scale/Scope**: 4 new package source files plus a drive helper in `VisualParameters`; a catalog entry; edits
to about 10 app files; 3 package test files; a golden test; 1 app unit test file; 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, UIKit, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator receives a target radius, beats, a time and a configuration; it knows nothing of analysis, bindings, settings or projectM. The binding choice lives in `VisualParameters`, the bus mapping in the host via `BeatRingTrigger`. |
| VII Real-time safety | Slots, beat queue and layout preallocated; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, golden and UI tests; device frame rate stays `{device}`. |
| Privacy | One setting key, added to every key list. |

No deviation; no ADR needed (ADR-0009 native visuals, ADR-0011 envelope, ADR-0012 catalog IDs). Post-design
re-check: unchanged.

## Project Structure

```text
specs/211-vis-009-particle-orbit/  spec, plan, research, data-model, quickstart, tasks, contracts/particle-orbit.md, checklists/
Packages/VisualGenerators/Sources/VisualGenerators/
├── ParticleOrbitConfiguration.swift   # count, radius, depth, speed, size, seed, Reduce Motion, palette; target mapping
├── ParticleOrbitSimulation.swift      # slots, beat queue, fixed-step phases, radius slew, pulse, work counter
├── ParticleOrbitLayout.swift          # CPU squares, FlashRegionLayout
└── ParticleOrbitGenerator.swift       # Metal generator on FlatShapePass (behind VISUAL_NO_METAL)
Packages/VisualGenerators/Sources/VisualParameters/
├── VisualParameterCatalog.swift       # + visual.particleOrbit.radius
└── ParticleOrbitRadiusDrive.swift     # unbound: setting + kick; bound: modulator value, no bass
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
├── ParticleOrbitSimulationTests.swift, ParticleOrbitFlashTests.swift, ParticleOrbitRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/ParticleOrbitGoldenTests.swift (+ GeneratorGoldens/ParticleOrbit/)
Apps/projectM-iOS/Coordinators/{AppSettings,AppCoordinator,SceneAutosaveCapture,ShowSceneSnapshot}.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, Views/{SettingsView,VisualizerView}.swift
Apps/projectM-iOS/Tests/ParticleOrbitAppTests.swift (+ SettingsTests, CameraVisualTests), UITests/ParticleOrbitUITests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py
```

**Structure Decision**: mirror VIS-008 file for file; reuse VIS-006's `BeatRingTrigger` (no new trigger file).

## Complexity Tracking

None.
