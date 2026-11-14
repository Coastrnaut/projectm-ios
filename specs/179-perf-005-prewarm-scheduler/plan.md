# Implementation Plan: PERF-005 Preset prewarm scheduler

**Branch**: `feature/perf-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/179-perf-005-prewarm-scheduler/spec.md`

## Summary

A plain-Swift scheduler joins the `PresentationLifecycle` package (pure Swift, Linux-tested, already home of
PERF-011 and PERF-006):

- `PrewarmKey`, `PrewarmItem`, `PrewarmLookahead` (the next cue and the one after it; no wrap).
- `PrewarmCache`: a value type with a byte budget, rank-aware LRU eviction that never touches live keys.
- `PrewarmBudget`: the device-class budget (48 / 96 / 192 MB by physical memory).
- `PrewarmScheduler`: lock-protected, with injected executor (default: serial utility queue), clock (settle delay
  0.5 s), loader and budget. `plan(_:live:)` replaces the plan and cancels stale work; pause reasons
  (presentation, thermal, memory pressure); `take(_:)` hands an entry to the live scene; a graphics gate lets a
  presentation suspension wait for a running GPU step; `forwardPresets` passes preset picks through
  synchronously to the unchanged SC-104 warm-up.

`ImageLayerSource` (Compositor package) splits its load into a public decode and a public texture step and gains
`prewarmedTexture`, a lookup consulted when `content` is set: a hit makes the layer ready at once with no load of
its own. It counts its own loads (`loadsStarted`).

The app adds `MediaPrewarmCoordinator` (presentation-bound, PERF-006 cache responder, thermal and Low Power
observer) and `PhotoPrewarmLoader` (decode off the main thread, texture inside the graphics gate), and
`AppCoordinator+Prewarm.swift` that replans after every applied cue and at connect, routes preset picks through
the scheduler, and gives each new Photo visual the lookup. Video and logo kinds are modelled but skipped by the
loader (spec Clarifications).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26 and Linux)
**Primary Dependencies**: Foundation (core); Metal and ImageIO (ImageLayer, app loader)
**Storage**: none (no new UserDefaults key, no setting)
**Testing**: XCTest: PresentationLifecycleTests (acceptance, eviction order, executor spy, pause, preset timing;
macOS host and Linux), CompositorTests (prewarmed adoption on the host's Metal device), app unit tests on the
feature simulator "PERF5" (stepping cues prewarms the next photo, one decode, adoption)
**Target Platform**: iOS/iPadOS 26+, macOS host tests, Linux for the core
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: no main-thread work; no GPU work while the app cannot present; at most one item in flight
**Constraints**: held prewarm bytes ≤ budget; the live scene's assets are never evicted; preset warm-up unchanged
**Scale/Scope**: plans of at most a few items (two cues × one photo)

## Constitution Check

| Principle | Check |
|---|---|
| I. Public Apple APIs only | Foundation, Dispatch, Metal, ImageIO, `ProcessInfo` thermal state and Low Power. Pass. |
| VI. Modular boundaries | Core in PresentationLifecycle (no dependencies); ImageLayer gains no dependency; the app wires them. Pass. |
| VII. Real-time audio safety | Nothing touches audio. Pass. |
| X. Evidence-based quality | Package tests with injected clock/executor/memory accounting; simulator results are not performance evidence; frame-rate check on a device is a `{device}` task. Pass. |
| Privacy | No new stored data, no network. Pass. |

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/
  PrewarmModel.swift          # key, item, lookahead, budget
  PrewarmCache.swift          # budgeted rank-aware LRU
  PrewarmScheduler.swift      # scheduler, executor, clock, loader protocol, graphics gate
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/
  PrewarmSchedulerTests.swift # acceptance + unit tests
Packages/Compositor/Sources/ImageLayer/ImageLayerSource.swift   # decode/texture split, prewarmedTexture, loadsStarted
Packages/Compositor/Tests/CompositorTests/ImageLayerPrewarmTests.swift
Apps/projectM-iOS/Coordinators/MediaPrewarmCoordinator.swift    # coordinator + photo loader
Apps/projectM-iOS/Coordinators/AppCoordinator+Prewarm.swift     # wiring
Apps/projectM-iOS/Tests/MediaPrewarmAppTests.swift
```

## Complexity Tracking

None.
