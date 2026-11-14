# Implementation Plan: ACC-012 Sensory Safety Profile

**Branch**: `feature/acc-012` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/121-acc-012-sensory-safety-profile/spec.md`

## Summary

One plain-Swift model, `SensorySafetyProfile` (preset + custom limits), and one value, `SafetyClamp`
(the effective limits after the effective Reduce flashing raised the flash limit), both in the
Linux-tested FlashSafety package next to FX-019's `FlashEnvelopeConfiguration`. The clamp produces the
flash envelope configuration every renderer uses (native generators through `VisualFrameContext`,
projectM through `ANGLERenderer`, camera/photo/video/text through the compositor's final flash guard)
and caps glow intensity, binding excursions and graph speed where a frame's parameters are resolved:
after MOD-002 modulation in `NativeSpectrumHost.resolveEffectiveGlow()` and in
`GeneratorGraphLayer.render`. Standard yields `nil` overrides and identity caps, so the existing code paths
run unchanged (bit-identical). Settings gains a Sensory safety section; values persist in four
UserDefaults keys, are cleared by the UI-test reset and travel in the FILE-005 backup. ADR-0049 records
the clamp point and precedence (research R1-R6).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2, Swift 6.4.2; CI also Xcode 26.x)

**Primary Dependencies**: FlashSafety (pure Swift), VisualGenerators/VisualEffects, ANGLERendering,
Compositor (+ GeneratorGraph), SwiftUI app target

**Storage**: UserDefaults (four `settings.sensorySafety.*` keys), local only

**Testing**: XCTest: FlashSafety package (host + Linux), VisualGenerators GPU test (host Metal),
app unit tests and one UI test on an own iOS 27.2 simulator

**Target Platform**: iOS/iPadOS 26.0+

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: no per-frame allocation; the clamp is a few comparisons per frame

**Constraints**: real-time render paths unchanged in Standard; tests within owner rule 7 budgets

**Scale/Scope**: 2 new package files, ~12 edited files, 1 new view, 1 ADR

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass: no new system API beyond SwiftUI and UserDefaults |
| VI Modular boundaries | Pass: the profile lives in FlashSafety (no UI, no app types); renderers get a plain `FlashEnvelopeConfiguration?`; projectM bridge untouched |
| VII Real-time safety | Pass: the clamp is a value copied on the main actor; no allocation, lock or I/O per frame; nothing in audio callbacks |
| VIII Upstream fidelity | Pass: no engine change; projectM gets only the existing envelope pass |
| X Evidence-based quality | Pass: table test on renderer inputs, GPU bit-identity test, UI probe; device check left `{device}` |
| Privacy | Pass: local keys in `ALLOWED_KEYS`; backup is FILE-005's local export |

Post-design re-check: unchanged (no violations).

## Project Structure

### Documentation (this feature)

```text
specs/121-acc-012-sensory-safety-profile/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/safety-clamp.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/FlashSafety/Sources/FlashSafety/SensorySafetyProfile.swift   (new)
Packages/FlashSafety/Sources/FlashSafety/SafetyClamp.swift            (new)
Packages/FlashSafety/Tests/FlashSafetyTests/SensorySafetyTests.swift  (new; clamp table on values)
Packages/VisualGenerators/Sources/VisualGenerators/VisualGenerator.swift   (VisualFrameContext.flashLimits)
Packages/VisualGenerators/Sources/VisualGenerators/FlashSafetyLimiter.swift (configuration overloads)
Packages/VisualGenerators/Sources/VisualGenerators/{Circular,Linear}SpectrumGenerator.swift, OscilloscopeGenerator.swift
Packages/VisualGenerators/Sources/VisualEffects/BloomParameters+Safety.swift (new)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/SensorySafetyRenderTests.swift (new; GPU bit identity, Strict)
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift    (flashLimits)
Packages/Compositor/Sources/Compositor/Compositor.swift, CompositeFlashGuard.swift (flashLimits)
Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphLayer.swift  (intensityLimit, effectiveSpeed)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift    (includedKeys)
Apps/projectM-iOS/Coordinators/SensorySafetySetting.swift             (new; storage)
Apps/projectM-iOS/Coordinators/AppSettings.swift, AppCoordinator.swift, PresetCoordinator.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Views/SensorySafetySection.swift                    (new), SettingsView.swift, VisualizerView.swift
Apps/projectM-iOS/Tests/SensorySafetyTests.swift                       (new)
Apps/projectM-iOS/UITests/SensorySafetyUITests.swift                   (new)
scripts/run_device_tests.py (ALLOWED_KEYS)
docs/adr/0049-sensory-safety-clamp.md (number checked before commit)
```

**Structure Decision**: model and clamp in FlashSafety (already the one definition of a flash, tested on
Linux, a dependency of every renderer package); app storage and UI in the app target.

## Complexity Tracking

No violations to justify.
