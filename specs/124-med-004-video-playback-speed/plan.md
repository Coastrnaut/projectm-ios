# Implementation Plan: MED-004 Video Playback Speed

**Branch**: `feature/med-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/124-med-004-video-playback-speed/spec.md`

## Summary

The video layer's decode queue already lives on the video's own (unwrapped) timeline, and one
clock (`VideoPlaybackClock`) turns presentation times into that timeline. MED-004 multiplies the
clock's added step by a speed from a fixed set, so nothing downstream changes its mapping: the
queue, the loop region, catch-up, seeks and recovery all keep working in video time
(research MED-004-D1). Only the pre-roll lead grows with speeds above 1× (D3).

In `Packages/Compositor` (target `VideoLayer`; plain Swift parts build on Linux):

- New `VideoPlaybackSpeed` (`VideoPlaybackSpeed.swift`): an integer percentage from the set
  25/50/75/100/125/150/200; `init?(percent:)` rejects anything else; `.normal`; `all`;
  `prerollLeadNanoseconds` (0.5 s × max(speed, 1)).
- `VideoPlaybackClock`: `speed`, exact integer scaling with a carried remainder (D2), and
  `setSpeed(_:)`, which keeps the playback time (continuous) and starts a new measurement window
  (`presentationSinceSpeedChange`, `playbackSinceSpeedChange`) for the DEBUG ratio probe.
- `VideoDecodePipeline.speed` (passed to every session; `setSpeed` updates the running session
  under its lock, no restart); the session's pre-roll lead is `speed.prerollLeadNanoseconds`.
- `VideoLayerSource.playbackSpeed`: sets the clock's and the pipeline's speed; never restarts the
  decoder (D4).

In `Packages/SceneFormat`: `SceneAsset.videoSpeedPercent` (get/set over the video asset's
`extra["speedPercent"]`; a positive integer or nil; no decoder, encoder or version change; D6).

In `Packages/LibraryBackup`: `settings.video.speed` in `LibrarySettingsPolicy.excludedKeys` and in
`LibraryErasePolicy`'s media keys (`videoSpeedKey`) (D5).

In the app:

- `VideoStore`: `settings.video.speed` = `{id, percent}` for the stored video; read only when the
  ID matches and the percent is one of the seven; removed by Remove Video, a new current video and
  the UI tests' reset (`AppSettings.allKeys`) (D5).
- `VideoCoordinator`: `speed`, `setSpeed(_:)` (saves and applies at once through
  `onSpeedChange`), `restoreSpeed(storeID:speedPercent:)` for scenes, undo states and cues.
- `VideoSpeedControls` (new view file, small bodies): a "Speed" menu `Picker` above the loop
  sliders in Settings → Video, values read in words (D7); the footer text adds one sentence.
- `AppCoordinator`: the host gets the speed at creation, on a new video and on change; scene inputs
  and the show look carry `videoSpeedPercent`; every `restoreLoop` site also restores the speed.
- `SceneVideoLoopBridge`: the asset and the read-back carry the speed (`videoSpeedPercent`).
- DEBUG probe `videoSpeed` = `"<percent> ratio=<x.xxx>"` (video time over presentation time since
  the last speed change), read by the new `VideoSpeedUITests`.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/video-speed.md](contracts/video-speed.md); checks: [quickstart.md](quickstart.md). No
ADR: no default is overridden and the scene field follows CMP-006's optional-field rule (as
MED-003's `loop`).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: Compositor (`VideoLayer`), SceneFormat, LibraryBackup, SwiftUI. No new
dependency, no networking, no new Apple API.

**Storage**: one UserDefaults key, `settings.video.speed` (allowed-keys list in
`scripts/run_device_tests.py`; excluded from FILE-005 backups; FILE-011 media erase).

