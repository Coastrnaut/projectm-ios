# Implementation Plan: MIDI-008 MIDI Transport Mapping

**Branch**: `feature/midi-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/157-midi-008-transport/spec.md`

## Summary

Buttons drive Play/Pause, Play, Pause, Next cue and blackout, and each physical press fires one action however often
the packet repeats. Same split as MIDI-003 to MIDI-007: a pure, Linux-testable model in
`Packages/PerformanceControl/Sources/PerformanceControl/MIDI/` and a thin app layer. MIDI-006's trigger list, router,
learn session, rows and performer are generalised rather than duplicated (research MIDI-008-D1).

Pure model (`MIDI/`):

- `MIDIPressFilter.swift` (new): the one normalisation point (research MIDI-008-D2). `MIDIPressFilter.rawEdge(_:)`
  turns a note (via MIDI-006's `noteEdge`), a CC (≥ 64 press, < 64 release; controllers 0–119) or a real-time
  Start/Continue/Stop (a momentary press) into a trigger key and an edge; `accept` applies the down state, the
  same-batch rule and the 30 ms timestamp window. `MIDIEvent.triggerKey` gives the learnable key.
- `MIDINoteBinding.swift`: three transport actions (`transport.toggle`, `transport.play`, `transport.pause`); a binding's
  key may be a note, a CC button (`ccbtn:`) or real-time (`rt:start`, `rt:stop`); the list reads all three tags.
- `MIDINoteRouter.swift`: its private down set is replaced by a `MIDIPressFilter`, so notes, CC buttons and real-time
  share one rule; panic handling (CC 120/123, Reset) is unchanged.
- `MIDILearnSession.swift`: `MIDILearnEligibility.isTriggerEligible(_:allowsRealTime:)`.

App:

- `MIDINoteActionPerformer`: Play/Pause, Play, Pause through injected `isPaused`/`setPaused`.
- `AppCoordinator.swift`: one small method `setPausedQuietly(_:)` (the controls' Pause without revealing the controls;
  acts only while the visualizer is shown) — `userPaused` is private to that file. Wiring in `AppCoordinator+Show.swift`.
- `MIDIMappingCoordinator+Notes.swift`: trigger learn accepts note, CC button, real-time (not for the hold row); the
  learned press is registered in the filter (its copies fire nothing); a CC learned as a button leaves the MIDI-003
  list and the reverse in `MIDIMappingCoordinator.swift`; texts for CC and real-time sources.
- `MIDIMappingsView`: "Note triggers" becomes "Transport" (same row views and identifiers).
- DEBUG: the fake MIDI panel gets "Send CC Button" (CC 20 = 127 then 0, channel 1).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/transport.md](contracts/transport.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-002 parsers, MIDI-003 learn, MIDI-006 triggers). No new package or
framework; no networking.

**Storage**: unchanged key `settings.midi.mappings` (`[String]`); `ccbtn:` and `rt:` lines among the trigger lines,
after the `cc:` lines and before MIDI-007's scene lines.

**Testing**: package `MIDITransportTests` (filter rules, CC hysteresis, codec round-trip, mixed lists, router
acceptance for each source and pattern; host and Linux shape); app `MIDITransportCoordinatorTests` (fake MIDI source
→ coordinator → performer: dedup patterns, play/pause, learn for CC and real-time, CC exclusivity); UI
`MIDITransportUITests`. Existing MIDI-006 tests change only where the row list grew.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (pure model).

**Project Type**: iOS app plus SwiftPM packages.

**Performance Goals**: O(events × log bindings) per batch at ≤ 30 Hz on the main actor; filter state bounded by bound
keys; the MIDI thread is unchanged.

**Constraints**: public APIs only; explicit closure types; typed string steps; no C stdio globals; no wall-clock
assertions (message timestamps are injected); unit tests about 1-2 s, UI test under 30 s. `AppCoordinator.swift` gets
one method; `SettingsView.swift`, `Compositor.swift`, `VisualizerView.swift` untouched.

**Scale/Scope**: 1 new and 4 edited package sources, 1 package test file; 4 coordinator/performer edits, 1 view edit,
1 DEBUG edit, 1 app test file, 1 UI test file.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | No new framework | Pass |
| VI Modular boundaries | Filter, codec and routing pure in PerformanceControl; coordinator owns state; performer calls existing app actions | Pass |
| VII Real-time safety | MIDI thread unchanged; routing on the main actor at drain rate | Pass |
| VIII Upstream fidelity | Nothing feeds projectM | Pass |
| X Evidence | Fake MIDI on the Mac; a physical controller is the `{device}` task | Pass |
| Privacy | Lines hold source kind, channel, number and an action only | Pass |
| No networking (FR-068) | No network code | Pass |
| Accessibility (ACC-004) | Learn on `.midi`; pause on `.playback`; cues on `.cue` | Pass |
| Permissions (FILE-013) | No new usage key; no new UserDefaults key | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/157-midi-008-transport/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/transport.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/
├── MIDIPressFilter.swift      # new: the shared press rule
├── MIDINoteBinding.swift      # transport actions; ccbtn:/rt: keys
├── MIDINoteRouter.swift       # uses the filter
└── MIDILearnSession.swift     # isTriggerEligible
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDITransportTests.swift   # new
Apps/projectM-iOS/
├── Coordinators/AppCoordinator.swift                  # setPausedQuietly (one method)
├── Coordinators/AppCoordinator+Show.swift             # wiring
├── Coordinators/MIDINoteActionPerformer.swift         # transport actions
├── Coordinators/MIDIMappingCoordinator.swift          # CC learn frees a button
├── Coordinators/MIDIMappingCoordinator+Notes.swift    # trigger learn, texts, exclusivity
├── Views/MIDIMappingsView.swift                       # Transport section
├── Debug/UITestFakeMIDI.swift                         # Send CC Button
├── Tests/MIDITransportCoordinatorTests.swift          # new
└── UITests/MIDITransportUITests.swift                 # new
```

**Structure Decision**: extend the MIDI-006 files; no new package.

## Complexity Tracking

None.
