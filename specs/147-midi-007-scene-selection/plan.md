# Implementation Plan: MIDI-007 MIDI Scene Selection

**Branch**: `feature/midi-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/147-midi-007-scene-selection/spec.md`

## Summary

Program changes and notes select show scenes. Same split as MIDI-003 to MIDI-006: a pure, Linux-testable model in
`Packages/PerformanceControl/Sources/PerformanceControl/MIDI/` and a thin app layer.

Pure model (`MIDI/`):

- `MIDISceneBinding.swift` (new): `MIDISceneBinding` (key = program change or note on key, scene ID, kept segments;
  the `pc:` and `note:…=cue.go:` line codec), `MIDIProgramCueMode` (off, any channel, one channel; the
  `pc:<ch|*>:*=cue.position` line) and `MIDISceneBindingList` (one scene per key, one key per scene, at most 128,
  unreadable scene lines kept verbatim, the mode).
- `MIDISceneRouter.swift` (new): `route(_:list:)` → the newest `MIDISceneCommand` of a batch (`.scene(id)` or
  `.cue(index)`), explicit mappings before the position mode (research MIDI-007-D2, D3).
- `MIDINoteBindingList` skips `note:…=cue.go:` lines (the scene list owns them now).
- `MIDILearnEligibility.isSceneEligible(_:)`: a program change or a note on with velocity > 0.

App:

- `MIDIMappingCoordinator`: owns `sceneBindings`, a third learn session (scene IDs; one session at a time), stores
  scene lines after the note lines, routes scenes after notes, Undo covers all three lists. Scene logic in a new
  extension file `MIDIMappingCoordinator+Scenes.swift`. Note learn (MIDI-006) frees a key a scene used and the
  reverse.
- `MIDISceneActionPerformer` (new): debounce (current scene or cue), "Scene not found." / "Cue n not found." on
  the `.midi` lane, `ShowCoordinator.goToScene(_:)` / `go(to:)` otherwise.
- `AppCoordinator+Show.swift`: wiring next to MIDI-006's performer (no edit of `AppCoordinator.swift`).
- `MIDIMappingsView`: a "Scene triggers" section and the picker; `MIDISceneAssignView` (new sheet);
  `ShowEditorView`: "Assign MIDI…" (context menu, swipe, VoiceOver action); `SettingsView`: one argument passed.
- DEBUG: the fake MIDI panel gets "Send Program" (program 5, channel 1) and the assign sheet shows the panel.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/scene-selection.md](contracts/scene-selection.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-002 parsers, MIDI-003 learn, MIDI-006 notes), ShowControl via
the app's `ShowCoordinator`. No new package or framework; no networking.

**Storage**: unchanged key `settings.midi.mappings` (`[String]`); scene lines after the `note:` lines.

**Testing**: package `MIDISceneSelectionTests` (codec, list, router, eligibility; host and Linux shape); app
`MIDISceneSelectionCoordinatorTests` (fake MIDI source → real `ShowCoordinator` over a temporary store, byte-identical
mappings, learn, performer); UI `MIDISceneSelectionUITests`; MIDI-006 tests unchanged except the one fixture that used
`cue.go:` as an "unknown" action.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (pure model).

**Project Type**: iOS app plus SwiftPM packages.

**Performance Goals**: O(events + mappings) per batch at ≤ 30 Hz on the main actor; at most one scene applied per
batch; the MIDI thread is unchanged.

**Constraints**: public APIs only; explicit closure types; typed string steps; no C stdio globals; no wall-clock
assertions; unit tests about 1-2 s, UI test under 30 s. Parallel work: `AppCoordinator.swift`, `Compositor.swift`
and `VisualizerView.swift` untouched; `SettingsView.swift` gets one argument.

**Scale/Scope**: 2 new and 3 edited package sources, 1 package test file; coordinator edit plus 1 extension, 1
performer, 1 new view, 3 view edits, 1 DEBUG edit, 1 app test file, 1 UI test file.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | No new framework | Pass |
| VI Modular boundaries | Codec and routing pure in PerformanceControl; coordinator owns state; performer calls SHOW-001's Go to Cue | Pass |
| VII Real-time safety | MIDI thread unchanged; routing on the main actor at drain rate | Pass |
| VIII Upstream fidelity | Nothing feeds projectM | Pass |
| X Evidence | Fake MIDI on the Mac; a physical controller is the `{device}` task | Pass |
| Privacy | Scene lines hold channel, number and a local scene ID only | Pass |
| No networking (FR-068) | No network code | Pass |
| Accessibility (ACC-004) | Learn and "not found" on `.midi`; cue steps on `.cue`; VoiceOver action "Assign MIDI" | Pass |
| Permissions (FILE-013) | No new usage key; no new UserDefaults key | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/147-midi-007-scene-selection/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/scene-selection.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/
├── MIDISceneBinding.swift     # new: binding, mode, list
├── MIDISceneRouter.swift      # new: batch → newest scene command
├── MIDINoteBinding.swift      # skip cue.go: lines
└── MIDILearnSession.swift     # isSceneEligible
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDISceneSelectionTests.swift   # new
Apps/projectM-iOS/
├── Coordinators/MIDIMappingCoordinator.swift          # scene state, save, undo, receive
├── Coordinators/MIDIMappingCoordinator+Scenes.swift   # new: scene learn, rows, routing
├── Coordinators/MIDIMappingCoordinator+Notes.swift    # a note learn frees a scene key
├── Coordinators/MIDISceneActionPerformer.swift        # new
├── Coordinators/AppCoordinator+Show.swift             # wiring
├── Views/MIDIMappingsView.swift                       # Scene triggers section
├── Views/MIDISceneAssignView.swift                    # new: Assign MIDI sheet
├── Views/ShowEditorView.swift                         # Assign MIDI…
├── Views/SettingsView.swift                           # pass the mapping coordinator
├── Debug/UITestFakeMIDI.swift                         # Send Program
├── Tests/MIDISceneSelectionCoordinatorTests.swift     # new
└── UITests/MIDISceneSelectionUITests.swift            # new
```

**Structure Decision**: extend the MIDI-003/006 files; no new package.

## Complexity Tracking

None.
