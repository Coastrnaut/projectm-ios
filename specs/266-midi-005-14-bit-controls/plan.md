# Implementation Plan: MIDI-005 MIDI 14-bit Controls

**Branch**: `feature/midi-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/266-midi-005-14-bit-controls/spec.md`

## Summary

A `cc:` mapping on controller 0–31 can be marked 14-bit (`;hires=1`). Its coarse controller n and fine controller n+32
combine into (MSB × 128 + LSB) / 16383, which then goes through MIDI-004's Invert and curve and the parameter range as
before. Learn marks the flag when the fine controller follows the learning message; the options screen has a manual
switch. Same split as MIDI-001 to MIDI-013: pure logic in
`Packages/PerformanceControl/Sources/PerformanceControl/MIDI/`, a thin app layer.

Package (PerformanceControl):

- `MIDIMappingOptions.highResolution` (`hires=1` segment after `curve=` and `invert=1`; summary ", 14-bit") (research
  MIDI-005-D1).
- New `MIDIHighResolution.swift`: `MIDIHighResolution` (controller rules and the 14-bit value),
  `MIDIHighResolutionTracker` (pair state, fixed 16 × 32 storage, D2, D3) and `MIDIHighResolutionLearnWatch` (the
  500 ms detection window on an injected clock, D4).
- `MIDIControlBinding.isHighResolution` (flag and controller 0–31).
- `MIDIBindingValues.values(for:bindings:registry:skipping:tracker:)`: the stateful variant (coarse and fine routing);
  the existing overload keeps its behaviour for 7-bit mappings.

App:

- `MIDIMappingCoordinator`: two stored properties (tracker, learn watch); `receive` uses the stateful values call and
  the watch; `bind` arms the watch.
- New `MIDIMappingCoordinator+HighResolution.swift`: `canUseHighResolution(for:)`, `setHighResolution(_:for:)`,
  `armHighResolutionWatch(_:target:)`, `detectHighResolution(in:)` (announcements on the `.midi` lane, D5).
- `MIDIMappingOptionsView`: a `MIDIHighResolutionSection` with the "14-bit control" switch (`midiHighResolution`),
  only for controllers 0–31.
- `scripts/check_status_events.py`: the new coordinator file is checked.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/high-resolution.md](contracts/high-resolution.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-002 events, MIDI-003 bindings, MIDI-004 options), ParameterGraph,
SwiftUI. No new package, framework or network API.

**Storage**: the existing `settings.midi.mappings` lines gain an optional `hires=1` segment. No new UserDefaults key.

**Testing**: package `MIDIHighResolutionTests` (the row's acceptance values, coarse then several fine, a new coarse
resets the fine part, 7-bit fallback, fine before coarse, other channel, learn watch, option segments, curve on the
14-bit value, profile round trip); app `MIDIHighResolutionCoordinatorTests` (learn detects the pair, single controller
stays 7-bit, fine resolution in the live value, the switch saves and announces); UI `MIDIHighResolutionUITests` (turn
the switch on, row summary ", 14-bit"; under 30 s).

**Target Platform**: iOS 26.5+ / iPadOS (app); package also macOS host and Linux.

**Performance Goals**: per message O(1) pair update plus the existing O(bindings ≤ 64) lookup; no allocation in the
tracker.

**Constraints**: owner rule 7 test budgets; Xcode 26 type-check budget.

**Scale/Scope**: 16 channels × 32 coarse controllers of pair state.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: no new API. |
| VI Modular boundaries | Pass: pairing logic in the package; UI and wiring in the app. |
| VII Real-time audio safety | Pass: nothing on the audio path; MIDI batches are handled on the main actor as today. |
| X Evidence-based quality | Pass: acceptance proven by package and app tests; a physical 14-bit controller is a `{device}` task. |
| Accessibility | Pass: a labelled switch with a footer, announcements on the `.midi` lane. |
| Privacy | Pass: one more option segment on an existing line; no device identifiers. |

Post-design re-check: unchanged, no violations.

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIHighResolution.swift        (new)
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIMappingOptions.swift        (highResolution)
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIControlBinding.swift        (isHighResolution)
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIBindingValues.swift         (stateful values)
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIHighResolutionTests.swift     (new)
Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift                                 (properties, receive, bind)
Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+HighResolution.swift                  (new)
Apps/projectM-iOS/Views/MIDIMappingOptionsView.swift                                        (switch)
Apps/projectM-iOS/Tests/MIDIHighResolutionCoordinatorTests.swift                            (new)
Apps/projectM-iOS/UITests/MIDIHighResolutionUITests.swift                                   (new)
scripts/check_status_events.py                                                              (new file checked)
```

## Complexity Tracking

None.
