# Implementation Plan: REC-008 Timed recording stop

**Branch**: `feature/rec-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/180-rec-008-timed-stop/spec.md`

## Summary

A recording can stop by itself after a set length (Off, 10 s, 30 s, 1 min, 5 min). The length becomes
the recording's `RecordingSettings.maxDurationSeconds` (capped by the 10-minute limit), so the existing
REC-006 grid timeline already refuses every frame whose slot tick is at or beyond it: frames at or after
the end never reach the writer. Two package changes make the end exact and non-blocking: the recorder
gets a `beginFinish()` that starts the (already asynchronous, writer-queue) finish without awaiting it,
and the audio timeline gets an end limit (`limitSample`) so a chunk straddling the end is cut at the
exact sample. The frame tap calls `beginFinish()` on the frame path right after the last audio pump of a
`durationReached` frame; the coordinator's stop then joins the same finish (idempotent). The coordinator
maps a `durationReached` with a set length to the new stop reason `timedStop` and the notice "Recording
stopped after 10 seconds." (status row X13). A small `RecordingTimedStopSetting` (key
`settings.recording.timedStop`) is shown in its own Settings section and passed in the coordinator's
context; the indicator reads "0:07 / 0:10".

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 build machine; CI also Xcode 26).
**Primary Dependencies**: AVFoundation, Metal, SwiftUI (existing); no new framework.
**Storage**: one String in UserDefaults (`settings.recording.timedStop`), backed up with the library settings.
**Testing**: FrameRecording package tests (GPU fixtures with injected frame times, read back with `RecordingValidator` and `RecordedVideoInspector`); app unit tests with the fake recording source; one UI test.
**Target Platform**: iOS/iPadOS 26+.
**Project Type**: mobile app with SwiftPM packages.
**Performance Goals**: nothing new on the frame loop beyond one lock and one task creation at the end.
**Constraints**: Constitution I, IV, VII, X; ACC-011 status router; owner rule 7 (short tests); FrameRecording stays buildable on Linux (pure-Swift timeline changes only).
**Scale/Scope**: two package edits (recorder, audio timeline), one stop reason, one setting file, one Settings section, small hooks in the coordinator, AppCoordinator, SettingsView, ControlsOverlay, StatusEvents.

## Constitution Check

| Principle | Check |
|---|---|
| I. Public APIs only | Pass. AVAssetWriter, Swift concurrency. |
| IV. Truthful labeling | Pass. "0:07 / 0:10" and "Recording stopped after 10 seconds." say what happens. |
| VI. Modular boundaries | Pass. The exact end is in the FrameRecording package; the app only maps a setting to settings. |
| VII. Real-time safety | Pass. The frame path never awaits; finishing runs on the writer queue (`beginFinish` creates a task). |
| Privacy | Pass. One preference; no new data. |
| X. Evidence | Package fixtures on the Mac; a device check is `{device}`. |

Post-design re-check: Pass. No ADR: Off keeps the default.

## Project Structure

### Documentation (this feature)

```text
specs/180-rec-008-timed-stop/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/timed-stop.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/FrameRecording/
├── RecordingAudioTimeline.swift        # limitSample: cut at the end
├── MetalFrameRecorder.swift            # beginFinish(); the audio limit from the duration
└── RecordingOutcome.swift              # RecordingStopReason.timedStop
Packages/Compositor/Tests/FrameRecordingTests/
├── RecordingTimedStopTests.swift       # NEW: acceptance fixtures (24/30/60 fps, jittery 60 Hz, audio), render-thread spy
└── RecordingAudioTimelineTests.swift   # limit cases
Apps/projectM-iOS/
├── Coordinators/RecordingTimedStop.swift          # NEW: lengths + setting
├── Coordinators/VideoRecordingCoordinator.swift   # context field, settings cap, timedStop mapping, indicator text
├── Coordinators/StatusEvents.swift                # X13 for the timed stop notice
├── Coordinators/AppCoordinator.swift              # the setting + context field
├── Views/RecordingTimedStopSection.swift          # NEW: Settings rows
├── Views/ControlsOverlay.swift, SettingsView.swift, VisualizerView.swift   # one-liners
├── Tests/RecordingTimedStopAppTests.swift         # NEW: manual stop, disk guard, persistence, mapping
└── UITests/RecordingTimedStopUITests.swift        # NEW
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py  # the key
```

**Structure Decision**: extend FrameRecording (exact end) and the REC-003 coordinator (setting); no new package.

## Complexity Tracking

None.
