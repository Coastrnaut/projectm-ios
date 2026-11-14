# MED-004 Video playback speed — test report (2026-11-14)

Spec: `specs/124-med-004-video-playback-speed/`. Branch `feature/med-004`. Host: the Mac Studio
(Xcode 27.2, iOS 27.2 simulator "MED4 iPhone 17", created for this run and deleted afterwards).
Simulator results are never device evidence (Constitution X).

## Audit (baseline `13491ae3`)

- The video's own time came from `VideoPlaybackClock` (presentation-time steps, 1×); the decode
  queue, MED-003's loop mapping and its recovery already work in that video time.
- The video has no sound: the stored copy is remuxed without a soundtrack (MED-002-R16) and the
  reader reads the video track only. `VideoLayer` imports no audio or capture module and uses no
  `AVAudio*`/`AVPlayer` API (checked by `VideoSpeedTests.testSpeedNeverReachesTheAudioSource`).
- The app sets the speed in three places, all on the Video visual's host; the audio source (In-App
  Playback, Microphone, System/App Capture), its transport and the analysis are never touched.

## Design as built

- Speeds: 0.25×, 0.5×, 0.75×, 1×, 1.25×, 1.5×, 2× (integer percent; no 0, nothing above 2×).
- Clock: `added = (step × percent + remainder) / 100`, remainder carried: exact, no drift. A speed
  change keeps the video time (continuous) and does not restart the decoder.
- Loop region (MED-003): unchanged, in video time; the pre-roll lead is 0.5 s × speed above 1×
  (1 s of video at 2× = 0.5 s of wall time), 0.5 s of video at or below 1×.
- Above 1×: playback never waits; the shown picture is the newest one due; a decoder that falls
  behind drops late pictures and seeks when more than 1 s behind.
- Storage: `settings.video.speed` = `{id, percent}` (1× = no key); excluded from FILE-005 backups;
  FILE-011 "Photos and videos" erases it; Remove Video and a new video clear it; scenes and cues
  carry `speedPercent` on the video asset (no version change).
- UI: Settings → Video, "Speed" menu picker above the loop sliders; VoiceOver reads "Half speed",
  "1.5 times", "Double speed"; footer "Speed changes only the video, never the music."

## Results

| Check | Result |
|---|---|
| Acceptance (injected 60 Hz clock): 2 s presented at 0.5× | video +1 000 000 000 ns exactly (criterion: within one picture interval); 1× +2 s, 2× +4 s, 0.25×/0.75×/1.5× likewise |
| Real H.264 fixture, 0.5× and 2× | every pixel index = ⌊video time × 30⌋ mod 30 over 122 frames; +1 s / +4 s over 2 s presented; dropped 0 (decoder waited per step) |
| Speed change mid-play | continuous (first step adds step × new speed); no open, no seek |
| Slow decoder at 2× (half the needed rate) | playback still exactly 2 × presentation every step; picture never early or back; lag < 1.2 s; seeks ≥ 1 |
| Loop region [0.5 s, 1.0 s) at 0.5× and 2× (fake reader) | all pictures inside, wraps 29 → 15, ≥ 3 wraps, gap 0 frames |
| Same on the real file | wraps 3 at each speed; measured joint lateness 5 ms (0.5×) and 20 ms (2×), i.e. the sampling phase, gap 0 frames |
| Pre-roll | first preparation after picture 45 at 0.5×/1×, 38 at 1.5×, 30 at 2× |
| UI test on the simulator (0.5×) | probe `50 ratio=0.500`, frame index 246 → 252 while sampling; 22.0 s |
| UI test at Accessibility L text | Speed picked ("Double speed"), probe `200 ratio=…`; 19.2 s |

## Commands (durations on the Mac Studio)

- `swift test --package-path Packages/Compositor`: 408 tests, 6 skipped, 0 failures (12.7 s of tests, 43 s with the build).
- Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, VideoSpeedTests, VideoLoopTests, VideoPipelineTests): 29 tests, 0 failures, 1.4 s.
- `swift test --package-path Packages/SceneFormat`: 114 tests, 0 failures (2.0 s); `Packages/LibraryBackup`: 44 tests, 0 failures (1.6 s).
- `projectM-iOSTests` on the simulator: 565 tests, 0 failures (22.9 s of tests).
- UI: VideoSpeedUITests 2/2 (22.0 s, 19.2 s); VideoLayerUITests 1/1 (23.3 s); VideoLoopUITests 1/1 (29.0 s; region 500-1100, gap 3 frames at 1× on the shared simulator, as MED-003 reported).
- `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`: OK; `test_scripts.py`: 153 tests OK (1 skipped); `check_privacy_manifest.py` on the Debug app: OK.
- Long-body flags (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`): no warning in the new or changed MED-004 code; one existing warning (`SettingsView.body`, 330 ms) predates this feature.
- PosterBoard reports: 25 before, 25 after.

## Not verified here

- `{device}` MED-004-T22 (S7): decoding 4K/60 fps at 2× on D1, smoothness at 0.25×, music unchanged
  with In-App Playback at every speed.
