# Implementation Plan: REC-007 Recording countdown

**Branch**: `feature/rec-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/175-rec-007-countdown/spec.md`

## Summary

Record gains an optional countdown (Off, 3, 5, 10 s). The recording coordinator gets a fourth state,
`.countingDown(remaining:)`, entered by Record after the existing refusals and before anything is
written. An injected `RecordingCountdownClock` (now + schedule-at-deadline, cancellable) drives the
ticks at whole seconds from the countdown's own start; a generation token makes each tick and the
completion act at most once, and the completion calls the unchanged start path. Record during a
countdown cancels it, except in a 0.25 s guard before completion and a 0.5 s guard after the start it
caused; a Cancel button (Escape through `.cancelAction`) cancels at any time. The 0.25 s context
check, the background observer and the visualizer's leave path cancel it automatically. Status rows
X9d (each second) and X9e (cancelled, transient caption) go through the status router's recording
lane. The preference is a small `RecordingCountdownSetting` (key `settings.recording.countdown`),
shown as its own Settings section and passed in the coordinator's context.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 build machine; CI also Xcode 26).
**Primary Dependencies**: SwiftUI, Foundation; no new framework.
**Storage**: one String in UserDefaults (`settings.recording.countdown`), backed up with the library settings.
**Testing**: XCTest app unit tests with a manual clock (no wall-clock waits) and the existing fake recording source; one UI test (under 30 s).
**Target Platform**: iOS/iPadOS 26+.
**Project Type**: mobile app with SwiftPM packages.
**Performance Goals**: nothing on the frame loop; one scheduled task per second while counting.
**Constraints**: Constitution I, IV, VII, X; ACC-001 motion policy (no animation); ACC-011 status router; owner rule 7.
**Scale/Scope**: one coordinator extension file, one setting, one Settings section, one overlay view, catalog rows, small one-line hooks in shared files.

## Constitution Check

| Principle | Check |
|---|---|
| I. Public APIs only | Pass. `Task.sleep`, `ProcessInfo.systemUptime`, SwiftUI `keyboardShortcut(.cancelAction)`. |
| IV. Truthful labeling | Pass. The number, "Cancel countdown" and the cancellation reason are shown and announced. |
| VI. Modular boundaries | Pass. Countdown logic lives in the recording coordinator's extension; views only read state. |
| VII. Real-time safety | Pass. No frame-loop work; no writer exists until completion. |
| Privacy | Pass. One preference; no file is made before the countdown completes; a cancel leaves nothing. |
| X. Evidence | Simulator tests are not device evidence; a device check is `{device}` (left open). |

Post-design re-check: unchanged (Pass). No ADR: no default is overridden (Off keeps today's start).

## Project Structure

### Documentation (this feature)

```text
specs/175-rec-007-countdown/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/countdown.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Apps/projectM-iOS/
├── Coordinators/RecordingCountdown.swift                  # NEW: setting values, clock protocol + system clock, cancel reasons
├── Coordinators/RecordingCountdownSetting.swift           # NEW: the stored preference
├── Coordinators/VideoRecordingCoordinator.swift           # state case, toggle routing, start(afterCountdown:), writer count; MARK Countdown: begin, tick, complete, cancel, guards (one file: `state` has a private setter)
├── Coordinators/StatusEvents.swift                        # rows X9d, X9e
├── Coordinators/AppCoordinator.swift                      # the setting + context field (two lines)
├── Views/RecordingCountdownView.swift                     # NEW: number + Cancel overlay
├── Views/RecordingCountdownSection.swift                  # NEW: Settings rows
├── Views/ControlsOverlay.swift, VisualizerView.swift, SettingsView.swift, StatusCaptionView.swift  # one-liners
├── Tests/RecordingCountdownAppTests.swift                 # NEW: acceptance, Off, background, announcements
└── UITests/RecordingCountdownUITests.swift                # NEW
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py  # the key
```

**Structure Decision**: extend the REC-003 coordinator in the app target; no new package.

## Complexity Tracking

None.
