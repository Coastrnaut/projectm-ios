# Implementation Plan: MIDI-010 MIDI Clock Receive

**Branch**: `feature/midi-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/273-midi-010-midi-clock-receive/spec.md`

## Summary

With "Follow MIDI clock" on, the show's tempo follows an external 24-PPQN clock. Same split as MIDI-002 to MIDI-008:
a pure, Linux-testable model in `Packages/PerformanceControl/Sources/PerformanceControl/` and a thin app layer.
MIDI-002's decoders already produce `.clock`, `.start`, `.continue`, `.stop` and `.songPosition` events with
timestamps (research MIDI-010-D1); only the clock pulses' timestamps are missing on the main actor.

Pure model:

- `MIDI/MIDIClockLane.swift` (new): a preallocated single-producer, single-consumer queue of clock-relevant events
  (clock, start, continue, stop, song position), enabled only while someone follows the clock (research D2).
- `MIDI/MIDIEventRing.swift`: one hook — `push` copies clock-relevant events into `clockLane` (before the
  existing counting); `discardAll` also clears the lane. Nothing else in the shared input changes.
- `MIDI/MIDIClockTracker.swift` (new): the tracker (research D3–D6): least-squares BPM over up to 96 pulses, lock after
  24, outliers and dropped pulses, window cut on a > 2 % change, 0.5 s timeout, Stop, 20–300 BPM, positions and beat
  anchor. Produces `MIDIClockTempo` (BPM, anchor) and a `MIDIClockStatus`.
- `TempoSnapshot.swift`: `TempoOrigin.midiClock`. `TempoSource.swift`: `updateMIDIClock(_:)`; the snapshot puts a
  clock first (research D7). `TempoConfidenceIndicator.swift`: `TempoReadout.midiClock(bpm:)`.

App:

- `Coordinators/MIDIClockCoordinator.swift` (new): owns the setting `settings.midi.followClock`, registers the input
  client "midiClock" while following, drains `clockLane` on each input batch, checks the timeout on a 100 ms task
  (injected clock), and hands `MIDIClockTempo?` to `TempoCoordinator.updateMIDIClock`. Status texts are static.
- `TempoCoordinator.swift`: `updateMIDIClock(_:)`; a tap while the clock sets the tempo announces "MIDI clock is setting
  the tempo"; texts for the new readout case.
- Readout switches: `SceneHUD.swift`, `SlideshowCoordinator.swift`, `ShowBeatGridCoordinator.swift` (the clock counts
  as manual for the grid and the slideshow).
- `Views/MIDIClockSettingsRows.swift` (new) placed by one line in `MIDISettingsSection.swift`.
- `AppCoordinator.swift`: create the coordinator after `tempo` (a few lines); the UI-test reset removes the key.
- DEBUG: `UITestFakeMIDI` gets a "Fake Clock 120" toggle that sends real-time pulses on a 10 ms timer.
- Key lists: `LibrarySettingsPolicy.excludedKeys`, `LibraryErasePolicy.settingsCategoryKeys`,
  `ALLOWED_KEYS`, `LibraryBackupAppTests` (outside `AppSettings.allKeys`, so `SettingsTests` is unchanged).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/midi-clock.md](contracts/midi-clock.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-002 input, SHOW-011 tempo source). No new package or framework; no
networking.

**Storage**: one new Bool `settings.midi.followClock` (absent = off), owned by `MIDIClockCoordinator`; excluded from
the FILE-005 backup (this device's MIDI setup, like `settings.midi.enabled`), erased with Settings (FILE-011).

**Testing**: package `MIDIClockTests` (tracker acceptance S1–S4, lane and ring hook, UMP and byte decoding,
tempo-source priority); app `MIDIClockCoordinatorTests` (fake source → `TempoCoordinator.snapshot`, toggle on/off,
tap notice); UI `MIDIClockUITests`; `LibraryBackupAppTests`, existing tempo tests.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (pure model).

**Project Type**: iOS app plus SwiftPM packages.

**Performance Goals**: receive thread: one extra branch and, while enabled, one 16-byte store per clock event; main
actor: O(pulses) per batch (≤ 4 per 33 ms at 300 BPM) with a 96-sample fit (≤ 96 multiply-adds per pulse).

**Constraints**: real-time safety on the receive thread (Constitution VII spirit, MIDI-002-R4); local MIDI only
(ADR-0038); no wall-clock assertions in tests.

**Scale/Scope**: one clock follower; ~600 lines of source, ~500 of tests.

## Constitution Check

| Principle | Status |
|---|---|
| I/II/III/IV/V capture and labelling | Not touched. |
| VI Modular boundaries | Pure model in the package; the app only wires and shows. Pass. |
| VII Real-time safety | The receive-thread change is a preallocated atomic SPSC store, no allocation, lock or log. Pass. |
| VIII Upstream projectM fidelity | Nothing reaches projectM (tempo consumers only). Pass. |
| IX Pinned dependencies | None added. Pass. |
| X Evidence | Simulator results are not device evidence; the physical clock check is `{device}` MIDI-010-T12. Pass. |
| Privacy | One Bool; no message, time or device stored or logged. Pass. |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/273-midi-010-midi-clock-receive/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/midi-clock.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/PerformanceControl/Sources/PerformanceControl/
├── MIDI/MIDIClockLane.swift          (new)
├── MIDI/MIDIClockTracker.swift       (new)
├── MIDI/MIDIEventRing.swift          (one hook)
├── TempoSnapshot.swift, TempoSource.swift, TempoConfidenceIndicator.swift
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIClockTests.swift (new)
Apps/projectM-iOS/Coordinators/MIDIClockCoordinator.swift (new), TempoCoordinator.swift, AppCoordinator.swift,
    SlideshowCoordinator.swift, ShowBeatGridCoordinator.swift
Apps/projectM-iOS/Views/MIDIClockSettingsRows.swift (new), MIDISettingsSection.swift, SceneHUD.swift
Apps/projectM-iOS/Debug/UITestFakeMIDI.swift
Apps/projectM-iOS/Tests/MIDIClockCoordinatorTests.swift (new), LibraryBackupAppTests.swift
Apps/projectM-iOS/UITests/MIDIClockUITests.swift (new)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, LibraryErasePolicy.swift
scripts/run_device_tests.py
```

## Complexity Tracking

No violations.
