# Data Model: REC-014 Export aspect presets

## RecordingAspect (FrameRecording, plain Swift)

| Case | Ratio | Stored kind |
|---|---|---|
| `matchScreen` (default) | the drawable's | `screen` |
| `portrait` | 9:16 | `portrait` |
| `square` | 1:1 | `square` |
| `landscape` | 16:9 | `landscape` |
| `custom(RecordingCustomSize)` | W:H | `custom` (+ width, height) |

`RecordingAspect.Kind` (String raw values above, CaseIterable) is what Settings stores; unknown → `screen`.

## RecordingCustomSize

- `width`, `height`: Int, each even, 128...4096 (`init(width:height:)` validates: odd rounds down, then clamps). Default 1080×1350.

## RecordingOutputCap

- `maxSide`, `maxPixels`. `compact` = 2560 / 3 686 400; `regular` = 4096 / 8 294 400.
- `device(physicalMemory:maxTextureSide:)`: compact below 4 GiB, else regular; `maxSide` ≤ `maxTextureSide`.
- `contains(width:height:)`.

## RecordingSettings (extended)

- `aspect: RecordingAspect = .matchScreen`, `outputCap: RecordingOutputCap = .regular`.

## RecordingGeometry (extended)

- `sourceWidth/Height` (unchanged: the even drawable), `outputWidth/Height`.
- `cropsToFill: Bool` — true for every aspect but Match screen.
- `reducedCustomSize: RecordingCustomSize?` — the asked size when a custom size was reduced.
- `init?(drawableWidth:drawableHeight:settings:)`; the old `init?(drawableWidth:drawableHeight:maxLongSide:)` is Match screen with the regular cap.

## Device-local keys (app)

| Key | Values | Default |
|---|---|---|
| `settings.recording.aspect` | `screen`, `portrait`, `square`, `landscape`, `custom` | `screen` |
| `settings.recording.customWidth` | Int | 1080 |
| `settings.recording.customHeight` | Int | 1350 |

Not backed up, erased with the Settings category, removed by `-uitestResetNotice`.
