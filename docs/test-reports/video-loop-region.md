# MED-003 Video loop region — test report (2026-11-14)

Spec: `specs/106-med-003-video-loop-region/`. Mac Studio, Xcode 27.2, own simulator "MED3 iPhone 17"
(iOS 27.2, deleted afterwards). No device run (MED-003-T20 `{device}` open). Simulator results are
never device evidence (Constitution X).

## Audit (before MED-003)

- The decode pipeline looped the whole file: at the end of the file it reopened the reader at 0 on
  an unwrapped timeline (`loop × duration + pts`); a stall over 1 s reopened at
  `playback mod duration`; a resume restarted at the clock's playback time.
- A pass with no picture, or any reader error, ended the session as `.failed` (transparent layer,
  "The video couldn't be played."), even an error near the end of an otherwise good file.
- MED-014's container check ran before every open (kept).

## What changed

- `VideoLoopRegion` (in/out, 0.25 s minimum, clamping) and a region timeline in the pipeline:
  `base + k × L + (pts − in)`; every open inside [in, out), the reader's time range ends at out,
  pictures before in skipped (the covering picture only for an empty pass), a picture at or after
  out ends the pass.
- Pre-roll: within 0.5 s of out the reader prepares the pass at in; `AVVideoFrameReader` starts one
  standby `AVAssetReader` and takes it over at the joint (pictures keep the `CVMetalTextureHold` of
  the shared cache).
- Recovery: EOF, an early end, or a reader error after a picture continue at in and are counted
  (`loops`, `earlyEnds`, `recoveredErrors`); a failed open or three bad passes in a row fail as before.
- App: `settings.video.loop` per video ID; Loop in / Loop out sliders and Reset Loop in Settings →
  Video; settle-then-apply; scenes, undo states and show cues carry `loop` on the video asset.

## Measured gap at the joint

| Where | How | Result |
|---|---|---|
| Fake reader (host and Linux shape) | `VideoLoopTests.testRegionLoopsAcrossFourBoundariesWithoutAGap`, 75 steps, 4 wraps | every picture due in its own slot: gap 0 frames |
| Real H.264 fixture, host Metal | `VideoLayerTests.testLoopRegionOnARealFileStaysInsideAcrossBoundaries`, 3 wraps | max wrap lateness < 1 frame: gap 0 frames |
| Simulator, real time | `VideoLoopUITests`, region 600-1100 ms, 17 wraps per run | run 1: gap 0 frames; run 2: gap 3 frames (max over 17 wraps, 30 fps timeline) |

The simulator figure is informational only (software decoding on a shared Mac); the visible joint
is checked on D1 (MED-003-T20).

## Commands and results

| Command | Result |
|---|---|
| `swift test --package-path Packages/Compositor` | 296 tests, 0 failures, 3 skipped, 23.4 s of tests (after merging `autonomous/integration`) |
| same, `--filter 'VideoLoopTests\|VideoPipelineTests'` with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE` | 19 tests, 0 failures, 0.8 s |
| `swift test --package-path Packages/SceneFormat` | 101 tests, 0 failures, 3.1 s; Linux shape of `SceneVideoLoopTests` and `SceneSourceSafetyTests`: 5 tests, 0 failures |
| `xcodebuild test` `-only-testing:projectM-iOSTests` | 469 tests, 0 failures, 11.2 s of tests (VideoLoopTests 4/4) |
| `xcodebuild test` `VideoLoopUITests`, `VideoLayerUITests` | both passed: 22.8 s and 23.4 s |
| `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events` | OK |
| `test_scripts.py` | 151 tests OK (1 skipped) |
| `check_privacy_manifest.py` on the Debug simulator app | OK |
| PosterBoard reports | 25 before, 25 after |
