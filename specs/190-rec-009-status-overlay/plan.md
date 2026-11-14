# Implementation Plan: REC-009 Recording status overlay

**Branch**: `feature/rec-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/190-rec-009-status-overlay/spec.md`

## Summary

While a recording runs, two compact lines appear under the existing indicator (which already shows the
duration, "0:07 / 0:10"): dropped frames from the recorder's live `RecordingStatistics.droppedSlots`
(REC-006) and the free storage with the minutes until the REC-015 guard would stop. A pure
`RecordingStatusSummary` in the FrameRecording package computes the texts and warning levels from the
statistics, the guard's policy and the latest storage reading; a pure `RecordingWarningThrottle` decides
which rising warnings are announced (at most once per kind per 30 s of recorded time). The REC-003
coordinator keeps the latest storage reading (at Record and from the existing 5 s storage loop) and
refreshes the summary in its 0.25 s check; a SwiftUI view shows it and a status-event modifier posts rows
X9f (dropped frames) and X9g (storage) through the ACC-011 router.

No burn-in option (research REC-009-D1): every recording is fed from the visual's own Metal output
(compositor `encodeOutput` or the native spectra's drawable), which SwiftUI never draws into. An app-hosted
acceptance test records a solid-colour Photo visual through the coordinator while a probe overlay and the
real status lines are on screen in the same window, and reads every frame back.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 build machine; CI also Xcode 26).
**Primary Dependencies**: SwiftUI, Metal, AVFoundation (existing); no new framework.
**Storage**: none (no new keys; values in memory only).
**Testing**: FrameRecording package tests (summary, thresholds, throttle; host, under 1 s); app unit tests (coordinator wiring, status rows, the exclusion acceptance with AVAssetReader read-back on the simulator GPU); one UI test (< 30 s).
**Target Platform**: iOS/iPadOS 26+.
**Project Type**: mobile app with SwiftPM packages.
**Performance Goals**: nothing on the frame loop; the summary is computed on the main actor every 0.25 s (one lock read of the statistics).
**Constraints**: Constitution I, IV, VI, VII, X; ACC-011 router (`check_status_events.py`); ACC-001 motion policy (no animation added); owner rule 7; FrameRecording stays Linux-buildable (pure Swift).
**Scale/Scope**: two package files, one app view file, small hooks in the coordinator, StatusEvents, StatusCaptionView and VisualizerView (one line).

## Constitution Check

| Principle | Check |
|---|---|
| I. Public APIs only | Pass. SwiftUI and the existing readings. |
| IV. Truthful labeling | Pass. "about 14 min left" uses the guard's own rule, never more time than the guard allows. |
| VI. Modular boundaries | Pass. Texts and rules in FrameRecording (pure), the view in the app. |
| VII. Real-time safety | Pass. Nothing added to the frame path; statistics are read under the existing lock. |
| Privacy | Pass. Free storage and drops stay in memory, never stored or sent (REC-009-R7); the disk-space reading is the already-declared E174.1 use. |
| X. Evidence | Simulator tests on the Mac; a device look is `{device}`. |

Post-design re-check: Pass. No ADR: no default is overridden (no setting added; the overlay is never recorded, as REC-003-R16 already required for the indicator).

## Project Structure

### Documentation (this feature)

```text
specs/190-rec-009-status-overlay/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/status-overlay.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/FrameRecording/
└── RecordingStatusSummary.swift          # NEW: summary, levels, texts, warning throttle
Packages/Compositor/Tests/FrameRecordingTests/
└── RecordingStatusSummaryTests.swift     # NEW
Apps/projectM-iOS/
├── Coordinators/VideoRecordingCoordinator.swift   # storage reading kept, summary refresh, throttle
├── Coordinators/StatusEvents.swift                # X9f, X9g
├── Views/RecordingStatusLines.swift               # NEW: the two lines + their status-event modifier
├── Views/VisualizerView.swift, StatusCaptionView.swift   # one line each
├── Tests/RecordingStatusOverlayAppTests.swift     # NEW: wiring, rows, exclusion acceptance
└── UITests/RecordingStatusOverlayUITests.swift    # NEW
scripts/check_status_events.py                     # the new view file is checked
```

**Structure Decision**: extend FrameRecording and the REC-003 coordinator; no new package.

## Complexity Tracking

None.
