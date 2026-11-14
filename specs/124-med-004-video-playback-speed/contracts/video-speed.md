# Contract: Video playback speed (MED-004)

## C1 — `VideoPlaybackSpeed` (VideoLayer, every platform)

- C1.1 `VideoPlaybackSpeed(percent:)` succeeds exactly for 25, 50, 75, 100, 125, 150, 200.
- C1.2 `VideoPlaybackSpeed.all` lists them ascending; `.normal.percent == 100`.
- C1.3 `prerollLeadNanoseconds` is 500 000 000 for percent ≤ 100 and 500 000 000 × percent / 100
  above.

## C2 — `VideoPlaybackClock`

- C2.1 First `advance` returns the current playback time without adding (unchanged).
- C2.2 A step s in (0, 1 s] adds ⌊(s × percent + r) / 100⌋ and carries the remainder r; over any
  sequence the total added is ⌊Σs × percent / 100⌋ (no drift) while the speed is constant.
- C2.3 A step > 1 s or ≤ 0 adds nothing and leaves the remainder (unchanged rule).
- C2.4 `setSpeed` keeps `playbackNanoseconds` (no jump) and zeroes the measurement window;
  `presentationSinceSpeedChange` / `playbackSinceSpeedChange` sum counted steps and added time.
- C2.5 `reset()` keeps the speed.

## C3 — Pipeline and layer

- C3.1 `VideoDecodePipeline.setSpeed(_:)` changes the running session's pre-roll lead without a
  restart (no new open, `seeks` unchanged); later sessions start with it.
- C3.2 The session prepares the pass at in once the picture read is within
  `speed.prerollLeadNanoseconds` of out.
- C3.3 `VideoLayerSource.playbackSpeed` sets the clock and the pipeline; it never stops, starts
  or seeks the decoder and never drops the held picture.
- C3.4 Loop wraps at any speed: shown pictures stay in [in, out), the wrap lateness is recorded as
  before (`maxWrapLatenessNanoseconds`).

## C4 — App

- C4.1 `VideoStore.speed(for:)` / `setSpeed(_:for:)` on `settings.video.speed`; 1× removes the key.
- C4.2 `VideoCoordinator.setSpeed(_:)` saves, then calls `onSpeedChange` at once (no settle).
- C4.3 `VideoCoordinator.restoreSpeed(storeID:speedPercent:)` applies only for the stored video
  (FILE-008 shared payloads count); nil storeID changes nothing; nil percent = 1×.
- C4.4 Settings → Video shows `Picker` "Speed" (identifier `videoSpeedPicker`) whenever a video is
  stored; options' accessibility labels as research D7.
- C4.5 DEBUG probe `videoSpeed`: `"<percent> ratio=<playbackSince / presentationSince, 3 decimals>"`
  (`ratio=none` before any counted step).
- C4.6 No audio source state (capture manager mode, In-App Playback transport) is read or written
  by any speed path.

## C5 — Scene field

- C5.1 `SceneAsset.videoSpeedPercent` get: the `video` asset's `extra["speedPercent"]` when it is
  an integer in 1…Int32.max, else nil; other kinds nil. Set nil removes the field; set on another
  kind does nothing.
- C5.2 Capture writes `speedPercent` only for a speed other than 1×.
