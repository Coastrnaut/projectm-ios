# Implementation Plan: SHOW-010 Beat Grid

**Branch**: `feature/show-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

**Model (ShowControl, Linux).** `BeatGrid.swift`: `BeatGridTempo` (BPM, period and anchor in whole nanoseconds on the
show timeline, source manual or estimated), `BeatGridTick` (time, beat index from the anchor, bar flag),
`BeatGridPosition` (bar, beat) and `BeatGridMark` (x, bar flag). `BeatGrid.ticks(_:from:to:stride:)` lists the beats
anchor + k × period in a window with integer arithmetic (floor division for times before the anchor), keeps every
`stride`-th beat (1, 4, 8, 16…; bars when k is a multiple of 4) and raises the stride until at most 512 ticks remain
(research D1, D2). `stride(for:duration:width:)` picks the smallest stride whose drawn spacing is ≥ 4 points.
`marks(_:duration:width:inset:)` lays ticks over a track: x = inset + t / duration × (width − 2 × inset).
`position(_:at:)` gives bar and beat (0:00 is in bar 1), `nearestBeat(_:to:)` the closest beat, and
`readoutText`/`accessibilityValue` the row's texts (D3).

**Placement (app).** `ShowBeatGridCoordinator` (main actor; owned lazily by `ShowTransportCoordinator`): reads
SHOW-011's `TempoSnapshot` and the monotonic tempo clock through injected closures. While the show plays it places the
tempo's anchor on the timeline: `timelineNow − (tempoNow − anchor)`, reduced modulo the period; paused or at Standby it
keeps the last placement; with no anchor or none placed yet the grid starts at 0:00 (D4). No storage, no timer: the
row's existing twice-a-second redraw reads it.

**UI.** `ShowScrubBar` draws `BeatGridTicks` (a `Path` of short beat and tall bar lines, hidden from VoiceOver) under
the thumb; the row shows `showBeatGridReadout` ("Bar 3 · Beat 2 · 120 BPM" / "No tempo") beside the position, a
VoiceOver element labelled "Beat grid" with the value "120 BPM, tap tempo, bar 3 beat 2". DEBUG: the readout's
identifier stays the same; the drawn tick count and stride are exposed only with `-uitestBeatGridProbe` as a
zero-size text `showBeatGridProbe` ("ticks 38 stride 4"), for the UI test (D5).

**Acceptance proof.** `BeatGridTests` (package): 120 BPM gives ticks exactly 500,000,000 ns apart over 0–10 s (21
ticks), bars at 0, 2, 4 … 10 s; an anchor at 0.25 s shifts all ticks; windows before the anchor; no tempo → none;
the 512 bound and stride choice; positions and texts; mark x positions for a 20 s timeline 300 points wide.
`ShowBeatGridAcceptanceTests` (app): the coordinator over a real transport on a `ShowManualClock` and an injected tempo
clock: placement while playing, kept while paused, 0:00 without phase; readout "120 BPM, tap tempo, bar 3 beat 2" at
4.5 s; marks at expected x. `ShowBeatGridUITests` (< 30 s): timeline seed + `-uitestTempoEstimate 120:0.9` → readout
value starts "120 BPM, detected, bar", probe shows ticks.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Foundation, SwiftUI; ShowControl, PerformanceControl (`TempoSnapshot`), AudioCore (`MonotonicClock`)
**Storage**: none (no UserDefaults key, no show-file field)
**Testing**: ShowControl package tests (host; Linux in CI); app acceptance tests; one UI test < 30 s on
"SHOW10 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+ app; ShowControl also Linux
**Performance Goals**: ≤ 512 ticks per layout, computed twice a second while the row is on screen; no per-frame work
**Constraints**: type-check budget; short tests (owner rule 7); small edits to shared files (`ShowTimelineRow`,
`ShowTransportCoordinator`, `AppCoordinator+Show`)
**Scale/Scope**: one row, one readout

## Constitution Check

- I (public APIs only): Foundation, SwiftUI `Path`. Pass.
- VI (modular boundaries): grid math in ShowControl (pure, Linux); tempo reading and placement in the app; ShowControl
  gains no dependency (the app converts `TempoSnapshot`). Pass.
- VII (real-time audio safety): reads the published snapshot on the main actor; nothing on the audio thread. Pass.
- VIII (projectM fidelity): no engine change. Pass.
- Privacy / local-first: no network, no stored data. Pass.
- Accessibility: the readout is a labelled element with a spoken value; ticks are decorative and hidden. Pass.
- X (evidence): injected clocks; integer-nanosecond assertions; simulator proves behavior only; `{device}` task open.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ShowControl/Sources/ShowControl/BeatGrid.swift                     # model (new)
Packages/ShowControl/Tests/ShowControlTests/BeatGridTests.swift             # new
Apps/projectM-iOS/Coordinators/ShowBeatGridCoordinator.swift                # new
Apps/projectM-iOS/Coordinators/ShowTransportCoordinator.swift               # lazy `beatGrid` (edit)
Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift                    # tempo wiring (edit)
Apps/projectM-iOS/Views/ShowTimelineRow.swift                               # ticks + readout (edit)
Apps/projectM-iOS/Views/ShowBeatGridTicks.swift                             # new
Apps/projectM-iOS/Tests/ShowBeatGridAcceptanceTests.swift                   # new
Apps/projectM-iOS/UITests/ShowBeatGridUITests.swift                         # new
```

## Complexity Tracking

None.
