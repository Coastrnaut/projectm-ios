# Implementation Plan: MIDI-006 MIDI Note Triggers

**Branch**: `feature/midi-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/143-midi-006-note-triggers/spec.md`

## Summary

Notes drive four actions (Next cue, Previous cue, Black out toggle, Black out while held). Same split as
MIDI-001 to MIDI-004: a pure, Linux-testable model in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/`
and a thin app layer.

Pure model (`MIDI/`):

- `MIDIEvent.noteEdge` (`MIDINoteEdge.on` / `.off` / nil): the single normalisation point; velocity-0 note on
  is `.off` even if an event was built by hand (research MIDI-006-D1). Parsers keep building note off for
  velocity 0 through `MIDIEvent.channelVoice`.
- `MIDINoteBinding.swift` (new): `MIDINoteAction` (`cue.next`, `cue.previous`, `blackout`), `MIDINoteMode`
  (trigger, hold), `MIDINoteTarget` (action + mode; the four learnable targets), `MIDINoteBinding` (key +
  target + kept segments; the `note:` line codec), `MIDINoteBindingList` (one note per target and one target
  per note, at most 64, unreadable `note:` lines kept verbatim).
- `MIDINoteRouter.swift` (new): keys down; `route(_:bindings:)` → `[MIDINoteCommand]` (fire / engage /
  release); edge-only, at most one fire per binding per batch, panic (CC 120/123 per channel, System Reset),
  `releaseAll(bindings:)`, `release(keys:bindings:)` (research MIDI-006-D2, D3).
- `MIDILearnSession.handle(_:now:isEligible:)` and `MIDILearnEligibility.isNoteEligible(_:)`; the existing
  `handle(_:now:)` is unchanged in behaviour (CC learn).

App:

- `MIDIMappingCoordinator`: owns `noteBindings`, a second learn session for notes (one session at a time),
  the router and `noteActions`; stores note lines after CC lines under the same key; releases held notes when
  the input stops or a listed input disappears and when a held binding is deleted or replaced; Undo covers
  both lists. Note logic lives in a new extension file `MIDIMappingCoordinator+Notes.swift`.
- `MIDINoteActionPerformer` (new, `Coordinators/MIDINoteActionPerformer.swift`): maps commands to
  `ShowCoordinator.next()/previous()` and OUT-010 blackout calls, remembering whether a hold blacked out.
- `AppCoordinator`: one line wiring the performer.
- `MIDIMappingsView`: a "Note triggers" section; `UITests/MIDINoteTriggersUITests.swift`.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/note-triggers.md](contracts/note-triggers.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-002 parsers, MIDI-003 learn/bindings), ShowControl via the
app's `ShowCoordinator`, the app's `ExternalDisplayCoordinator` (OUT-010). No new package or framework; no
networking.

**Storage**: unchanged key `settings.midi.mappings` (`[String]`); new `note:` lines after the `cc:` lines.

**Testing**: package `MIDINoteTriggerTests` (edge normalisation, parser and UMP equivalence, codec, list,
router) on the host and the Linux shape; app `MIDINoteTriggerCoordinatorTests` (fake MIDI source end to end,
learn, stuck notes, storage next to CC lines, performer); UI `MIDINoteTriggersUITests`; script tests.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (pure model).

**Project Type**: iOS app plus SwiftPM packages.

**Performance Goals**: O(events + bindings) per batch at ≤ 30 Hz on the main actor; the MIDI thread is
unchanged.

**Constraints**: public APIs only; explicit closure types; typed string steps; no C stdio globals; no
wall-clock assertions; unit tests about 1-2 s, UI test under 30 s. Parallel work: `AppCoordinator.swift`
gets one wiring line; `SettingsView.swift`, `Compositor.swift` and `VisualizerView.swift` are not touched.

**Scale/Scope**: 2 new and 2 edited package sources, 1 package test file; 1 coordinator edit plus 1 extension
file, 1 performer file, 1 view edit, 1 app test file, 1 UI test file, 1 script list line.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | No new framework | Pass |
| VI Modular boundaries | Codec and routing pure in PerformanceControl; coordinator owns state; performer calls existing actions | Pass |
| VII Real-time safety | MIDI thread unchanged; routing runs on the main actor at drain rate | Pass |
| VIII Upstream fidelity | Nothing feeds projectM | Pass |
| X Evidence | Fake MIDI on the Mac; a physical controller is the `{device}` task | Pass |
| Privacy | Note lines hold channel, note, action and mode only | Pass |
| No networking (FR-068) | No network code | Pass |
| Accessibility (ACC-004, ACC-011) | Learn announces on `.midi`; actions keep their own announcement paths | Pass |
| Sensory safety (OUT-010, ACC-012) | Blackout uses OUT-010's calls, so restore keeps its fade and spacing | Pass |
| Permissions (FILE-013) | No new usage key | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/143-midi-006-note-triggers/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/note-triggers.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/
├── MIDIEvent.swift            # noteEdge
├── MIDILearnSession.swift     # handle(_:now:isEligible:), isNoteEligible
├── MIDINoteBinding.swift      # new: action, mode, target, binding, list
└── MIDINoteRouter.swift       # new: edges → commands
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDINoteTriggerTests.swift   # new
Apps/projectM-iOS/
├── Coordinators/MIDIMappingCoordinator.swift          # note state, save, undo, receive
├── Coordinators/MIDIMappingCoordinator+Notes.swift    # new: note learn, rows, release
├── Coordinators/MIDINoteActionPerformer.swift         # new
├── Coordinators/AppCoordinator.swift                  # one wiring line
├── Views/MIDIMappingsView.swift                       # Note triggers section
├── Tests/MIDINoteTriggerCoordinatorTests.swift        # new
└── UITests/MIDINoteTriggersUITests.swift              # new
scripts/check_status_events.py
```

**Structure Decision**: extend MIDI-003's files; no new package.

## Complexity Tracking

None.
