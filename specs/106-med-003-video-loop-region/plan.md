# Implementation Plan: MED-003 Video Loop Region

**Branch**: `feature/med-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/106-med-003-video-loop-region/spec.md`

## Summary

MED-002's decode pipeline already owns looping, seeking and the unwrapped playback timeline, and
every read goes through one reader seam (`VideoFrameReading`). MED-003 generalises the pipeline's
"whole file" to an effective region [in, out) and adds recovery, pre-roll and a small UI.

In `Packages/Compositor` (target `VideoLayer`; the pipeline files are plain Swift and build on
Linux):

- New `VideoLoopRegion` (`VideoLoopRegion.swift`): in and out in nanoseconds (milliseconds at the
  edges), the 0.25 s minimum, `effective(duration:)` clamping (research MED-003-D1), `contains`.
- `VideoFrameReading` gains two defaulted requirements: `open(startNanoseconds:endNanoseconds:)`
  (default: the one-argument open) and `prepare(startNanoseconds:endNanoseconds:)` (default: no-op).
- `VideoDecodePipeline.start(atNanoseconds:region:mediaStartNanoseconds:)`; the old
  `start(atNanoseconds:)` is the whole-file case. The session maps pass k, picture time pts to
  playback time `base + k × L + (pts − in)` (research MED-003-D2): every open starts inside the
  region; pictures before in are skipped (the one covering in is kept as a fallback for a pass
  that would otherwise be empty); a picture at or after out ends the pass; the pass at in is
  prepared when reading comes within 0.5 s of out (D3); EOF, an early end or a reader error after
  a picture start the next pass at in and are counted; three bad passes in a row fail (D4).
