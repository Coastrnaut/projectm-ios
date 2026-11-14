# Research: MED-004 Video Playback Speed

Decisions made by Claude under the owner's standing approval (owner rules 4 and 9).

## MED-004-D1 — Where speed applies

- **Decision**: in `VideoPlaybackClock`: the step added per frame is the presentation step times
  the speed. The clock's playback time is already the video's own unwrapped time, so the decode
  queue (`take(upTo:)`, catch-up, seeks), the loop region's mapping `base + k × L + (pts − in)` and
  its recovery are unchanged.
- **Rationale**: one multiplication at the single place where wall time becomes video time; the
  header of `VideoPlaybackClock` already reserved it ("MED-004 (speed) scales the added
  difference"). Every MED-002/MED-003 test stays valid at 1×.
- **Alternatives**: retiming pictures in the decode session (`time = base + (pts − in) / speed`):
  rejected, a speed change would invalidate queued pictures and need a restart; `AVPlayer.rate`:
  rejected, the layer does not use AVPlayer (bounded reader queue, MED-002-D3).

## MED-004-D2 — Exact arithmetic

- **Decision**: speed is an integer percentage; per step `scaled = step × percent + remainder`,
  `added = scaled / 100`, `remainder = scaled % 100`. With steps ≤ 1 s (10⁹ ns) and percent ≤ 200,
  `scaled` < 2.1 × 10¹¹, far inside `Int64`. The sum of added steps equals ⌊total × percent / 100⌋
  exactly, so there is no drift over any session length.
- **Alternatives**: `Double` multiplier: rejected, rounding per frame drifts (60 frames × 0.5 ns
  per second) and makes the acceptance test depend on tolerances.

## MED-004-D3 — Pre-roll at higher speeds

- **Decision**: the session's pre-roll lead (video time) is `0.5 s × max(percent, 100) / 100`:
  1 s of video at 2× (still 0.5 s of wall time), 0.5 s of video at or below 1× (1 s or 2 s of wall
  time at 0.5× and 0.25×: earlier, never later). Only one prepared reader exists at a time
  (MED-003-D3), so a longer lead costs no extra memory.
- **Check**: at 2× with a 0.5 s video-time lead the reader would be asked only 0.25 s of wall time
  before out; the fake-reader test asserts the preparation happens at the scaled lead.

## MED-004-D4 — Speed changes and speeds above 1×

- **Decision**: a change only sets the clock's and the pipeline's speed. The playback time is
  continuous (the clock integrates), the queued pictures stay valid (their times are video
  times), and the decoder is not restarted. Above 1× the decoder must produce speed × frame rate
  pictures per second; when it falls behind, the existing catch-up drops late pictures and a lag
  above 1 s of video time seeks (MED-002-R10). Playback never waits for the decoder: the shown
  picture is always the newest one due at the current video time.
- **Measured**: the Mac host decodes the 64 × 48 fixture far faster than 2× (the real-file test
  shows every expected picture with 0 dropped at 2× when each step waits for the decoder);
  device throughput for 4K at 2× is `{device}` (MED-004-S7).
- **Alternatives**: slowing down when the decoder lags: rejected, the video would drift from the
  chosen speed and from scene timing.

## MED-004-D5 — Storage, backup and erase

- **Decision**: `settings.video.speed` = `{"id": <UUID>, "percent": <Int>}`; 1× is stored as no
  key. Read only when `id` is the stored video and `percent` is one of the seven; otherwise
  removed. Remove Video and a new current video remove it (as `settings.video.loop`). Excluded
  from FILE-005 backups (the video and its loop are excluded: a speed without its video means
  nothing); FILE-011's "Photos and videos" category removes it with the video and its loop.
- **Alternatives**: a global speed for every video: rejected, inconsistent with the per-video
  loop region and surprising after importing a new clip.

## MED-004-D6 — Scene field

- **Decision**: optional integer `speedPercent` on a `video` asset, written only when not 100.
  `SceneAsset.videoSpeedPercent` returns any positive integer that fits `Int32` (SceneFormat does
  not know the speed set); the app maps it through `VideoPlaybackSpeed(percent:)`, so anything
  outside the set plays at 1×. Older apps carry the field verbatim (`SceneAsset.extra`), no
  version change (CMP-006 rule, MED-003-D6 precedent).

## MED-004-D7 — Control and spoken values

- **Decision**: a SwiftUI menu `Picker("Speed", …)` with seven tags, shown "0.25×" … "2×", each
  option carrying an accessibility label in words: "Quarter speed", "Half speed",
  "Three-quarter speed", "Normal speed", "1.25 times", "1.5 times", "Double speed". The strings
  are built in typed steps. Shown whenever a video is stored. A pick saves and applies at once and
  is one undo step (the scene history observes `sceneInputs`).
- **Alternatives**: ACC-005 slider: rejected (discrete safe set; seven stops), segmented control:
  rejected (does not fit at large text sizes).

## MED-004-D8 — Independence from the audio source

- **Audit**: the stored copy has no soundtrack (`VideoSanitizer`, MED-002-R16); the reader opens
  the video track only; `VideoLayer` imports `AVFoundation`, `CoreMedia`, `Metal`, `Compositor`,
  `CameraLayer`, `MediaSniffing` and Foundation only, no AudioCore or CaptureKit. Speed is set on
  the Video visual's host and nowhere else.
- **Test** (as built): `VideoSpeedTests.testSpeedNeverReachesTheAudioSource` (app) checks that no
  `VideoLayer` source imports an audio or capture module or uses `AVAudio*`/`AVPlayer`/`audioMix`,
  and that the only three speed setters in the app are on the Video visual's host; the coordinator
  path is tested with no audio object at all. Building a second `AppCoordinator` in the hosted test
  (to compare the capture manager and transport) was rejected: it would start a second audio
  pipeline inside the host app. Package tests assert the speed changes only the video time.
