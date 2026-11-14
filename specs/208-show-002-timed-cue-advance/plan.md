# Implementation Plan: SHOW-002 Timed Cue Advance

**Branch**: `feature/show-002` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A per-cue optional dwell (`ShowCueDwell`, whole seconds 1…3600) on `ShowCue`, stored in `show.json` as an
optional cue field `advanceAfter` (written only when set, read leniently with a `droppedDwells` warning; no
version bump). A pure value-type engine, `ShowAdvanceTimeline` (ShowControl, Foundation only, Linux), holds the
pending advance as idle, running (cue ID, deadline) or held (cue ID, remaining), all in `Duration` on an
injected monotonic clock (`ShowMonotonicClock`: `ShowContinuousClock` in the app, `ShowManualClock` in tests).
`ShowTimedAdvance.tick` combines it with a `ShowCueList` for the pure acceptance test: when due, it calls
`list.next()` once and restarts the timeline from the tick's time (research SHOW-002-D2: a jump fires once).

In the app, `ShowAutoAdvanceCoordinator` (main actor, `@Observable`) owns the timeline and the clock. It
listens to `ShowCoordinator.cueStarted` (called from the single `perform` step path and from a dwell edit on the
active cue), polls the hold closure (pause, blackout not live, repair report pending, app inactive) and, while a
countdown exists, runs a 4 Hz task that ticks: when due it calls `show.next()` (the same path as a manual Next,
so transitions, SCN-012 repair, MOD-017 queued changes and the cue announcement all apply). It publishes
`countdown` (whole seconds remaining, rounded up, and whether held) for the cue row and the performance pad.

Editor: "Advance After…" per cue (context menu, swipe, VoiceOver action) opens `CueDwellView` (a picker of the
clarified presets); `ShowCoordinator.setDwell` is refused while the scene is locked.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Foundation (`ContinuousClock`, `Duration`); SwiftUI, Observation in the app
**Storage**: `show.json` (optional per-cue `advanceAfter`); no UserDefaults key
**Testing**: ShowControl package tests (`swift test`, host; Linux in CI); app unit tests for the coordinator with a manual clock; one UI test under 30 s on simulator "SHOW2 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+; package also macOS 15 and Linux
**Performance Goals**: the 4 Hz tick runs only while a countdown exists (idle shows wake nothing)
**Constraints**: no wall-clock time; no networking; owner rule 7 budgets; Xcode 26 type-check budget; small edits in AppCoordinator, SettingsView, VisualizerView, ShowEditorView

## Constitution Check

- I (public APIs only): Foundation and SwiftUI only. Pass.
- VI (modular boundaries): the engine is pure and in the ShowControl package; the app only wires clocks and holds. Pass.
- VII (real-time audio safety): no audio-thread work. Pass.
- Privacy / local-first: no network, no new stored key; the dwell is part of the user's show file. Pass.
- Accessibility (FR-070, ACC-004): countdown in the VoiceOver value; announcements unchanged (cue lane). Pass.
- Sensory safety: a clock jump never causes a burst of scene changes (one advance, D2). Pass.
- X (evidence): deterministic tests with an injected clock; simulator UI test proves behavior only; no device claim.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ShowControl/Sources/ShowControl/ShowCueDwell.swift          # new: dwell value, presets, text
Packages/ShowControl/Sources/ShowControl/ShowAdvanceTimeline.swift   # new: clocks, timeline engine, ShowTimedAdvance
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift           # ShowCue.dwell; setDwell; insert carries dwell
Packages/ShowControl/Sources/ShowControl/ShowDocument.swift          # advanceAfter field, droppedDwells warning
Packages/ShowControl/Tests/ShowControlTests/ShowAdvanceTimelineTests.swift  # engine + acceptance (S1-S4)
Packages/ShowControl/Tests/ShowControlTests/ShowDwellDocumentTests.swift    # file round trip, lenient read (S5)
Apps/projectM-iOS/Coordinators/ShowAutoAdvanceCoordinator.swift      # new: app driver
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                 # cueStarted hook, setDwell, duplicate keeps dwell
Apps/projectM-iOS/Coordinators/AppCoordinator.swift (+Show)          # owns the driver, wires holds
Apps/projectM-iOS/Views/CueDwellView.swift                           # new: the picker sheet
Apps/projectM-iOS/Views/ShowEditorView.swift                         # Advance After… entry points, row caption
Apps/projectM-iOS/Views/ShowControls.swift, PerformancePad.swift     # countdown text
Apps/projectM-iOS/Tests/ShowAutoAdvanceCoordinatorTests.swift        # app acceptance with manual clock
Apps/projectM-iOS/UITests/ShowAutoAdvanceUITests.swift               # S6
Apps/projectM-iOS/Debug/UITestShowFixture.swift                      # optional dwell for the seeded show
```

**Structure Decision**: engine in the existing ShowControl package (already in CI's `PKGS_LIBRARY`); no new package.

## Complexity Tracking

None.
