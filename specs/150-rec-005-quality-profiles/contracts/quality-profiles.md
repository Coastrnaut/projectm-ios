# Contract: REC-005 quality profiles

## C1 — Profile table (in-app text and tests use the same values)

| Profile | Long side at most | Codec | Average bit rate | Frame rate |
|---|---|---|---|---|
| Draft | 1280 | H.264 | 4 Mb/s | 30 fps |
| Standard (default) | 1920 | HEVC, else H.264 | REC-003 rule (≈ 7.5 Mb/s at 1080×1920 HEVC) | 30 fps |
| High | 2560 | HEVC | 20 Mb/s | 60 fps |
| Max | screen | HEVC | 40 Mb/s | 60 fps |

No profile upscales: output = the even-cropped drawable, scaled down to the cap with its aspect.

## C2 — Availability (FrameRecording)

```swift
public protocol RecordingEncoderCapabilities: Sendable {
    func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool
    var maxFramesPerSecond: Int { get }
}
public enum RecordingQualityCatalog {
    static func availability(of: RecordingQualityProfile, drawableWidth: Int, drawableHeight: Int,
                             capabilities: any RecordingEncoderCapabilities) -> RecordingProfileAvailability
    static func resolve(_ selected: RecordingQualityProfile, drawableWidth: Int, drawableHeight: Int,
                        capabilities: any RecordingEncoderCapabilities) -> RecordingProfileResolution
}
```

Rules, in order: frame rate above `maxFramesPerSecond` → `frameRateUnsupported`; no codec of the
preference encodable at 1280×720 → `hevcUnavailable` (only for HEVC-only profiles; Draft and Standard
fall to `sizeUnsupported`); no codec encodable at the output size → `sizeUnsupported`; else available
with the first encodable codec.

## C3 — App

- Settings → "Recording quality" section, directly before REC-004's "Recording" section. One row per profile: identifier `recordingQuality.<rawValue>`, label "<Title>, <W>×<H>, <codec>, <bit rate>, <fps>" (or "<Title>, unavailable: <reason>"), `.isSelected` trait on the chosen row, disabled rows not tappable. Footer: the profile table in one line per profile.
- Record (`VideoRecordingCoordinator.start`): after the REC-003 refusals, resolve with the drawable; `.refuse` → `refuse` with `RecordingFailure.encoderUnavailable.notice`; a fallback sets `notice` to the fallback text after the recording started (status X9c, through `StatusEventCatalog.recordingNotice`).
- Key `settings.recording.qualityProfile`: in `excludedKeys`, `ALLOWED_KEYS`, and removed by `-uitestResetNotice`.
