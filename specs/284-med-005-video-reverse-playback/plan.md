# Implementation Plan: MED-005 Video Reverse Playback

**Branch**: `feature/med-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/284-med-005-video-reverse-playback/spec.md`

## Summary

Forward playback reads pictures once, forward, through a 3-picture queue; nothing can be shown
backwards without either random access or a cache. MED-005 decodes a supported clip once, on a
background queue, into a bounded cache of downsampled textures, then picks the shown picture from
that cache as a pure function of the existing video time (MED-002 clock × MED-004 speed), backwards
over the loop region (MED-003). The budget and the per-picture accounting are MED-008's
(`AnimatedFrameBudget`); every cached picture stays resident, so no eviction is involved
(research MED-005-D2, D3).

In `Packages/Compositor`, target `VideoLayer` (now also depending on `ImageLayer` for
`AnimatedFrameBudget`; no cycle: `ImageLayer` depends on `Compositor` and `MediaSniffing` only):

- `VideoReversePlayback.swift` (plain Swift, Linux too): `VideoReverseLimits` (30 s, 1920 × 1080,
  30 pictures/s), `VideoReverseUnsupported` (too long, too large, undecodable; the messages),
  `VideoReversePlan` (eligibility + cached size and count for a budget), `VideoReverseTimeline`
  (the pure picture selection), `VideoReverseFrameStore` (strict budget accounting with a peak),
  the `VideoReverseDecoding` seam and `VideoReverseCacheBuilder` (decode once, decimate to
  ≤ 30/s, account, cancel).
- `AVReverseFrameDecoder.swift` (Apple, Metal): `AVAssetReader` 32BGRA after the MED-014 container
  check and the probe; each picture downsampled on the CPU (nearest sample) into a shared
  `.bgra8Unorm_srgb` texture of the plan's size.
- `VideoReverseDriver.swift` (Apple, Metal): one build per request on a utility queue; state
  (`off`, `preparing`, `playing`, `unsupported`) behind an `OSAllocatedUnfairLock`; the render
  thread only tries the lock; state changes reach the main actor.
- `VideoLayerSource`: `reverse`, `reverseLimits`, `reverseBudgetBytes`, `onReverseStateChange`,
  `reverseState`, `reverseShownIndex`, `reversePeakBytes`. While the cache plays, the forward
  decoder is stopped; turning reverse off (or the cache failing) restarts it at the shown picture.
  The draw code is shared by both directions.

In `Packages/LibraryBackup`: `settings.video.reverse` in `LibrarySettingsPolicy.excludedKeys` and
in `LibraryErasePolicy`'s media keys (`videoReverseKey`).

In the app:

- `VideoStore`: `settings.video.reverse` = `{id}` for the stored video (read only for its id);
  removed by Remove Video, a new current video and the UI tests' reset (`AppSettings.allKeys`).
- `VideoCoordinator`: `reverse`, `setReverse(_:)` (saved, applied at once via `onReverseChange`),
  `reverseState` and `reverseCaption` from `reverseStateChanged(_:)`, the unsupported message
  announced once.
- `VideoReverseControls` (new view): the "Reverse" toggle and its caption, under Speed.
- `VideoVisualHost`: `reverse`, `onReverseStateChange`, `reverseProbe()`; `AppCoordinator` wires
  them where speed is wired; `VisualizerView`'s video probe gains `videoReverse`.
- `scripts/run_device_tests.py` `ALLOWED_KEYS`; `SettingsTests` written-keys list.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / iOS SDK 27.2; CI also Xcode 26)
**Primary Dependencies**: AVFoundation (`AVAssetReader`), Metal, CoreVideo; no new third-party code
**Storage**: UserDefaults `settings.video.reverse`; the cache lives in memory only
**Testing**: XCTest: package tests (pure rules with a fake decoder, Linux shape; real-file layer
tests on the Mac host with Metal), app tests, one short UI test on the iOS 27.2 simulator
**Target Platform**: iOS/iPadOS 26.5+ (D3) and 27
**Project Type**: mobile app + Swift packages
**Performance Goals**: no work on the render path beyond a try-lock and a binary search; the cache
build runs at utility priority
**Constraints**: peak cache bytes ≤ the MED-008 budget (32 / 64 / 128 MB by device class)
**Scale/Scope**: at most 30 s × 30 pictures/s = 901 cached pictures

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: `AVAssetReader`, `MTLTexture.replace`, CoreVideo pixel access. |
| VI. Modular boundaries | Pass: rules are plain Swift in `VideoLayer`; the app only wires and stores a flag. |
| VII. Real-time audio safety | Pass: no audio code touched; the video has no soundtrack. |
| X. Evidence-based quality | Pass: acceptance through the real compositor on generated fixtures; device memory and smoothness are `{device}` tasks. |
| Privacy | Pass: one boolean per stored video, excluded from backups, erased with media. |

No violations; no ADR needed (no default is overridden).

## Project Structure

```text
specs/284-med-005-video-reverse-playback/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/video-reverse.md
└── checklists/requirements.md
Packages/Compositor/Sources/VideoLayer/
├── VideoReversePlayback.swift      (new, plain Swift)
├── AVReverseFrameDecoder.swift     (new, Apple + Metal)
├── VideoReverseDriver.swift        (new, Apple + Metal)
└── VideoLayerSource.swift          (reverse hooks)
Packages/Compositor/Tests/CompositorTests/
├── VideoReverseTests.swift         (new, pure)
└── VideoReverseLayerTests.swift    (new, real file + Metal)
Packages/LibraryBackup/Sources/LibraryBackup/{LibrarySettings,LibraryErasePolicy}.swift
Apps/projectM-iOS/
├── Coordinators/{VideoStore,VideoCoordinator,AppSettings,AppCoordinator}.swift
├── Visuals/VideoVisualHost.swift
├── Views/{VideoReverseControls (new),SettingsView,VisualizerView}.swift
├── Tests/{VideoReverseAppTests (new),SettingsTests}.swift
└── UITests/VideoReverseUITests.swift (new)
```

## Complexity Tracking

None.
