# Implementation Plan: SHOW-004 Cue Transition Override

**Branch**: `feature/show-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

`ShowCue` gains an optional `transitionOverride: ShowCueTransition?` (the SCN-007 value type, so the same
validation: type, duration 0…10 s, MOD-004 easing). `show.json` stores it as an optional per-cue object
`transitionOverride` with the same fields as SCN-007's `transition`, written only when set and read leniently
through the existing `StoredTransition` (invalid → dropped, counted in a new `droppedTransitionOverrides`
warning; unknown type → kept, reported as `unknownTransitionOverrideType`). No version bump; shows without
overrides keep their bytes.

`ShowCue.effectiveTransition` (`transitionOverride ?? transition`) is the one rule; `ShowCoordinator.show(_:)`
passes it where it passed `cue.transition`, so every step source (Next, Previous, Go to, SHOW-002 timed advance,
SHOW-003 quantized step, pad, keys, MIDI, OSC, switcher, SCN-012 repaired open) uses it, then
`CueTransitionResolver` applies Reduce Motion and Reduce flashing as before. `ShowCueList.setTransitionOverride`
and `ShowCoordinator.setTransitionOverride` (refused while locked, saves, applies nothing) edit it; Duplicate
Scene passes it to `insert`. The scene document and the cue's SCN-007 `transition` are never written by any of
this (SHOW-004-R4).

Editor: `CueTransitionView` gets a `target` (`.sceneDefault` = SCN-007 as today, `.override` = SHOW-004): with
`.override` the first type choice reads "Use Scene Default", the title "Transition Into This Cue", the footer
names the scene default, and edits call `setTransitionOverride`. `ShowEditorView` adds the context-menu item,
leading swipe "Into" and VoiceOver action, and the row line "Into this cue: <summary>".

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Foundation; SwiftUI in the app; existing ShowControl, ParameterGraph (MappingCurve)
**Storage**: `show.json` (optional per-cue `transitionOverride`); no UserDefaults key
**Testing**: ShowControl package tests (`swift test`, host; Linux in CI); app unit test (acceptance) with a
transition-driver spy and a temporary store; one UI test under 30 s on simulator "SHOW4 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+ app; ShowControl also Linux
**Performance Goals**: none new (one optional lookup per step)
**Constraints**: type-check budget (functions ≤ 300 ms, expressions ≤ 200 ms); short tests (owner rule 7)
**Scale/Scope**: ≤ 256 cues per show (SHOW-001)

## Constitution Check

- I (public APIs only): Foundation and SwiftUI only. Pass.
- VI (modular boundaries): model and file format in ShowControl; the app wires the editor and passes the effective transition. Pass.
- VII (real-time audio safety): no audio-thread work. Pass.
- Privacy / local-first: no network, no new stored key; the override is part of the user's show file. Pass.
- Accessibility (FR-070, ACC-004, ACC-005): context menu, swipe and VoiceOver action; the override is read in the row's VoiceOver value; the sheet reuses SCN-007's accessible slider. Pass.
- Sensory safety (ACC-012, CMP-014-R10): the override goes through `CueTransitionResolver`, so Reduce Motion and Reduce flashing still apply. Pass.
- X (evidence): deterministic package and app tests; the simulator UI test proves behavior only; no device claim.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift       # ShowCue.transitionOverride, effectiveTransition, setTransitionOverride, insert(...)
Packages/ShowControl/Sources/ShowControl/ShowDocument.swift      # transitionOverride field, warnings
Packages/ShowControl/Tests/ShowControlTests/ShowTransitionOverrideTests.swift   # new
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift             # effective transition, setTransitionOverride, duplicate
Apps/projectM-iOS/Views/CueTransitionView.swift                  # target: scene default / override
Apps/projectM-iOS/Views/ShowEditorView.swift                     # menu, swipe, VoiceOver action, row line
Apps/projectM-iOS/Tests/CueTransitionOverrideAcceptanceTests.swift   # new (acceptance)
Apps/projectM-iOS/UITests/CueTransitionOverrideUITests.swift     # new (one test)
```

**Structure Decision**: extend the existing ShowControl model and the SCN-007 sheet; no new package, no new file
for the model (the override reuses `ShowCueTransition`).

## Complexity Tracking

None.
