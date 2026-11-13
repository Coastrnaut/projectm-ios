# Implementation Plan: REC-003 Video Recording

**Branch**: `feature/rec-003` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/058-rec-003-video-recording/spec.md`

## Summary

A new target `FrameRecording` in `Packages/Compositor` holds the recording rules in plain Swift
(settings, geometry, the timestamp timeline, the bounded in-flight gate, statistics, stop reasons and
refusals; Linux-testable) and, behind `#if canImport(AVFoundation)`, the video writer
(`AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`, HEVC then H.264), a read-back inspector
(`AVAssetReader`) and, behind `#if canImport(Metal)`, the `MetalFrameRecorder` that turns one shown
frame into one IOSurface-backed `CVPixelBuffer` through `CVMetalTextureCache`, entirely on the GPU
(research REC-003-D1 to D9, ADR-0027). Each recordable visual feeds it from its frame loop:

| Visual | Recording point | Copy |
|---|---|---|
| Camera, Photo, Video, Text (CMP-001) | after `Compositor.composite` succeeds, `Compositor.encodeOutput(into:commandBuffer:)` encodes the existing output pipeline (composite × flash-guard gain) a second time into the pixel buffer's `bgra8Unorm_srgb` texture | one render pass (existing shader) |
| Circular / Linear Spectrum | `NativeSpectrumHost` keeps `framebufferOnly` off while recording and blits the drawn drawable (glow included) into the pixel buffer's texture | one blit |
| projectM (ANGLE) | not recordable in this row (spec Clarifications; ADR-0027 follow-up) | — |

The pixel buffer's texture is the drawable's size cropped to even dimensions; the writer scales it to
the output size (long side ≤ 1920) with `AVVideoScalingModeKey`. No new Metal source.

`VideoRecordingCoordinator` (app, main actor) checks the refusals, attaches a `VideoRecordingTap` to
the shown visual's host, shows the indicator and elapsed time, watches the context (pause, blackout,
visual change, presentation loss) and the app lifecycle (background, with a background-task grant),
finishes the file off the main thread and hands it to the system `fileMover` (moves the temporary
file; nothing is copied or kept). DEBUG `-uitestRecordingDirectory <name>` moves the file into a
temporary folder instead and exposes a probe.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; Xcode 26 / iOS SDK 26.5 in CI).

**Primary Dependencies**: AVFoundation (`AVAssetWriter`, `AVAssetWriterInput`,
`AVAssetWriterInputPixelBufferAdaptor`, `AVAssetReader`), CoreVideo (`CVPixelBufferPool`,
`CVMetalTextureCache`), CoreMedia (`CMTime`), Metal (existing compositor output pipeline, blit),
Synchronization (`Mutex`), SwiftUI (`fileMover`), UIKit (background task). No new package; the
`Compositor` library product lists the new target.

**Storage**: one temporary file per recording in `<tmp>/Recordings/`, deleted after the mover
finishes or is cancelled, and at launch (FR-065).

**Testing**: `swift test --package-path Packages/Compositor` on the Mac host (timeline, gate, geometry,
10-second fixture encode + decode with a fake frame clock, stalled-writer bound, stop and finish,
compositor `encodeOutput`) and the Linux shape (`--scratch-path .build/linuxshape -Xswiftc
-DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`: pure rules only);
`xcodebuild test -scheme Compositor` once on the iOS 27.2 simulator; app unit tests (coordinator
refusals and every stop reason with a fake source; a real Photo host recording a few offscreen
frames); one UI test (`VideoRecordingUITests`).

**Target Platform**: iOS/iPadOS 26+.

**Project Type**: mobile app plus package additions.

**Performance Goals**: zero cost when not recording (one optional check per frame). While recording,
at most 30 frames per second each add one render pass or one blit; nothing on the CPU per frame but
bookkeeping; appends happen on the writer's serial queue; at most 3 pixel buffers in flight.

