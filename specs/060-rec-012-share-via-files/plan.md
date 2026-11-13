# Implementation Plan: REC-012 Share via Files

**Branch**: `feature/rec-012` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/060-rec-012-share-via-files/spec.md`

## Summary

REC-001 and REC-003 stop opening the Files sheet by themselves. Each keeps its finished result as an
**offered result** (`FrameCaptureCoordinator.offered`: the encoded `CapturedFrame` in memory;
`VideoRecordingCoordinator.offered`: the finished temporary file in `<tmp>/Recordings`) and the
visualizer shows a ready panel ("Frame ready", "Recording ready") with Save…, Share… and Discard.
Save… opens the existing `fileExporter` / `fileMover`; a cancelled Save… keeps the result.

A new app-level `CaptureShareCoordinator` (main actor) owns sharing: on Share… it asks a
`ShareFileStore` for a **temporary copy** in `<tmp>/Sharing/<UUID>/<descriptive name>` (bytes of the
still written out, or the recording copied, an APFS clone), then presents `UIActivityViewController`
with that one file URL, excluding `.saveToCameraRoll` and `.assignToContact`. The sheet's
`completionWithItemsHandler` maps to `ShareOutcome` (completed / cancelled / failed); every outcome
deletes the copy's folder and leaves the original offered. At launch the coordinator deletes
everything in `<tmp>/Sharing` (directory listing only). DEBUG `-uitestShareSimulation` replaces the
system sheet with two buttons that deliver the outcome, and exposes a probe (research REC-012-D1 to D6).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; Xcode 26 / iOS SDK 26.5 in CI).

**Primary Dependencies**: UIKit (`UIActivityViewController`, `UIActivity.ActivityType`), SwiftUI
(`UIViewControllerRepresentable`, existing `fileExporter` / `fileMover`), Foundation `FileManager`.
No package change.

**Storage**: one temporary copy per Share… tap in `<tmp>/Sharing/<UUID>/`, deleted when the sheet
closes and at launch; the still stays in memory, the recording in `<tmp>/Recordings` (REC-003), until
saved, discarded or the process ends (FR-065).

**Testing**: app unit tests (`CaptureShareAppTests`: copy created with the original's bytes and name;
cancel / complete / fail delete the copy and keep the original; leftovers swept at init; excluded
activity types; outcome mapping; frame and recording coordinator offer / save / discard / refusal);
one UI test (`CaptureShareUITests`) with `-uitestShareSimulation`; the existing FrameCapture and
VideoRecording unit and UI tests, updated where the Files sheet no longer opens by itself.

**Target Platform**: iOS/iPadOS 26+.

**Project Type**: mobile app (app target only).

**Performance Goals**: nothing per frame. A copy of a still is a few MB written once; a recording's
copy is a clone on APFS.

**Constraints**: public APIs only; no networking API; no required-reason API (no file timestamps, no
disk-space query); explicit closure types; typed literals; no C stdio globals; no main-actor mutation
in setUp/tearDown; no wall-clock assertions; owner rule 7 budgets; never the Simulator panel tool;
small edits to shared files (`VisualizerView.swift`, `AppCoordinator.swift`), since PERF-014 and
SCN-001 run in parallel.

**Scale/Scope**: about 350 lines of source and 300 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | `UIActivityViewController`, `FileManager`, SwiftUI | Pass |
| IV/V. Truthful labeling, no universal claims | No claim about any receiving app; AirDrop, Messages, Files on D1 are `{device}` | Pass |
| VI. Modular boundaries | Sharing is one app coordinator; the capture and recording coordinators only hold their result | Pass |
| VII. Real-time audio safety | No audio or frame-loop change | Pass |
| VIII / IX | Engine untouched; no dependency added | Pass |
| X. Evidence | Unit and UI tests on the simulator; real sheet on D1 by the owner | Pass |
| Privacy (Platform, Security & Privacy Constraints) | Explicit action only; the file goes only to the activity the user picks; Photos and Contacts activities excluded, no permission requested; no network by the app; temporary copies deleted on close and at launch; privacy policy updated; App Store label stays Data Not Collected | Pass |

Post-design re-check: unchanged, all pass. No ADR: the share sheet is a system UI already used by
PRE-014, nothing overrides a default, and the REC-001-R10 / REC-003-R13 behavior change ("a cancel
releases the result") is recorded in the spec's Clarifications and in those features' specs as a
superseded note.

## Project Structure

### Documentation (this feature)

```text
specs/060-rec-012-share-via-files/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/capture-share.md
└── checklists/requirements.md
docs/privacy-policy.md, docs/release/app-privacy.md   # sharing
```

### Source Code (repository root)

```text
Apps/projectM-iOS/Coordinators/CaptureShareCoordinator.swift   # NEW store, outcome, coordinator, presenter
Apps/projectM-iOS/Views/CaptureResultPanels.swift              # NEW ready panels, share notice, DEBUG panel and probe
Apps/projectM-iOS/Coordinators/FrameCaptureCoordinator.swift   # offered still, Save…, Discard
Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift # offered recording, Save…, Discard, refusal
Apps/projectM-iOS/Coordinators/AppCoordinator.swift            # + one stored property
Apps/projectM-iOS/Views/VisualizerView.swift                   # + one line in banners; exporter name
Apps/projectM-iOS/Tests/CaptureShareAppTests.swift             # NEW
Apps/projectM-iOS/Tests/FrameCaptureAppTests.swift, VideoRecordingAppTests.swift   # updated
Apps/projectM-iOS/UITests/CaptureShareUITests.swift            # NEW
```

**Structure Decision**: all app-side; the file store is a plain value type so its lifecycle is
unit-tested without UI; the UIKit sheet is a thin representable.

## Complexity Tracking

None.
