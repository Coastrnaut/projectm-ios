# Implementation Plan: MOD-006 Threshold Trigger

**Branch**: `feature/mod-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/148-mod-006-threshold-trigger/spec.md`

## Summary

A generic, pure threshold trigger turns any MOD-002 audio feature into debounced discrete events and
drives the MIDI-006 trigger actions:

- **ParameterGraph** (`ThresholdTrigger.swift`): `ThresholdTriggerSettings` (high, low, minimum
  interval, hold; validated), `ThresholdTrigger` (a value type with the Schmitt state and
  `mutating step(value:timeNanoseconds:) -> Bool`), `ThresholdTriggerAction` (`cue.next`,
  `cue.previous`, `blackout`), `ThresholdTriggerBinding` (source, action, settings) and
  `ThresholdTriggerBank` (at most 8 bindings; `advance(frame:timeNanoseconds:fire:)` calls `fire` once
  per firing binding, in binding order, allocation-free after setup). Research MOD-006-D1 to D5.
- **SceneFormat** (`SceneTriggers.swift`): an optional top-level `triggers` array of verbatim
  `SceneTriggerEntry` objects, written only when non-nil; `SceneTriggerEntry.read(_:)` gives the live
  bindings and warnings (`invalidTrigger`, `unknownTrigger`), which `validate` includes; the live state
  and `init(live:)` carry the list. Research MOD-006-D6, D7.
- **App**: `NativeSpectrumHost` owns a `ThresholdTriggerBank`; `applyModulation` evaluates it with the
  same frame as the bindings and calls `onTrigger`. `AppCoordinator+ThresholdTriggers.swift` connects a
  `MIDINoteActionPerformer` (new `fire(_:)` for trigger-mode actions) and sets the current scene's
  triggers when the native visual is created; the scene carry writes the list back unchanged.
  Research MOD-006-D8.
- Tests: acceptance (seeded noise → at most 1 trigger; pulse trains), edge cases, frame rates, jitter,
  NaN, determinism, scene round trip and issues, an app unit test (kick → Next cue once per kick).

No ADR: nothing overrides a default (a new optional scene field follows SCN-001's rule; no settings key).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new; ParameterGraph stays Foundation-only, SceneFormat plain Swift.

**Storage**: scene JSON (SCN-001), new optional `triggers` field; no UserDefaults key.

**Testing**: XCTest. ParameterGraph and SceneFormat on the macOS host (Linux in CI); app unit tests on
the private iOS 27.2 simulator "MOD6 iPhone 17". Budgets (owner rule 7): each test ≲ 1 s, suites under
1 minute. Seeded noise from a local SplitMix64; frame times injected, no wall clock.

**Target Platform**: iOS/iPadOS 26+ (app), macOS host, Linux (packages).

**Project Type**: mobile app with SwiftPM packages.

**Performance Goals**: per frame, at most 8 trigger steps, no allocation, no lock (main thread, display
link; never an audio callback).

**Constraints**: Constitution VI (ParameterGraph stays independent of PerformanceControl: the action
enum mirrors MIDI-006's identifiers and the app maps them), VII (not in audio callbacks), X (tests).

**Scale/Scope**: 3 new source files, 4 edited package files, 3 edited app files, 4 new test files.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass: plain Swift. |
| II-V Capture | Not affected. |
| VI Modular boundaries | Pass: trigger in ParameterGraph (no dependencies), persistence in SceneFormat, actions in the app. |
| VII Real-time audio safety | Pass: evaluated on the display-link frame, allocation-free; no audio callback. |
| VIII Upstream fidelity | Not affected. |
| IX Pinned dependencies | No new dependency. |
| X Evidence-based quality | Pass: deterministic unit tests with injected clocks; app test on the simulator; no device claim. |
| Privacy | No new stored key, no network. |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/148-mod-006-threshold-trigger/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/threshold-trigger.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/ParameterGraph/Sources/ParameterGraph/ThresholdTrigger.swift          (new)
Packages/ParameterGraph/Tests/ParameterGraphTests/ThresholdTriggerTests.swift  (new)
Packages/SceneFormat/Sources/SceneFormat/SceneTriggers.swift                   (new)
Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneIssue,SceneValidation,SceneLiveState}.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneTriggerTests.swift            (new)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Coordinators/MIDINoteActionPerformer.swift
Apps/projectM-iOS/Coordinators/AppCoordinator+ThresholdTriggers.swift          (new)
Apps/projectM-iOS/Coordinators/{AppCoordinator,SceneAutosaveCapture,SceneAutosaveCoordinator}.swift
Apps/projectM-iOS/Tests/ThresholdTriggerAppTests.swift                         (new)
```

**Structure Decision**: follow MOD-005's split (pure model in ParameterGraph, persistence in
SceneFormat, an app unit test through `NativeSpectrumHost`).

## Complexity Tracking

None.
