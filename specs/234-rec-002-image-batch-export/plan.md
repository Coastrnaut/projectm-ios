# Implementation Plan: REC-002 Image Batch Export

**Branch**: `feature/rec-002` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A main-actor model, `SnapshotBatchExportCoordinator`, turns the selected SCN-008 snapshots of the current scene into
a frozen `SnapshotBatchJob` when Export is tapped: the native visual's style, Reduce flashing, the safety clamp, the
size and, per image, the render values (the live snapshot-parameter values with the snapshot's usable values laid
over them by `SceneSnapshotRecallPlan`, SCN-009's side rule D4) and the file name (`SnapshotBatchNaming`). It reads
through the snapshot coordinator's `read` and never calls `write`, so the live values, autosave, the scene file, the
snapshot list and the undo history are untouched by construction (research REC-002-D1).

A detached task renders the job with `SnapshotStillRenderer`: its own Metal device queue, the same generator factory
as `NativeSpectrumHost` (`makeGenerator`, now internal) and the FX-001 glow (`BloomEffect` in an `EffectChain`),
into an offscreen `bgra8Unorm_srgb` texture at the chosen size; four warm-up frames at a fixed 60 Hz clock from
t = 1 s with seeded synthetic bands or waveform, then a blit to a shared buffer gives REC-001's
`CapturedPixels(.sRGBBGRA8TopDown)`, encoded with `FrameImageEncoder` as PNG and written to
`<tmp>/SnapshotBatch/<UUID>/<NN>-<name>.png`. Progress returns to the main actor after each image; Cancel (a flag
checked between images) or a failure deletes the folder. The finished batch offers Save… (`fileExporter` with one
`FileDocument` per image), Share… (system sheet, REC-012's exclusions) and Save to Photos (REC-011's coordinator, one
image after the other).

UI: Settings › Visual gets an "Export Images…" row under SCN-009's Compare row (inside `SceneSnapshotRows`, no
`SettingsView` edit) that opens the export sheet.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: SwiftUI, Observation, Metal; VisualGenerators, VisualEffects (`BloomEffect`, `EffectChain`), VisualParameters (`BloomParameters`, `SafetyClamp`), FrameCapture (`CapturedPixels`, `FrameImageEncoder`), SceneFormat, ParameterGraph; app SCN-008 snapshots, SCN-009 compare, REC-011 photos, REC-012 share rules, ACC-004 announcer
**Storage**: temporary files only (`<tmp>/SnapshotBatch`), removed on Done and at launch; no UserDefaults key
**Testing**: XCTest app unit tests (naming, plan, renderer, acceptance with real autosave stores in a temporary folder); one UI test under 30 s on simulator "REC2 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+
**Performance Goals**: an image of 1920 × 1080 renders and encodes in well under a second on a device; the main actor does no rendering
**Constraints**: no scene format change, no new UserDefaults key, no permission beyond REC-011's add-only, no networking; owner rule 7 budgets; Xcode 26 type-check budget; small edits in shared files (AppCoordinator)

## Constitution Check

- I (public APIs only): Metal, SwiftUI, Photos add-only (existing). Pass.
- Privacy and local-first: files stay in the app's temporary folder until the user saves or shares them. Pass.
- VI (modular boundaries): naming and planning are pure value code; rendering is one class; the coordinator owns the state machine. Pass.
- VII (real-time audio safety): no audio thread involvement; synthetic audio. Pass.
- FR-072 / ACC-012 (flash safety): the images go through the generators' limiter and the clamped glow, as on screen. Pass.
- X (evidence): simulator tests prove behavior only; no device claim.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Apps/projectM-iOS/Coordinators/SnapshotBatchNaming.swift              # new: safe names, NN prefix, collisions
Apps/projectM-iOS/Coordinators/SnapshotBatchJob.swift                 # new: sizes, items, job capture from the live state
Apps/projectM-iOS/Coordinators/SnapshotBatchExportCoordinator.swift   # new: state machine, folder, cancel, offers
Apps/projectM-iOS/Coordinators/AppCoordinator+SnapshotBatch.swift     # new: wiring
Apps/projectM-iOS/Visuals/SnapshotStillRenderer.swift                 # new: offscreen render + synthetic audio
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift                    # makeGenerator private → internal
Apps/projectM-iOS/Coordinators/SceneSnapshotCoordinator.swift         # weak `batchExport` link
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                   # owns `snapshotBatch`; one connect call
Apps/projectM-iOS/Views/SnapshotBatchExportViews.swift                # new: row, sheet
Apps/projectM-iOS/Views/SceneSnapshotRows.swift                       # the row
Apps/projectM-iOS/Tests/SnapshotBatchNamingTests.swift                # new
Apps/projectM-iOS/Tests/SnapshotBatchExportAcceptanceTests.swift      # new
Apps/projectM-iOS/UITests/SnapshotBatchExportUITests.swift            # new
```

## Complexity Tracking

None.
