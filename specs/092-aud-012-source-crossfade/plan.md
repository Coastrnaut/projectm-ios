# Implementation Plan: AUD-012 Source Crossfade

**Branch**: `feature/aud-012` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/092-aud-012-source-crossfade/spec.md`

## Summary

A mid-session source switch with a bounded, ducked handoff (research AUD-012-D1). The renderer
boundary is `NormalizedPCMRing.write` (AudioCore): every sample projectM and the analysis tap ever
receive passes through it, on the analysis queue. It gains two stages:

1. **Sanitizer** (`PCMSanitizer`): one scan per write; clean audio (finite, |x| ≤ 2) is written as
   before with no copy. Otherwise the write goes through a preallocated 1,024-frame scratch where
   NaN/±Inf become 0 and finite values beyond ±2 are clamped, counted in an atomic counter. The
   analyzer also replaces non-finite samples in its drain scratch before level metering and the
   Normalizer (research D4).
2. **Handoff envelope** (`HandoffEnvelope`): an integer ramp position 0…4,410 (100 ms) and a phase
   (unity, fading out, silent, fading in). Unity is the fast path; otherwise each frame is scaled by
   position / 4,410.

`CaptureManager.switchSource(to:)` orchestrates (contract C2): set the switching label → start the
fade-out (the old source keeps delivering) → wait until it is done or 150 ms passed → complete it
(from the last sample if needed, ≤ 1,024 frames) → stop the old source → a handoff attempt:
`AudioAnalyzer.beginAttempt(handoff: true)` empties the sink and the tap but keeps projectM's ring
(its content ends at exact 0), advances the generation, writes 1,024 frames of silence and arms the
fade-in → start the new source. The manager's `switchingTo` drives the "Switching source…" label
until the new session's first audio is observed, its attempt ends or its state is decided.

The app adds a "Switch Source" control and dialog (`AppCoordinator.switchSource(to:)`), routes
the indicator text, announcements and the AUD-007 route indicator through the label rule, moves
AUD-011's microphone flag at the switch point (a manager callback), shows the sanitized count in
the performance overlay when non-zero, and lets `-uitestFake` take a comma-separated list so a UI
test can switch between two fakes.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode

**Primary Dependencies**: AudioCore (`Synchronization.Atomic`), CaptureKit, SwiftUI

**Storage**: none (no new keys)

**Testing**: XCTest: AudioCore on the host and with `-DAUDIOCORE_NO_AVFAUDIO` (the Linux job's
shape), CaptureKit on the host; app unit tests and UI tests on the feature's simulator
"AUD12 iPhone 17" (iOS 27.2, deleted afterwards)

**Target Platform**: iOS 26.0+ (app), macOS 15 and Linux (packages)

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: clean, idle-envelope write = one compare per sample, no copy; the ramp costs
one multiply per sample for 100 ms per switch

**Constraints**: no allocation, lock or logging in the write path or the drain pass; no new
permission, API or capture; projectM's ring bit-identical for clean audio outside a handoff

**Scale/Scope**: 2 packages (AudioCore, CaptureKit), app coordinator and 4 views, 1 debug fake

## Constitution Check

| Principle | Check |
|---|---|
| I. Public APIs only | No new framework or API; pure Swift arithmetic. Pass. |
| II/III. Capture | No change to what is captured or how; sources are only stopped and started as today. Pass. |
| IV. Truthful labeling | Ducking never mixes two sources under one label; the label names a source only once its audio flows; "Active audio" is still verified per session (new attempt). Pass. |
| V. No universal claims | No compatibility wording. Pass. |
| VI. Modular boundaries | projectM's reader is unchanged (`NormalizedPCMReader`); the handoff lives in AudioCore/CaptureKit; the renderer knows nothing of sources. Pass. |
| VII. Real-time safety | All new code runs on the analysis queue (never an audio callback); preallocated scratch, scalar state, one relaxed atomic add per dirty write; queues stay bounded (the silence is 1,024 frames into a drop-oldest ring). The underrun policy (R-06: no silence injected) gains one documented exception: the handoff silence. Pass. |
| Privacy | No audio stored or logged; the sanitized count is a number. No new permission (FILE-013 catalog unchanged). Pass. |
| X. Evidence | Unit tests on host and Linux shape, UI test on the simulator; device tasks stay open. Pass. |

Post-design re-check: unchanged (no violations; Complexity Tracking empty).

## Project Structure

### Documentation (this feature)

```text
specs/092-aud-012-source-crossfade/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/source-handoff.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/AudioCore/Sources/AudioCore/
├── SourceHandoff.swift          # new: PCMSanitizer, HandoffEnvelope
├── NormalizedPCMReader.swift    # write through the boundary; handoff reset; counters
└── AudioAnalyzer.swift          # input sanitize; fade-out control; handoff attempt
Packages/AudioCore/Tests/AudioCoreTests/SourceHandoffTests.swift
Packages/CaptureKit/Sources/CaptureKit/CaptureManager.swift   # switchSource, switchingTo, timing
Packages/CaptureKit/Tests/CaptureKitTests/SourceSwitchTests.swift
Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift          # "Switching source…", "Switch Source"
Apps/projectM-iOS/Coordinators/AppCoordinator.swift           # switchSource(to:), label, gate flag
Apps/projectM-iOS/Views/{SourceStatusIndicator,ControlsOverlay,VisualizerView,PerformanceOverlay}.swift
Apps/projectM-iOS/Debug/UITestFakeSource.swift                # several fakes, -uitestFakeLevel
Apps/projectM-iOS/Tests/SourceSwitchAppTests.swift
Apps/projectM-iOS/UITests/SourceSwitchUITests.swift
docs/adr/00NN-source-switch-handoff.md
```

**Structure Decision**: the boundary stays inside AudioCore's ring (the one choke point every
writer, including the resampler stages, already uses); orchestration stays in CaptureManager, which
already serializes source commands.

## Complexity Tracking

None.
