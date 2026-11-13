# Data Model: MED-002 Import Video Layer

## VideoImportLimits (plain Swift)

| Field | Value (standard) | Rule |
|---|---|---|
| maxFileBytes | 500 × 1024 × 1024 | larger → `.tooLarge` |
| maxLongestSide | 4096 | larger picture → `.pictureTooLarge` |
| maxFrameRate | 60.5 | higher nominal rate → `.frameRateTooHigh` |
| codecs | H.264 (`avc1`, `avc3`), HEVC (`hvc1`, `hev1`) | other → `.unsupportedCodec` |

## VideoImportError (plain Swift, Equatable, Sendable)

`notAVideo`, `tooLarge`, `unsupportedCodec`, `pictureTooLarge`, `frameRateTooHigh`, `damaged`,
`unreadable`, `saveFailed`; each has a plain `message` (R14).

## VideoTrackInfo (plain Swift)

`width`, `height` (encoded picture), `rotation` (`CameraRotation` from the preferred transform),
`frameRate` (nominal), `durationNanoseconds` (> 0), `codec` (`VideoCodec.h264/.hevc`). Upright size:
width/height swapped when the rotation swaps axes.

## VideoPlaybackClock (plain Swift)

State: `previousPresentation: UInt64?`, `playbackNanoseconds: Int64`. `advance(to presentation)`:
first call → 0; Δ in (0, 1 s] adds Δ; Δ > 1 s or Δ ≤ 0 adds 0. `reset()`.

## VideoDecodePipeline<Frame> (plain Swift)

- Queue: at most `capacity` (3) `TimedFrame<Frame>(pts: Int64, frame: Frame)`, oldest first.
- Counters: `framesDecoded`, `framesTaken` (became the shown frame), `framesDropped` (late),
  `maxDepth`, `seeks`, `loops`.
- State: `idle`, `running`, `failed(VideoImportError)`, `stopped`.
- `target`: the latest playback time the render side asked for (read by the decoder for seeks).
- Rule: `take(upTo t)` removes every queued frame with `pts ≤ t`, returns the newest (others dropped).

## Stored video (app)

`StoredVideo(id: UUID, url: URL)`; file `Application Support/Videos/<UUID>.mov`; settings key
`settings.video.id` (canonical UUID string). Invalid or missing → cleared, "no video".

## VideoLayerState

`empty` → (content set) `loading` → `playing(width, height)` (upright size) or `failed(error)`;
setting `content = .none` → `empty`.