**Constraints**: public APIs only; no new Metal source (SHD-011 allowlist unchanged); no
required-reason API (no disk-space query, no file timestamps, no `mach_absolute_time` or
`systemUptime` in app code); explicit closure types; no C stdio globals; no main-actor mutation in
setUp/tearDown; no wall-clock assertions (the UI test asserts content); owner rule 7 budgets; never
the Simulator panel tool.

**Scale/Scope**: about 900 lines of source and 700 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | AVFoundation, CoreVideo, CoreMedia, Metal, SwiftUI `fileMover`, `UIApplication.beginBackgroundTask` | Pass |
| IV/V. Truthful labeling, no universal claims | No compatibility claim; device behavior is `{device}` tasks | Pass |
| VI. Modular boundaries | Rules and writer in a package target with no app, capture or engine knowledge; each host only offers "encode this frame into that texture" | Pass |
| VII. Real-time audio safety | No audio path change; no audio recorded (REC-004) | Pass |
| VII (queues) | The frame queue is bounded (3) with a tested overflow policy (drop + count) | Pass |
| VIII. Upstream fidelity | projectM and ANGLE untouched | Pass |
| IX. Dependencies | None added | Pass |
| X. Evidence | Fixture tests on host and Linux; simulator once; devices last, by the owner | Pass |
| Privacy | Explicit action only, user-chosen destination, no Photos permission, no audio, no metadata, no copy kept, temp files deleted; privacy policy and app-privacy notes updated; label still Data Not Collected | Pass |
| Flash safety (ADR-0011) | The recording copies the post-limiter frame; nothing new is shown | Pass |

Post-design re-check: unchanged, all pass. ADR-0027 records the recording pipeline (a new
subsystem with a scope limit: projectM not recordable yet); it overrides no constitution default.
ADR-0025 and ADR-0026 are left to PERF-014 and MED-014, which run in parallel.

## Project Structure

### Documentation (this feature)

```text
specs/058-rec-003-video-recording/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/video-recording.md
└── checklists/requirements.md
docs/adr/0027-video-recording-pipeline.md
docs/privacy-policy.md, docs/release/app-privacy.md   # recorded videos
```

### Source Code (repository root)

```text
Packages/Compositor/Package.swift                                        # + FrameRecording target, test target
Packages/Compositor/Sources/FrameRecording/RecordingSettings.swift        # NEW settings, codec, geometry
Packages/Compositor/Sources/FrameRecording/RecordingTimeline.swift        # NEW timestamp + rate rules
Packages/Compositor/Sources/FrameRecording/RecordingFrameGate.swift       # NEW bounded in-flight gate, statistics
Packages/Compositor/Sources/FrameRecording/RecordingOutcome.swift         # NEW stop reasons, refusals, failures, result
Packages/Compositor/Sources/FrameRecording/VideoFileWriter.swift          # NEW AVAssetWriter wrapper
Packages/Compositor/Sources/FrameRecording/RecordedVideoInspector.swift   # NEW AVAssetReader read-back
Packages/Compositor/Sources/FrameRecording/MetalFrameRecorder.swift       # NEW pixel buffers, texture cache, queue
Packages/Compositor/Sources/Compositor/Compositor.swift                   # + encodeOutput(into:commandBuffer:)
Packages/Compositor/Tests/FrameRecordingTests/*.swift                     # NEW
Packages/Compositor/Tests/CompositorTests/CompositorRecordingTests.swift  # NEW (fixture through a compositor)
Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift            # NEW
Apps/projectM-iOS/Visuals/*Host.swift                                     # + VideoRecordingSource, per-frame tap
Apps/projectM-iOS/Views/ControlsOverlay.swift, VisualizerView.swift      # Record, indicator, mover, notice, probe
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                      # owns the coordinator, active source
Apps/projectM-iOS/Tests/VideoRecordingAppTests.swift
Apps/projectM-iOS/UITests/VideoRecordingUITests.swift
```

**Structure Decision**: rules, writer and GPU copy in the package (host- and Linux-testable), one
copy call in each host, glue in the app.

## Complexity Tracking

None: no constitution violation. The per-host tap repeats a three-line call in four compositor hosts
on purpose (they already repeat the frame loop; plan of MED-001).
