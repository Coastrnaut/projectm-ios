# Implementation Plan: SHOW-005 Cue Hold and Skip

**Branch**: `feature/show-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

**Skip (model and file).** `ShowCue` gains `skipped: Bool` (default false). `ShowCueList.next()` and `previous()`
look for the nearest cue that is not skipped (a new outcome `.allSkipped` when every cue is skipped); `canGoNext` /
`canGoPrevious` follow the same rule, so SHOW-002's timeline (`hasNext: list.canGoNext`) never counts down towards
nothing. `go(to:)` is unchanged. `setSkipped(_:_:)` edits the flag (never moves the position). `show.json` stores
an optional per-cue `skip: true`, written only when set and read leniently (`StoredSkip`: a boolean or nothing;
another JSON type is dropped and counted in `droppedSkipFlags(n)`); no version bump (SHOW-002/004 pattern).

**Skip (app).** `ShowCoordinator.setSkipped` is an edit (refused while locked through `refusedByLock`), saves at
once, applies nothing; `save()` already calls `listChanged`, and `ShowAutoAdvanceCoordinator.listChanged` also
cancels a countdown when the active cue no longer has a next cue. `perform` posts "All cues are skipped." (cue lane)
when a step returns `.allSkipped`. Duplicate Scene passes the flag to `insert`. `statusText` reads "… · all
skipped" when every cue is skipped. The editor row is dimmed with "Skipped" (VoiceOver ", skipped") and gains
"Skip Cue"/"Don't Skip Cue" (context menu), a leading swipe "Skip"/"Unskip" and a VoiceOver action, all hidden while
locked.

**Hold.** `ShowAutoAdvanceCoordinator` gains session-only `isOperatorHeld` and `setOperatorHold(_:)`. The effective
hold is `isOperatorHeld || isHeld()` (pause, blackout, repair, background as before), applied at once
(`timeline.setHeld`, refresh). Turning Hold on while SHOW-003 holds a **timed** step for the beat withdraws it
(`ShowCueQuantizer.withdrawTimed()`) and re-arms the timeline for the active cue held with zero remaining
(`ShowAdvanceTimeline.rearm(cueID:remaining:at:)`), so Hold off makes it due at once (quantized again). Toggling
announces on the cue lane. UI: a Hold button in `ShowCueRow` (identifier `showHold`, label "Hold timed advances",
value On/Off, `.isToggle`), "Hold" in the pad's cue readout (VoiceOver ", hold on") with a VoiceOver action
"Hold"/"Release Hold".

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Foundation; SwiftUI in the app; existing ShowControl, PerformanceControl
**Storage**: `show.json` (optional per-cue `skip`); Hold is never stored; no UserDefaults key
**Testing**: ShowControl package tests (host; Linux in CI); app unit tests with `ShowManualClock` (acceptance);
one UI test under 30 s on simulator "SHOW5 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+ app; ShowControl also Linux
**Performance Goals**: none new (a step scans ≤ 256 cues)
**Constraints**: type-check budget (functions ≤ 300 ms, expressions ≤ 200 ms); short tests (owner rule 7)
**Scale/Scope**: ≤ 256 cues per show (SHOW-001)

## Constitution Check

- I (public APIs only): Foundation and SwiftUI only. Pass.
- VI (modular boundaries): stepping rules and the file in ShowControl; hold wiring and views in the app. Pass.
- VII (real-time audio safety): no audio-thread work. Pass.
- Privacy / local-first: no network, no new stored key; Skip is part of the user's show file, Hold is not stored. Pass.
- Accessibility (FR-070, ACC-004): toggle with label and value, announcements on the cue lane, row value ", skipped", VoiceOver actions. Pass.
- X (evidence): deterministic tests with an injected monotonic clock (no wall-clock assertions); the simulator UI test proves behavior only; no device claim.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift        # ShowCue.skipped, skip-aware next/previous/canGo*, .allSkipped, setSkipped, insert(skipped:)
Packages/ShowControl/Sources/ShowControl/ShowDocument.swift       # skip field, StoredSkip, droppedSkipFlags
Packages/ShowControl/Sources/ShowControl/ShowAdvanceTimeline.swift # rearm(cueID:remaining:at:)
Packages/ShowControl/Tests/ShowControlTests/ShowSkipTests.swift   # new
Apps/projectM-iOS/Coordinators/ShowAutoAdvanceCoordinator.swift   # operator hold, listChanged cancel
Apps/projectM-iOS/Coordinators/ShowCueQuantizer.swift             # withdrawTimed()
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift              # setSkipped, all-skipped notice, duplicate, status
Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift          # toggleShowHold (announce)
Apps/projectM-iOS/Views/ShowControls.swift                        # Hold button
Apps/projectM-iOS/Views/PerformancePad.swift                      # readout Hold state and action
Apps/projectM-iOS/Views/ShowEditorView.swift                      # Skipped row, Skip actions
Apps/projectM-iOS/Tests/CueHoldSkipAcceptanceTests.swift          # new (acceptance)
Apps/projectM-iOS/UITests/CueHoldSkipUITests.swift                # new (one test)
```

**Structure Decision**: extend the existing model, coordinators and views; no new package.

## Complexity Tracking

None.
