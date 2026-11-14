# Data Model: REC-005 Record quality profiles

## RecordingQualityProfile (FrameRecording, plain Swift)

| Field | Draft | Standard | High | Max |
|---|---|---|---|---|
| `rawValue` (stored) | `draft` | `standard` | `high` | `max` |
| `maxLongSide` | 1280 | 1920 | 2560 | none (the drawable) |
| `codecPreference` | [H.264] | [HEVC, H.264] | [HEVC] | [HEVC] |
| `fixedBitRate` | 4,000,000 | nil (REC-003 rule) | 20,000,000 | 40,000,000 |
| `frameRate` | 30 | 30 | 60 | 60 |

- `settings: RecordingSettings`: Standard returns `RecordingSettings.standard`; Max uses `RecordingSettings.nativeLongSide` (16,384, above any drawable) so the geometry never scales.
- `fallbackOrder`: max, high, standard, draft (`CaseIterable` order is draft…max).
- `title`, `documentation` ("Up to 1280 px · H.264 · 4 Mb/s · 30 fps").

## RecordingSettings (extended)

- `fixedBitRate: Int?` (default nil, ≥ 100,000 when set).
- `averageBitRate(codec:width:height:) -> Int`: fixed rate, else `codec.averageBitRate(width:height:frameRate:)`.

## RecordingEncoderCapabilities (protocol)

- `canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool`
- `maxFramesPerSecond: Int`

Implementations: `VideoToolboxEncoderCapabilities` (Apple; cached), test stubs.

## RecordingProfileAvailability

- `.available(RecordingProfilePlan)` — plan = profile, geometry (output size), codec it will use (first encodable in its preference), settings.
- `.unavailable(RecordingUnavailableReason)`:
  - `hevcUnavailable` — "Needs HEVC, which this device cannot encode."
  - `sizeUnsupported(width, height)` — "This device cannot encode W×H."
  - `frameRateUnsupported(max)` — "Needs 60 fps; this display shows at most N."
  - `noPicture` — "No picture to record." (drawable under 2×2)

## RecordingProfileResolution

- `.record(plan, fallbackFrom: RecordingQualityProfile?, reason: RecordingUnavailableReason?)`
- `.refuse` — no profile is available.
- `fallbackNotice` — "Recording at Standard: Needs HEVC, which this device cannot encode."

## RecordedVideoInfo (extended)

- `nominalFrameRate: Double` (frames / duration), `videoBytes: Int`, `averageVideoBitRate: Double` (videoBytes × 8 / duration).

## RecordingQualitySetting (app)

- `profile: RecordingQualityProfile` (didSet stores `rawValue`), key `settings.recording.qualityProfile`, default Standard.
- `availability(_:) -> RecordingProfileAvailability` for the rows, from the capability source and the rows' size closure.