- `TimedFrame.mediaNanoseconds` (the picture's time in the file); statistics `earlyEnds`,
  `recoveredErrors`, `prepared`.
- `AVVideoFrameReader`: `timeRange = [start, end)` and one prepared standby reader swapped in when
  the next open asks for its start (D3); the container check still runs before every open
  (MED-014).
- `VideoLayerSource.loopRegion`: a change restarts decoding at the shown picture when it lies inside
  the new region, otherwise at in, keeping the playback clock; a held picture outside the new
  region is dropped. `resumeDecoding` restarts at the shown picture. New read-outs:
  `shownMediaNanoseconds`, `mediaDurationNanoseconds`, `wraps`, `maxWrapLatenessNanoseconds`
  (the joint's gap, D5).

In `Packages/SceneFormat`: `SceneVideoLoop` and `SceneAsset.videoLoop` (get/set over the asset's
`extra["loop"]`; no decoder, encoder or version change; research D6).

In the app:

- `VideoStore`: `settings.video.loop` = `{id, inMilliseconds, outMilliseconds}` for the stored
  video; read only when the ID matches; cleared by Remove Video, a new current video and the UI
  tests' reset (it is in `AppSettings.allKeys`) (D7).
- `VideoCoordinator`: `loopRegion`, `durationNanoseconds`, `setLoop(inSeconds:)`,
  `setLoop(outSeconds:)`, `resetLoop()`, `commitLoop()`; saves at once, tells the player after the
  value settles (0.4 s or drag end) through `onLoopRegionChange`.
- `VideoLoopControls` (new view file, small bodies): In and Out sliders, times, Reset Loop, in
  Settings → Video.
- `AppCoordinator`: the host gets the region at creation and on change; the duration is copied to
  `videos` when the layer plays; scene inputs carry `videoLoop`.
- Scenes: `SceneInputs.videoLoop` and `ShowLook.videoLoop` write the video asset's `loop`; restore,
  undo and show cues apply it when the scene's video is the stored one.
- DEBUG probes: `videoMediaFrameIndex`, `videoLoopRegion`, `videoLoopStats`.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/video-loop.md](contracts/video-loop.md); checks: [quickstart.md](quickstart.md). No ADR:
no default is overridden and the scene field follows CMP-006's optional-field rule.

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: AVFoundation (`AVAssetReader.timeRange`), Compositor, SceneFormat,
SwiftUI. No new dependency, no networking.

**Storage**: one UserDefaults key, `settings.video.loop` (allowed-keys list in
`scripts/run_device_tests.py`).

**Testing**: `Packages/Compositor`: `VideoLoopTests` (fake reader: region table, timeline across
four boundaries, wrap from out−1 to in, gap 0, edits mid-play, stall seek and resume inside, early
end and reader error recovered and counted, three bad passes fail, every open inside the region;
Linux shape) and a real-file case in `VideoLayerTests` (fixture, region, pixels by index across
boundaries). `Packages/SceneFormat`: `SceneVideoLoopTests`. App: `VideoLoopTests` (store per ID,
coordinator clamping and settle, scene capture/restore/show round trips). UI: `VideoLoopUITests`
with `-uitestSeedVideo counter`.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (CPU parts).

**Project Type**: iOS app plus SwiftPM package targets.

**Performance Goals**: the joint shows no held picture when the decoder keeps up (gap 0 frames
with the fake reader; the simulator gap is measured and reported, never asserted on wall time).

**Constraints**: public APIs only; explicit closure types; typed steps for strings and numbers; no
C stdio globals; no main-actor mutation in setUp/tearDown; no wall-clock assertions; unit tests
about 1-2 s, UI test under 30 s (owner rule 7). Parallel work: FILE-003 (scene archive import),
MIDI-001, a test-budget agent (`DynamicTypeInspectorUITests`, `SessionRecoveryUITests`: not
touched); shared-file edits kept small.

**Scale/Scope**: 3 new sources, 1 new view, about 14 files touched, 4 new test files.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | `AVAssetReader`, `CMTimeRange`, SwiftUI `Slider` | Pass |
| VI Modular boundaries | Region rules live in the pipeline (plain Swift); the app stores and shows; SceneFormat only gains an accessor | Pass |
| VII Real-time safety | No audio change; `render` still never waits (try-lock), no allocation added per frame | Pass |
| X Evidence | Simulator fixture only; the picker and the visible joint on D1 are `{device}` tasks | Pass |
| Privacy | Two integers and the video's ID in the app's settings; nothing sent | Pass |
| No networking | None; `check_compliance.py` | Pass |
| Accessibility | Sliders with labels and "N seconds" values; no animation (`check_motion_policy.py`); layout wraps at accessibility sizes | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/106-med-003-video-loop-region/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/video-loop.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/VideoLayer/
├── VideoLoopRegion.swift          # new
├── VideoFrameQueue.swift          # region timeline, pre-roll, recovery
├── AVVideoFrameReader.swift       # end bound, standby reader
└── VideoLayerSource.swift         # loopRegion, read-outs
Packages/Compositor/Tests/CompositorTests/
├── VideoLoopTests.swift           # new
├── VideoPipelineTests.swift       # MED-002 error test follows the recovery rule
└── VideoLayerTests.swift          # + region on a real file
Packages/SceneFormat/Sources/SceneFormat/SceneVideoLoop.swift   # new
Packages/SceneFormat/Tests/SceneFormatTests/SceneVideoLoopTests.swift   # new
Apps/projectM-iOS/
├── Coordinators/VideoStore.swift, VideoCoordinator.swift, AppSettings.swift, AppCoordinator.swift
├── Coordinators/SceneAutosaveCapture.swift, ShowSceneSnapshot.swift, AppCoordinator+SceneHistory.swift, AppCoordinator+Show.swift
├── Views/VideoLoopControls.swift  # new
├── Views/SettingsView.swift, VisualizerView.swift
├── Visuals/VideoVisualHost.swift
├── Tests/VideoLoopTests.swift     # new
└── UITests/VideoLoopUITests.swift # new
scripts/run_device_tests.py        # allowed key
```

**Structure Decision**: extend the `VideoLayer` target and the Video visual; no new target.

## Complexity Tracking

None.
