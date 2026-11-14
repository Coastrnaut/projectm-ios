# Implementation Plan: PERF-003 Adaptive effect quality

**Branch**: `feature/perf-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/173-perf-003-adaptive-quality/spec.md`

## Summary

A pure-Swift ladder joins FX-001's `VisualEffects` target (VisualGenerators package, Linux-tested):

- `EffectQualityLevel` (full, reduced, minimal), `EffectThermalState`, `EffectBudgetSignal`, `EffectQualityReason`.
- `EffectQualityPolicy`: over-budget hold 3 s, recovery hold 10 s, fade 0.4 s each way.
- `EffectQualityLadder`: stepped with an injected monotonic time, the thermal state, Low Power and the budget
  signal; keeps a target level (immediate thermal step-down, 3 s budget step-down, 10 s one-step recovery), an
  applied level and a glow weight that fades out, switches at zero and fades back in. Arithmetic only.

`BloomPlan` gains a quality argument: Full is today's plan bit for bit; Reduced takes ⌈R/2⌉ taps and, when the
halo extent allows it, twice the downsample, never a wider halo than Full (so the FX-019 area model and the
glow luminance model, both computed for Full, stay upper bounds); `BloomEffect.quality` rebuilds the plan only
on a level change, and Minimal makes the effect pass-through. `BloomEffect` counts its encoded passes.

`QualityGovernor.settings(thermal:lowPower:adaptiveEffects:)` skips the serious-state 30 fps cap while an
adaptable effect is on (critical and Low Power cap as today; the old two-argument call is unchanged).

The native spectrum host owns one ladder: started with the loop, stepped each frame with the display-link
timestamp, its glow weight multiplied into the glow after the ACC-012 clamp (so the FX-019 limiter's luminance
model follows the glow actually drawn), its level handed to the bloom. The coordinator feeds PERF-002's verdict
(any flag → over) while the overlay runs and appends the ladder's overlay line; the automation `perf001` export
carries the level. DEBUG `-uitestThermalState <state>` injects the thermal input.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26 and Linux)
**Primary Dependencies**: Foundation, Metal (BloomEffect only); UIKit/QuartzCore in the app and Rendering
**Storage**: none (no new UserDefaults key, no setting)
**Testing**: XCTest: VisualGeneratorsTests (ladder, plan, strobe fixture, Metal encode counts on the host),
Linux shape (`-Xswiftc -DVISUAL_NO_METAL`), RenderingTests (governor), Diagnostics (export + schema), app unit
tests (host wiring, overlay line), one UI test (< 30 s)
**Target Platform**: iOS/iPadOS 26+, macOS host tests, Linux for the pure logic
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: the ladder adds a few comparisons per frame; zero per-frame allocation; plan rebuilds only on a level change
**Constraints**: safety limiters unchanged at every level (R8); nominal path bit-identical (S5); public APIs only
**Scale/Scope**: 3 levels, 1 effect (FX-001 glow) on the native host

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs | Pass: `ProcessInfo.thermalState`, `isLowPowerModeEnabled`, Metal. |
| VI Modular boundaries | Pass: the ladder knows no renderer; the host maps inputs; Diagnostics gets a plain Codable value. |
| VII Real-time audio safety | Pass: nothing on audio threads; frame path arithmetic only. |
| X Evidence-based quality | Pass: deterministic tests with injected time and inputs; device thermal behaviour is a `{device}` task; no performance claim from the simulator. |
| Flash safety (FR-072, FX-019, ACC-012) | Pass: the ladder only lowers the glow after the clamp; the limiter, envelope and clamp are untouched; level changes fade at < 3 Hz. |
| Privacy | Pass: no new data or keys. |

FR-049 lets the visualization lower its frame rate ("MAY"); deferring the serious-state cap while the glow is
reduced stays within FR-049 and overrides no constitution default, so no ADR is needed (recorded in research).

## Project Structure

### Documentation (this feature)

```text
specs/173-perf-003-adaptive-quality/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/effect-quality-ladder.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/VisualGenerators/
├── Sources/VisualEffects/EffectQuality.swift          # level, inputs, policy, ladder (pure)
├── Sources/VisualEffects/BloomPlan.swift              # + quality (Reduced plan, halo invariant)
├── Sources/VisualEffects/BloomEffect.swift            # + quality, pass counts
└── Tests/VisualGeneratorsTests/EffectQualityLadderTests.swift, EffectQualityBloomTests.swift, EffectQualitySafetyTests.swift
Packages/Rendering/Sources/Rendering/QualityGovernor.swift   # + adaptiveEffects overload
Packages/Rendering/Tests/RenderingTests/QualityGovernorTests.swift
Packages/Diagnostics/ (FrameTimings.effectQuality, exporter line, schema copy, tests)
specs/001-ios-projectm-visualizer/contracts/diagnostics-export.schema.json
Apps/projectM-iOS/
├── Visuals/NativeSpectrumHost.swift (+ NativeSpectrumHost+EffectQuality.swift)
├── Coordinators/AppCoordinator+FrameStages.swift      # budget signal in, overlay line out
├── Automation/AutomationRunner.swift                  # perf001 exports the level
├── Tests/EffectQualityAppTests.swift
└── UITests/EffectQualityOverlayUITests.swift
```

**Structure Decision**: The ladder sits beside the bloom it drives (VisualEffects is pure Swift apart from the
Metal files and runs on Linux). `AppCoordinator.swift`, `SettingsView.swift`, `Compositor.swift` and
`VisualizerView.swift` are not touched.

## Complexity Tracking

None.
