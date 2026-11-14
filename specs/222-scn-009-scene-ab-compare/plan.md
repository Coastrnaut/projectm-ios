# Implementation Plan: SCN-009 Scene A/B Compare

**Branch**: `feature/scn-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

One main-actor model, `SceneCompareCoordinator`, owns a Compare session: the pre-Compare inputs (SCN-010's
`SceneInputs`) and parameter values, side A (Current scene or a snapshot), side B (a snapshot) and the shown side.
A side's values are the pre-Compare values overlaid with the snapshot's usable values (SCN-008's
`SceneSnapshotRecallPlan`), so the toggle reaches exactly two states. The toggle writes only differing values
through the snapshot coordinator's Settings targets (a cut: no crossfade, never quantized; research SCN-009-D3).

Nothing is saved while comparing (research SCN-009-D1): starting flushes any pending autosave edit, then
`SceneAutosaveCoordinator.suspend()` makes every commit trigger (debounce, Settings closing, background, terminate)
write nothing, and `SceneHistoryCoordinator.suspend()` records nothing and refuses undo/redo. Cancel restores the
pre-Compare inputs through the history's `apply` (the Settings path), then both resume against the pre-Compare
inputs, so an unchanged scene writes nothing. Keep sets the side, resumes, commits once (`commitNow`) and records
one step "Keep <name>". A cue, Reopen or media replacement restarts the history; while suspended that ends
Compare without restoring (R11). The lock refuses start, the toggle and Keep; Cancel always works.

UI: Settings › Visual gets a "Compare A/B…" row under the snapshot rows that opens a setup sheet (A, B, Start
Compare); the visualizer's top status stack gets a "Comparing A/B" bar (segmented A | B toggle, Done → Keep A /
Keep B / Cancel Compare / Keep Comparing).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: SwiftUI, Observation; SceneFormat (`SceneSnapshot`, `SceneSnapshotRecallPlan`), ParameterGraph; app coordinators SCN-002, SCN-008, SCN-010, SCN-015; `AccessibilityAnnouncer` (library lane)
**Storage**: none (session state in memory; R10)
**Testing**: XCTest app unit tests with real stores in a temporary folder; one UI test under 30 s on simulator "SCN9 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+
**Performance Goals**: a switch writes at most seven values on the main actor in the tap's turn
**Constraints**: no scene format change, no new UserDefaults key, no networking; owner rule 7 budgets; Xcode 26 type-check budget; small edits in shared files (AppCoordinator, VisualizerView)

## Constitution Check

- I (public APIs only): SwiftUI and Observation only. Pass.
- Privacy and local-first: nothing stored, nothing sent. Pass.
- VI (modular boundaries): Compare is one coordinator; autosave and history each gain a suspend/resume pair; the snapshot coordinator keeps its writes. Pass.
- VII (real-time audio safety): main actor only; nothing on the audio or render threads. Pass.
- Accessibility (ACC-004): label/value on the toggle, announcements on the library lane. Pass.
- X (evidence): simulator tests prove behavior only; no device claim.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Apps/projectM-iOS/Coordinators/SceneCompareCoordinator.swift        # new: session, toggle, keep, cancel, abandon
Apps/projectM-iOS/Coordinators/AppCoordinator+SceneCompare.swift    # new: wiring (shared with the tests)
Apps/projectM-iOS/Coordinators/SceneAutosaveCoordinator.swift       # suspend() / resume(from:)
Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift        # suspend() / resume(), restart while suspended
Apps/projectM-iOS/Coordinators/SceneSnapshotCoordinator.swift       # edits refused while comparing; `compare` link
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                 # owns `sceneCompare`; one connect call
Apps/projectM-iOS/Views/SceneCompareViews.swift                     # new: Compare row, setup sheet, Comparing bar
Apps/projectM-iOS/Views/SceneSnapshotRows.swift                     # the Compare row
Apps/projectM-iOS/Views/VisualizerView.swift                        # the bar (one line)
Apps/projectM-iOS/Tests/SceneCompareAcceptanceTests.swift           # new
Apps/projectM-iOS/UITests/SceneCompareUITests.swift                 # new
```

## Complexity Tracking

None.
