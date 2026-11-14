# Implementation Plan: REC-014 Export aspect presets

**Branch**: `feature/rec-014` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/215-rec-014-export-aspect-presets/spec.md`

## Summary

Recordings gain an aspect choice (Match screen, Portrait 9:16, Square 1:1, Landscape 16:9, Custom W×H)
and a per-device output cap. Both are plain-Swift rules in FrameRecording: `RecordingAspect` (with the
validated `RecordingCustomSize`) and `RecordingOutputCap` (compact/regular device classes, limited by
the GPU texture side) become fields of `RecordingSettings`; `RecordingGeometry` computes the output from
the drawable, the profile's long side, the aspect and the cap (exact even multiples of the preset's
ratio, no larger than the centred crop, so never upscaled) and marks crop-to-fill. The capability
protocol gains `outputCap` (default regular) so the catalogs need only one new `aspect:` parameter.
The writer crops with its own scaler (`AVVideoScalingModeResizeAspectFill`) when the output aspect
differs, so the five visual hosts and the frame loop are unchanged. A reduced custom size adds a
"Recording at W×H: Custom size reduced to fit this device." notice to Record's resolution (row X9c).
The app stores the choice next to the profile and frame rate in `RecordingQualitySetting`, shows a
"Recording aspect" section under the frame-rate section, passes the aspect in the recording context,
and reports the device cap through `DisplayBoundCapabilities`.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 build machine; CI also Xcode 26).
**Primary Dependencies**: AVFoundation (writer scaling mode, read-back), Metal (fixture), SwiftUI.
**Storage**: three device-local UserDefaults values (`settings.recording.aspect`, `.customWidth`, `.customHeight`).
**Testing**: XCTest. FrameRecording: geometry sweep (presets × profiles × drawables × cap classes, custom sizes; plain Swift, Linux-buildable), catalog with aspect, one short GPU encode fixture (two tiny clips). App unit tests (persistence, validation, rows, Record with an aspect and a reduced custom size), one UI test (pick Square).
**Target Platform**: iOS/iPadOS 26+.
**Project Type**: mobile app with SwiftPM packages.
**Performance Goals**: no frame-loop work added (the encoder's scaler crops); geometry is computed once per Record and per Settings row.
**Constraints**: Constitution I, VI, X; owner rule 7 (fixture under 10 s, UI test under 30 s); Linux build of the plain-Swift files.
**Scale/Scope**: one new FrameRecording file, small edits to settings/geometry/availability/writer; app: setting, section, coordinator context, three key lists.

## Constitution Check

| Principle | Check |
|---|---|
| I. Public APIs only | Pass. `AVVideoScalingModeResizeAspectFill`, `ProcessInfo.physicalMemory` are public. |
| IV. Truthful labeling | Pass. Rows show the real planned size; a reduced custom size is said in Settings and at Record. |
| VI. Modular boundaries | Pass. Rules are plain Swift in FrameRecording; the app supplies the device class. |
| VII. Real-time safety | Pass. No frame-loop change. |
| Privacy | Pass. Device-local preferences, excluded from the backup, erased with Settings. |
| X. Evidence | Host fixture is not device evidence; the device check is `{device}` (left open). |

Post-design re-check: Pass. Crop-to-fill and the output cap amend ADR-0027's geometry (REC-003-D3) → ADR-0060.

## Project Structure

### Documentation (this feature)

```text
specs/215-rec-014-export-aspect-presets/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/aspect-presets.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/FrameRecording/
├── RecordingAspect.swift               # NEW: aspect, custom size validation, output cap, notice text
├── RecordingSettings.swift             # settings.aspect/outputCap; geometry with aspect, cap, cropsToFill, reducedCustom
├── RecordingQualityAvailability.swift  # capabilities.outputCap; aspect parameter
├── RecordingFrameRate.swift            # aspect parameter; reduced-size notice
├── VideoFileWriter.swift               # ResizeAspectFill when cropping
└── MetalFrameRecorder.swift            # geometry from settings
Packages/Compositor/Tests/FrameRecordingTests/
├── RecordingAspectTests.swift          # NEW: geometry sweep, validation, catalog, notice
└── RecordingAspectFixtureTests.swift   # NEW: short real encode
Apps/projectM-iOS/
├── Coordinators/RecordingQualitySetting.swift   # aspect + custom size, rows, device cap
├── Views/RecordingAspectSection.swift           # NEW
├── Coordinators/VideoRecordingCoordinator.swift # Context.aspect; geometry from settings
├── Coordinators/AppCoordinator.swift, Views/SettingsView.swift  # one line each
├── Tests/RecordingAspectAppTests.swift          # NEW
└── UITests/RecordingAspectUITests.swift         # NEW
Packages/LibraryBackup/Sources/LibraryBackup/{LibrarySettings,LibraryErasePolicy}.swift, scripts/run_device_tests.py
docs/adr/0060-recording-aspect-and-output-cap.md
```

**Structure Decision**: extend FrameRecording and REC-005's app setting; no new package or target.

## Complexity Tracking

None.
