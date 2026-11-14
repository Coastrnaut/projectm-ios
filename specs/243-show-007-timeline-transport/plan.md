# Implementation Plan: SHOW-007 Timeline Transport

**Branch**: `feature/show-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

**Timeline (model, ShowControl, Linux).** A pure `ShowTimeline` built from a `ShowCueList`: entries are the
non-skipped cues in order with start and span (dwell), ending at the first cue without a dwell (open end).
`locate(_:looping:)` maps a time to (cue, index, elapsed, remaining); `time(ofCue:elapsed:)` maps back;
`loopTarget(from:looping:)` names the first entry when the active cue is the last entry and Loop applies.
`ShowSeekPlan.plan(...)` turns a seek into `.none`, `.reposition(cueID, remaining)` or `.apply(cueID, remaining)`
(research D2). `ShowScrub` coalesces a drag: `begin`, `move(to:)` (preview only), `end()` → at most one time to
commit (D3). `ShowAdvanceTimeline` is reused unchanged as the playhead too (D4).

**Driver (app).** `ShowAutoAdvanceCoordinator` gains a playhead (a second `ShowAdvanceTimeline` that always runs for
a timed cue and is never acted on), a `loops` closure (the last timeline cue counts down and wraps through
`ShowCoordinator.timedGo(to:)`, quantized like a timed advance; `passes` counts wraps) and `reposition(cueID:
remaining:)` for seeks.

**Seek path (app).** `ShowCoordinator.seek(to:)`: withdraws any waiting quantized step (silent), then runs the one
step path (`perform`) with the transition forced to a cut (D5) — one save, one scene apply (with MOD-017's
`cueApplied`), one transition drive, one `cueStarted`. `ShowTransportCoordinator` (observable; owns the Loop key and
the scrub) plans the seek and calls `seek` only for `.apply`, then `reposition` (D2).

**UI.** `ShowTimelineRow` under the cue row's buttons in `ShowCueRow` when a timeline exists: Play/Pause (SHOW-005
Hold via `AppCoordinator.setShowHold`), an ACC-005 accessible slider (`showTimelineScrub`, 5 s step), "1:15 / 2:30"
or the scrub preview "Cue 3 · Drop at 0:15", and a Loop toggle. A `TimelineView` refreshes the position twice a
second only while the row is on screen.

**Acceptance proof.** `ShowTransportAcceptanceTests` (app unit test target): a real `ShowCoordinator` over a
temporary store, the driver on a `ShowManualClock`, SHOW-003's quantizer and MOD-017's `ParameterQuantizer` in Cue
mode, and a recorder of applies, transitions, announcements, MOD-017 applies and quantized steps. Seek across three
cues → exactly one apply; repeat → nothing; loop two passes → two wraps; pause/play keeps remaining.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Foundation, SwiftUI; ShowControl, PerformanceControl (quantizers)
**Storage**: one UserDefaults key `settings.show.loop` (Bool, absent = off); no show-file change
**Testing**: ShowControl package tests (host; Linux in CI); app unit/acceptance tests; one UI test < 30 s on
"SHOW7 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+ app; ShowControl also Linux
**Performance Goals**: building a timeline is O(cues) ≤ 256; the row refreshes at 2 Hz only while visible
**Constraints**: type-check budget; short tests (owner rule 7); shared files (`AppCoordinator`, `AppSettings`) get
one-line edits
**Scale/Scope**: ≤ 256 cues, dwell 1 s…60 min (timeline ≤ 256 h)

## Constitution Check

- I (public APIs only): Foundation, SwiftUI. Pass.
- VI (modular boundaries): timeline, seek plan and scrub in ShowControl (pure, Linux); driving and UI in the app. Pass.
- VII (real-time audio safety): no audio-thread work. Pass.
- VIII (projectM fidelity): no engine change. Pass.
- Privacy / local-first: no network; one device preference, not backed up. Pass.
- Accessibility (FR-070, ACC-004, ACC-005): labelled buttons, accessible slider, no duplicate announcements. Pass.
- Safety (Reduce flashing): a seek's cut still goes through `CueTransitionResolver` (minimum fade). Pass.
- X (evidence): injected clocks, event recorder, no wall-clock assertions; simulator proves behavior only.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ShowControl/Sources/ShowControl/ShowTimeline.swift          # timeline, seek plan, scrub (new)
Packages/ShowControl/Tests/ShowControlTests/ShowTimelineTests.swift  # new
Apps/projectM-iOS/Coordinators/ShowTransportCoordinator.swift       # new
Apps/projectM-iOS/Coordinators/ShowAutoAdvanceCoordinator.swift     # playhead, loop, reposition
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                # seek, timedGo
Apps/projectM-iOS/Coordinators/ShowCueQuantizer.swift               # withdrawAll
Apps/projectM-iOS/Coordinators/AppCoordinator(+Show).swift          # wiring (one lazy var)
Apps/projectM-iOS/Views/ShowTimelineRow.swift                       # new; ShowControls.swift one edit
Apps/projectM-iOS/Debug/UITestShowFixture.swift                     # -uitestShowTimelineSeed
Apps/projectM-iOS/Tests/ShowTransportAcceptanceTests.swift          # new
Apps/projectM-iOS/UITests/ShowTimelineUITests.swift                 # new
```
