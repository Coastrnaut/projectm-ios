# Implementation Plan: REC-006 Record frame rate

**Branch**: `feature/rec-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/164-rec-006-record-frame-rate/spec.md`

## Summary

Recordings gain an explicit export frame rate (Profile default, 24, 30, 60 fps) and an exact frame
grid. `RecordingTimeline` (REC-003) becomes a slot timeline: slot n is at n × 600/fps ticks from the
first frame; each offered frame maps to the slot whose half-interval window holds it, and a frame
that is early in its window is skipped when the next frame, predicted one render interval later,
would be nearer (nearest-frame decimation without buffering). Empty slots are not filled; the writer
queue counts them as dropped frames (`RecordingStatistics.droppedSlots`), and `RecordedVideo` reports
them with the nominal rate. A plain-Swift `RecordingFrameRateCatalog` decides which rates are
available from the REC-005 capability source, extended with an optional render cap (Low Power Mode,
serious thermal state) and an encoder frame-rate limit (both with defaults so existing sources
compile unchanged), and resolves Record: explicit rate fallback first, then REC-005's profile
resolution with the rate override, then the render cap and encoder limit for Profile default. The app
stores the choice next to the profile in `RecordingQualitySetting` (key `settings.recording.frameRate`),
shows it as a "Recording frame rate" section, and passes it to the recording coordinator. The
read-back gains the track's `nominalFrameRate` and `minFrameDuration`; a GPU fixture records 24, 30
and 60 fps from injected 60 Hz, 120 Hz, jittery and stalled frame times and checks rate, grid and
drop counts.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 build machine; CI also Xcode 26).
**Primary Dependencies**: AVFoundation (writer, read-back), Metal (fixture frames), SwiftUI.
**Storage**: one String in UserDefaults (`settings.recording.frameRate`), device-local.
**Testing**: XCTest. FrameRecording: timeline (slot mapping, decimation, drops), rate catalog and resolution (plain Swift, Linux-buildable), GPU fixture (24/30/60 × 4 patterns, small drawable, offline writer) on the Mac host. App unit tests (setting persistence, availability, Record resolution with injected capabilities), one UI test (picker).
**Target Platform**: iOS/iPadOS 26+.
**Project Type**: mobile app with SwiftPM packages.
**Performance Goals**: per frame: a few integer operations in the timeline (no allocation, no wait, no extra GPU copy); drop counting is one subtraction on the writer queue.
**Constraints**: Constitution I, VII, X; owner rule 7 (fixture under 10 s, UI test under 30 s); Linux build of the plain-Swift files.
**Scale/Scope**: FrameRecording timeline rewrite (same API), one catalog file, recorder and inspector edits; app: setting, section, coordinator, a few shared-file one-liners.

## Constitution Check

| Principle | Check |
|---|---|
| I. Public APIs only | Pass. `AVVideoExpectedSourceFrameRateKey`, `AVAssetTrack.nominalFrameRate`/`minFrameDuration`, `ProcessInfo.isLowPowerModeEnabled`, `thermalState`, `UIScreen.maximumFramesPerSecond` are public. |
| IV. Truthful labeling | Pass. Disabled rates say why; a fallback is announced; the result reports dropped frames. |
| VI. Modular boundaries | Pass. Timing and availability rules are plain Swift in FrameRecording; the app maps the governor and screen into the capability source. |
| VII. Real-time safety | Pass. The timeline is constant-time integer work on the frame loop; nothing waits; drops are counted, never caught up. |
| Privacy | Pass. One device-local preference, excluded from the backup, erased with Settings. |
| X. Evidence | Host fixture is not device evidence; the device read-back is `{device}` (left open). |

Post-design re-check: unchanged (Pass). The grid amends ADR-0027 decision 2 → new ADR (REC-006-D1).

## Project Structure

### Documentation (this feature)

```text
specs/164-rec-006-record-frame-rate/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/frame-rate.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/FrameRecording/
├── RecordingTimeline.swift            # slot timeline (rewritten, same API)
├── RecordingFrameRate.swift           # NEW: choice, availability, reasons, resolution
├── RecordingQualityAvailability.swift # capability protocol: renderLimit, maxEncodedFramesPerSecond (defaults); profile availability with a rate override
├── RecordingQualityProfile.swift      # settings(frameRate:)
├── RecordingFrameGate.swift           # RecordingStatistics.droppedSlots
├── RecordingOutcome.swift             # RecordedVideo.frameRate, droppedFrames
├── MetalFrameRecorder.swift           # count empty slots on append
└── RecordedVideoInspector.swift       # trackNominalFrameRate, minFrameDurationTicks
Packages/Compositor/Tests/FrameRecordingTests/
├── RecordingRulesTests.swift          # timeline tests updated to the grid
├── RecordingFrameRateTests.swift      # NEW: decimation, drops, availability, resolution
└── RecordingFrameRateFixtureTests.swift # NEW: acceptance fixture (GPU)
Apps/projectM-iOS/
├── Coordinators/RecordingQualitySetting.swift   # frameRate choice + capabilities with the governor cap
├── Views/RecordingFrameRateSection.swift        # NEW
├── Coordinators/VideoRecordingCoordinator.swift # Context.frameRateChoice, resolution, lastRecording
├── Coordinators/AppCoordinator.swift, Views/SettingsView.swift  # one line each
├── Tests/RecordingFrameRateAppTests.swift       # NEW
└── UITests/RecordingFrameRateUITests.swift      # NEW
Packages/LibraryBackup/Sources/LibraryBackup/{LibrarySettings,LibraryErasePolicy}.swift, scripts/run_device_tests.py  # the key
docs/adr/00NN-recording-frame-grid.md            # amends ADR-0027 decision 2
```

**Structure Decision**: extend the existing FrameRecording module and REC-005's app setting; no new package or target.

## Complexity Tracking

None.
