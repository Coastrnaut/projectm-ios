# Implementation Plan: VIS-008 Particle Fountain

**Branch**: `feature/vis-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/203-vis-008-particle-fountain/spec.md`

## Summary

An eighth native visual beside VIS-001 to VIS-007: bursts of particles launched from the bottom centre on
each ANL-004 onset, moving under gravity and linear drag. `ParticleFountainSimulation` (pure Swift, every
platform) owns a preallocated pool of 512 particles, a queue of 32 pending onsets and a SplitMix64
generator; it advances in fixed 1/240 s steps scheduled in integer nanoseconds from an anchor, so the state
at any time depends only on the seed, the configuration and the onset log, never on how frames divide time.
`ParticleFountainLayout` turns the live particles into flat squares (the FX-019 flash regions);
`ParticleFountainGenerator` draws them with the shared `FlatShapePass` under FX-019's envelope gain. The
host reuses VIS-006's bus subscription: while the fountain is shown, each drained `onset` event is enqueued
stamped with the frame's time. The app adds the Visual choice "Particle Fountain" with one setting key
(Gravity) and passes Reduce Motion (VIS-007's `NativeSpectrumHost.reduceMotion`) to the fountain. Proof:
CPU acceptance (fixed seed + event log replayed twice and with 60 Hz, 30 Hz and irregular frames: identical
counts, positions within 1e-9), ballistic closed form, bounds, Reduce Motion, flash-envelope tests, one GPU
golden, app tests and a short UI test.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal (`FlatShapePass`), FlashSafety (envelope), AnalysisFeatures (onset event
type, in `VisualBandFeed` only). No new dependency.

**Storage**: One UserDefaults key (`settings.particleFountain.gravity`).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host and the Linux shape
`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`), `Packages/RenderGoldens` golden (macOS
host, iOS Simulator), app unit tests and one UI test on the agent's own simulator "VIS8 iPhone 17".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Project Type**: iOS app with SwiftPM packages.

**Performance Goals**: At most 512 particles: 512 regions, 3,072 vertices, ≤ 240 steps × 512 particles per
frame only after a long gap (normally 4 steps per 60 Hz frame); no allocation per frame.

**Constraints**: Owner rule 7 test budgets; no wall-clock assertions (clock injected); type-check budget;
deterministic floating point (only +, −, ×, ÷ and `sin`/`cos` of the drawn angles in the simulation).

**Scale/Scope**: 4 new package source files (configuration, simulation, layout, generator) plus a small
onset filter in `VisualBandFeed`, edits to about 9 app files, 3 package test files, a golden test with 2
images per platform class, 1 app unit test file, 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, UIKit, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator knows nothing of analysis, settings or projectM: it receives onsets (time, strength, threshold), a time and a configuration. The bus mapping lives in `VisualBandFeed`. |
| VII Real-time safety | The pool, queue and layout are preallocated; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, golden and UI tests; device look and GPU timing stay `{device}`. |
| Privacy | Nothing stored or sent besides one setting key, added to every key list. |

No deviation; no ADR needed (ADR-0009 covers native visuals, ADR-0011 the envelope). Post-design re-check:
unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/203-vis-008-particle-fountain/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/particle-fountain.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/VisualGenerators/Sources/VisualGenerators/
├── ParticleFountainConfiguration.swift  # gravity, drag, life, size, seed, Reduce Motion, palette; burst size, SplitMix64
├── ParticleFountainSimulation.swift     # pool, onset queue, fixed-step integration, counters
├── ParticleFountainLayout.swift         # CPU squares, FlashRegionLayout
└── ParticleFountainGenerator.swift      # Metal generator on FlatShapePass (behind VISUAL_NO_METAL)
Packages/VisualGenerators/Sources/VisualBandFeed/ParticleFountainTrigger.swift   # onset events → (strength, threshold)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
├── ParticleFountainSimulationTests.swift, ParticleFountainFlashTests.swift, ParticleFountainRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/ParticleFountainGoldenTests.swift
Packages/RenderGoldens/GeneratorGoldens/ParticleFountain/{macos,ios-simulator}/
Apps/projectM-iOS/Coordinators/{AppSettings,AppCoordinator,SceneAutosaveCapture,ShowSceneSnapshot}.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Views/{SettingsView,VisualizerView}.swift
Apps/projectM-iOS/Tests/ParticleFountainAppTests.swift (+ native lists in SettingsTests, CameraVisualTests)
Apps/projectM-iOS/UITests/ParticleFountainUITests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py
```

**Structure Decision**: mirror VIS-006 (event-driven) and VIS-007 (Reduce Motion) file for file.

## Complexity Tracking

None.
