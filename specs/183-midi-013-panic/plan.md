# Implementation Plan: MIDI-013 MIDI Panic

**Branch**: `feature/midi-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/183-midi-013-panic/spec.md`

## Summary

One user command that puts every held trigger key up through the existing release path, resets the shared press
rule, drops queued input and cancels learning, without touching the stored mappings or the show. Same split as
MIDI-001 to MIDI-012: the pure reset in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/`, a thin app
layer.

Package (PerformanceControl):

- `MIDIPressFilter.reset()` (down keys, last-press times and same-batch presses cleared) and `isEmpty` (research
  MIDI-013-D1).
- `MIDINoteRouter.panic(bindings:)`: `releaseAll(bindings:)` (the source-loss path: one `release` per held hold
  binding, ordered) then `filter.reset()`; `isIdle` (D1).
- `MIDINoteAction.panic` (`midi.panic`, trigger only) and `MIDINoteTarget.panic` ("MIDI panic"), appended to
  `MIDINoteTarget.all` (D4).

App:

- `MIDIInputCoordinator.discardPending()`: drains the input ring into a scratch buffer without delivering it (D2).
- `MIDIMappingCoordinator+Panic.swift` (new): `panic()` cancels every learn session, discards queued input, routes
  the router's panic commands through `performNotes` (so `MIDINoteActionPerformer` undoes a hold blackout exactly as
  on release), sets the status and announces "MIDI reset" on the `.midi` lane (D3). The `+Notes` router step runs
  panic when a `midi.panic` binding fires (commands before it are performed, later ones dropped).
- `MIDINoteActionPerformer`: `.panic` is handled by the coordinator; the performer ignores it (D4).
- `MIDIPanicCommand` (new view file `Views/MIDIPanicControls.swift`): the shortcut constants (⌘⇧M, D5), the Settings
  button `MIDIPanicButton` (in `MIDISettingsSection`, after the MIDI Mappings row), the hidden visualizer key command
  `MIDIPanicKeyCommand` (in `VisualizerView.keyCommandLayers` while Settings is closed) and the VoiceOver action on
  the visualizer's tap area while listening is on.
- DEBUG only: `UITestFakeMIDIPanicProbe` in the MIDI section (a "Hold Note" button and a `midiHeldProbe` readout
  "<n> held").
- `scripts/check_status_events.py`: the new coordinator file is checked (announcements through the announcer only).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/panic.md](contracts/panic.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-006/008 router and press rule), SwiftUI. No new package, framework
or network API.

**Storage**: none new. `settings.midi.mappings` is read, never written by panic. No new UserDefaults key.

**Testing**: package `MIDIPanicTests` (router and filter reset, hold releases, fresh press after panic inside the old
30 ms window, idle no-op, `midi.panic` line round trip, Linux shape); app `MIDIPanicCoordinatorTests` (the
acceptance through the stand-in source system: three notes incl. a hold blackout, a CC button, a learn session →
zero gates, empty filter, blackout restored, learn cancelled, stored lines byte-identical, later presses fire; idle
no-op; queued input dropped; `midi.panic` binding; shortcut constants); UI `MIDIPanicUITests` (hold a note, tap
Panic, 0 held; ⌘⇧M; under 30 s).

**Target Platform**: iOS 26.5+ / iPadOS (app); package also macOS host and Linux.

**Performance Goals**: panic is O(bindings ≤ 64) on the main actor, on user action only.

**Constraints**: owner rule 7 test budgets; Xcode 26 type-check budget (small view bodies, typed closures).

**Scale/Scope**: ≤ 64 bound keys.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: SwiftUI `keyboardShortcut`, `accessibilityActions`. |
| VI Modular boundaries | Pass: reset logic in the package; UI and wiring in the app. |
| VII Real-time audio safety | Pass: nothing on the audio path; the MIDI ring is drained on the main actor as today. |
| X Evidence-based quality | Pass: acceptance proven by package and app tests; the physical controller check is a `{device}` task. |
| Accessibility | Pass: button with label and hint, VoiceOver action, announcement on the `.midi` lane, keyboard shortcut. |
| Privacy | Pass: nothing stored, no device identifiers. |

Post-design re-check: unchanged, no violations.

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIPressFilter.swift     (reset, isEmpty)
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteRouter.swift      (panic, isIdle)
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteBinding.swift     (midi.panic)
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIPanicTests.swift        (new)
Apps/projectM-iOS/Coordinators/MIDIInputCoordinator.swift                             (discardPending)
Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Panic.swift                     (new)
Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Notes.swift                     (panic trigger in the router step)
Apps/projectM-iOS/Coordinators/MIDINoteActionPerformer.swift                          (.panic ignored)
Apps/projectM-iOS/Views/MIDIPanicControls.swift                                       (new)
Apps/projectM-iOS/Views/MIDISettingsSection.swift                                     (button, DEBUG probe)
Apps/projectM-iOS/Views/VisualizerView.swift                                          (key command, VO action)
Apps/projectM-iOS/Debug/UITestFakeMIDI.swift                                          (probe)
Apps/projectM-iOS/Tests/MIDIPanicCoordinatorTests.swift                               (new)
Apps/projectM-iOS/UITests/MIDIPanicUITests.swift                                      (new)
scripts/check_status_events.py                                                        (new file checked)
```

## Complexity Tracking

None.
