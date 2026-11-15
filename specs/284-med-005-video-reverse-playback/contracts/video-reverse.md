# Contract: Video reverse playback (MED-005)

## C1 — Layer API (`VideoLayer`)

- `VideoLayerSource.reverse: Bool` (default false). Setting true with file content starts a cache
  build; false drops the cache and restarts forward decoding at the shown picture.
- `VideoLayerSource.reverseLimits: VideoReverseLimits` (default `.standard`) and
  `reverseBudgetBytes: Int` (default `AnimatedFrameBudget.current`), read when a build starts.
- `VideoLayerSource.reverseState: VideoReverseState`; `onReverseStateChange` is called on the main
  actor after each change.
- `VideoLayerSource.reverseShownIndex: Int?` (cached picture shown last), `reversePeakBytes: Int`.
- `render` never decodes, waits or allocates for reverse; it tries the driver's lock once.

## C2 — Selection (pure)

`VideoReverseTimeline.index(elapsedNanoseconds:region:startMediaNanoseconds:) -> Int`: research
MED-005-D4. For a 12-picture, 30 fps clip with no region and no start, elapsed k / 30 s (+ < 1/30 s)
gives picture 11 − (k mod 12).

## C3 — Messages

| Reason | Text |
|---|---|
| tooLong | Reverse playback is available for clips up to 30 seconds. This video plays forward. |
| tooLarge | Reverse playback is available for clips up to 1080p. This video plays forward. |
| undecodable | This video can't be played in reverse. It plays forward. |

Settings caption while preparing: "Preparing reverse…".

## C4 — App

- Settings → Video: toggle "Reverse" (`videoReverseToggle`), caption `videoReverseStatus`, shown
  while a video is stored, under Speed.
- DEBUG probe `videoReverse`: `"<state> <index|none>"`, state ∈ off, preparing, playing,
  unsupported.
- UserDefaults `settings.video.reverse` = `{"id": "<UUID>"}`.
