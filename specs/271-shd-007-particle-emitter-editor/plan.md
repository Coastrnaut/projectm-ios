# Implementation Plan: SHD-007 Particle Emitter Editor

**Branch**: `feature/shd-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/271-shd-007-particle-emitter-editor/spec.md`

## Summary

Add optional emitter settings to the VIS-008 Particle Fountain: spawn shape, a continuous rate on an integer
accumulator, speed/direction/spread, a lifetime range drawn from the existing seeded SplitMix64, gravity, and
floor/box collision bounds with bounce or kill. The fountain's fixed 512-particle pool, fixed 1/240 s steps on the
injected frame clock, layout, Metal pass and strobe safety envelope are reused unchanged; without emitter settings
the fountain is exactly VIS-008. The app adds Settings › Particle emitter (switch, live preview on a fixed 30 fps
frame clock, Reset, seed, ACC-005 sliders), one UserDefaults key, and passes the emitter to the fountain's style.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2; CI also Xcode 26)

**Primary Dependencies**: VisualGenerators (VIS-008 fountain, SplitMix64, FlatShapePass), SwiftUI, ACC-005
`AccessibleParameter`

**Storage**: UserDefaults key `settings.particleFountain.emitter` (JSON)

**Testing**: XCTest: package tests (pure simulation, Metal render), app unit tests, one XCUITest

**Target Platform**: iOS 26+ app; the package also builds on Linux (simulation and settings are pure Swift)

**Project Type**: mobile app + Swift packages

**Performance Goals**: no allocation per frame (Constitution VII pattern of VIS-008); at most one continuous spawn
per 1/240 s step

**Constraints**: pool fixed at 512; tests within owner rule 7 budgets; no wall-clock assertions

**Scale/Scope**: one package file pair (settings, simulation changes), one app store, one view, small edits to
the fountain style and settings lists

## Constitution Check

- I Public APIs only: SwiftUI, Metal, UserDefaults. Pass.
- VI Modular boundaries: emitter physics in the VisualGenerators package; the app only stores and wires. Pass.
- VII Real-time safety: no allocation added to the simulation step; the pool stays fixed. Pass.
- X Evidence-based quality: acceptance proven by deterministic tests; the device look is a `{device}` task. Pass.
- Platform/privacy: no network, no new data leaves the device; the key follows FILE-005 backup rules. Pass.
- SHD-011: parameters only; no user code or shader. Pass.

## Project Structure

### Documentation (this feature)

```text
specs/271-shd-007-particle-emitter-editor/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/particle-emitter.md
└── tasks.md
```

### Source Code

```text
Packages/VisualGenerators/Sources/VisualGenerators/
├── ParticleEmitterSettings.swift          # new: settings, ranges, clamping, Codable
├── ParticleFountainConfiguration.swift    # + `emitter: ParticleEmitterSettings?`
└── ParticleFountainSimulation.swift       # + continuous spawn, emitter draws, bounds, expiry stats
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
├── ParticleEmitterSimulationTests.swift   # acceptance (10 s seeded run)
├── ParticleEmitterSettingsTests.swift     # clamping, coding
└── ParticleEmitterRenderTests.swift       # Metal golden signature
Apps/projectM-iOS/
├── Coordinators/ParticleEmitterChoice.swift   # stored switch + settings, lenient JSON, seed sequence
├── Coordinators/AppSettings.swift             # key, property, allKeys
├── Coordinators/AppCoordinator.swift, SnapshotBatchJob.swift, Visuals/NativeSpectrumHost.swift  # style carries emitter
├── Views/ParticleEmitterEditorView.swift      # editor, preview
├── Views/SettingsView.swift                   # link section
├── Tests/ParticleEmitterEditorTests.swift
└── UITests/ParticleEmitterEditorUITests.swift
```

**Structure Decision**: extend the fountain rather than add a parallel particle system, so the layout, Metal pass,
flash areas and app wiring are shared (research SHD-007-D1).
