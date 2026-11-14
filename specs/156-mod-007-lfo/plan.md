# Implementation Plan: MOD-007 LFO Sine and Triangle

**Branch**: `feature/mod-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/156-mod-007-lfo/spec.md`

## Summary

A pure, clocked low-frequency oscillator becomes a new binding source next to the audio features:

- **ParameterGraph** (`LFO.swift`): `LFOShape` (`sine`, `triangle`), `LFO` (rate Hz 0.01…20, phase
  offset 0…1, amplitude 0…1, centre 0…1; `validationProblem`; `phase(elapsedNanoseconds:rateHz:)`,
  `value(elapsedNanoseconds:maximumRateHz:)`), `LFOBank` (at most 8; shared origin at the first
  sample after `set`; `values(atNanoseconds:maximumRateHz:into:)`), `LFOError`. The phase is computed
  from the integer nanoseconds split into whole seconds and a remainder with a fused multiply-add, so
  it is exact to ~1e-16 cycles regardless of running time (research MOD-007-D1 to D3).
- **Binding source**: `AudioFeatureSource.lfo(Int)` with ID `audio.lfo.<index>` (0…7);
  `AudioFeatureFrame.lfos` (a borrowed `UnsafeBufferPointer<Double>`, empty by default) carries the
  bank's values for the frame; a missing value reads 0. Validation refuses an index outside 0…7. The
  SHD-009 expression catalog does not accept LFO names (research MOD-007-D4).
- **Safety**: `LFOBank.reduceFlashingMaximumRateHz = 3`; the app passes it while the effective Reduce
  flashing setting is on (research MOD-007-D5).
- **SceneFormat** (`SceneLFOs.swift`): an optional top-level `lfos` array of verbatim `SceneLFOEntry`
  objects, written only when non-nil; `SceneLFOEntry.read(_:)` returns the oscillators by position
  (nil for unusable entries) and warnings (`invalidLFO`, `unknownLFO`), which `validate` includes; the
  live state and `init(live:)` carry the list (research MOD-007-D6).
- **App**: `NativeSpectrumHost` owns an `LFOBank` and an 8-value scratch buffer; `applyModulation`
  fills the scratch at the frame's display time (rate capped while `reduceFlashing`) and passes it in
  the frame; `AppCoordinator+LFOs.swift` sets the current scene's oscillators when the native visual is
  created; the scene carry writes the list back unchanged (research MOD-007-D7).
- Tests: acceptance (closed form at quarter periods, irrational and multi-hour times within 1e-9),
  determinism, bounds, the safety cap, source ID parsing and binding through the modulator, scene round
  trip and issues, an app unit test (LFO → glow intensity).

No ADR: nothing overrides a default (a new optional scene field follows SCN-001's rule; no settings key;
the 3 Hz cap tightens FR-072, it does not relax it).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new; `LFO.swift` uses only the platform C math library (`sin`) through
the same `Darwin`/`Glibc`/`Musl` imports as ExpressionMath.

**Storage**: scene JSON (SCN-001), new optional `lfos` field; no UserDefaults key.

**Testing**: XCTest. ParameterGraph and SceneFormat on the macOS host (Linux in CI); app unit tests on
the private iOS 27.2 simulator "MOD7 iPhone 17". Budgets (owner rule 7): each test ≲ 1 s, suites under
1 minute. Times injected as integer nanoseconds, no wall clock.

**Target Platform**: iOS/iPadOS 26+ (app), macOS host, Linux (packages).

**Project Type**: mobile app with SwiftPM packages.

**Performance Goals**: per frame at most 8 oscillator evaluations (one `sin` each), no allocation, no
lock (main thread, display link; never an audio callback).

**Constraints**: Constitution VI (the oscillator lives in ParameterGraph, no new dependency), VII (not
in audio callbacks), X (tests); FR-072 / ACC-012 (flash safety).

**Scale/Scope**: 2 new source files, ~4 edited ParameterGraph files (source, frame, validation,
expression catalog and compiler switch), 6 edited SceneFormat files, 4 edited app files plus 1 new,
3 new test files.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass: plain Swift and the C math library. |
| II-V Capture | Not affected. |
| VI Modular boundaries | Pass: oscillator in ParameterGraph, persistence in SceneFormat, feed in the app. |
| VII Real-time audio safety | Pass: evaluated on the display-link frame, allocation-free; no audio callback. |
| VIII Upstream fidelity | Not affected. |
| IX Pinned dependencies | No new dependency. |
| X Evidence-based quality | Pass: closed-form unit tests with injected times; app test on the simulator; no device claim. |
| Privacy | No new stored key, no network. |
| Flash safety (FR-072) | Pass: rate capped at 3 Hz under Reduce flashing; the ACC-012 clamp still follows modulation. |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/156-mod-007-lfo/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/lfo.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/ParameterGraph/Sources/ParameterGraph/LFO.swift                         (new)
Packages/ParameterGraph/Sources/ParameterGraph/{AudioFeatureSource,AudioFeatureBinding,AudioFeatureModulator}.swift
Packages/ParameterGraph/Sources/ParameterExpression/{ExpressionCatalog,ExpressionCompiler}.swift
Packages/ParameterGraph/Tests/ParameterGraphTests/LFOTests.swift                 (new)
Packages/SceneFormat/Sources/SceneFormat/SceneLFOs.swift                         (new)
Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneIssue,SceneValidation,SceneLiveState,SceneRepair}.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneLFOTests.swift                  (new)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Coordinators/AppCoordinator+LFOs.swift                         (new)
Apps/projectM-iOS/Coordinators/{AppCoordinator,SceneAutosaveCapture,SceneAutosaveCoordinator,ParameterInspectorModel}.swift
Apps/projectM-iOS/Tests/LFOBindingAppTests.swift                                 (new)
```

**Structure Decision**: follow MOD-006's split (pure model in ParameterGraph, persistence in
SceneFormat, an app unit test through `NativeSpectrumHost`).

## Complexity Tracking

None.