**Testing**: `Packages/Compositor`: `VideoSpeedTests` (plain Swift, Linux shape: speed set,
clock arithmetic at 0.5×/1×/2× over 2 s of injected 60 Hz steps, remainder carry, change mid-play
continuity, pre-roll lead, loop region through the fake reader at 0.5× and 2× with gap 0, speed
change without a restart) and one real-file case in `VideoLayerTests` (H.264 fixture, 0.5× and 2×,
shown pixel index = expected video time). `Packages/SceneFormat`: `SceneVideoLoopTests` gains the
speed field. `Packages/LibraryBackup`: policy tests gain the key. App: `VideoSpeedTests` (store per
ID, coordinator, scene round trips, the audio source untouched). UI: `VideoSpeedUITests` with
`-uitestSeedVideo counter`.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (CPU parts).

**Project Type**: iOS app plus SwiftPM package targets.

**Performance Goals**: no per-frame allocation added; the clock's work per frame is two integer
multiplications. Decoding at 2× is measured on the simulator only (reported, never asserted);
device throughput is `{device}` (MED-004-S7).

**Constraints**: public APIs only; explicit closure types; typed steps for strings and numbers; no
C stdio globals; no main-actor mutation in setUp/tearDown; no wall-clock assertions; unit tests
about 1-2 s, UI test under 30 s (owner rule 7). Parallel work: ACC-012 (sensory safety profile)
and FX-003 (colour grading); shared-file edits (SettingsView, AppCoordinator, AppSettings,
LibraryBackup policies) kept to a few lines.

**Scale/Scope**: 2 new sources, 1 new view, about 16 files touched, 3 new test files.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | SwiftUI `Picker`; no new framework | Pass |
| VI Modular boundaries | Speed lives in the video layer's clock (plain Swift); `VideoLayer` imports no audio or capture module, so speed cannot reach the audio source; the app stores and shows | Pass |
| VII Real-time safety | No audio code touched; `render` still never waits; no allocation added per frame | Pass |
| X Evidence | Injected clocks and the simulator fixture only; decoding at 2× and smoothness at 0.25× on D1 are `{device}` | Pass |
| Privacy | One integer and the video's ID in the app's settings; nothing sent; excluded from backups | Pass |
| No networking | None; `check_compliance.py` | Pass |
| Accessibility | Picker with a label and spoken values; works at accessibility sizes; no animation (`check_motion_policy.py`) | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/124-med-004-video-playback-speed/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/video-speed.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/VideoLayer/
├── VideoPlaybackSpeed.swift       # new
├── VideoPlaybackClock.swift       # speed, remainder, measurement window
├── VideoFrameQueue.swift          # speed → pre-roll lead
└── VideoLayerSource.swift         # playbackSpeed
Packages/Compositor/Tests/CompositorTests/
├── VideoSpeedTests.swift          # new (Linux shape)
└── VideoLayerTests.swift          # + speed on a real file
Packages/SceneFormat/Sources/SceneFormat/SceneVideoLoop.swift   # + videoSpeedPercent
Packages/SceneFormat/Tests/SceneFormatTests/SceneVideoLoopTests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, LibraryErasePolicy.swift
Apps/projectM-iOS/
├── Coordinators/VideoStore.swift, VideoCoordinator.swift, AppSettings.swift, AppCoordinator.swift
├── Coordinators/SceneVideoLoopBridge.swift, SceneAutosaveCapture.swift, ShowSceneSnapshot.swift
├── Coordinators/AppCoordinator+SceneHistory.swift, AppCoordinator+Show.swift
├── Views/VideoSpeedControls.swift # new
├── Views/SettingsView.swift, VisualizerView.swift
├── Visuals/VideoVisualHost.swift
├── Tests/VideoSpeedTests.swift    # new
└── UITests/VideoSpeedUITests.swift # new
scripts/run_device_tests.py        # allowed key
```

**Structure Decision**: extend the `VideoLayer` target and the Video visual; no new target.

## Complexity Tracking

None.
