# Research: REC-014 Export aspect presets

## REC-014-D1: Crop to fill in the writer's scaler

- **Decision**: The pixel buffer stays the drawable's even size (REC-003); when the output's aspect differs from the drawable's, the writer's output settings use `AVVideoScalingModeResizeAspectFill`, which scales the source uniformly to cover the output and crops the centre.
- **Rationale**: No change to the five visual hosts' encode closures and no extra GPU pass or texture; the encoder's scaler (already used for REC-003's downscale with `ResizeAspect`) does the work off the frame loop (REC-014-R11).
- **Alternatives**: a crop rectangle passed to every host's encode (five hosts, compositor viewport changes, more frame-loop code); letterboxing (`ResizeAspect`: mostly bars on phones; rejected in Clarifications).

## REC-014-D2: Exact even multiples of the preset ratio, never upscaled

- **Decision**: For a preset with reduced ratio u:v the output is (u·m, v·m) with the largest m such that both sides are even (m even when u or v is odd), u·m ≤ the crop width and v·m ≤ the crop height (the centred crop of the even drawable at u:v, floored), max(u,v)·m ≤ min(profile long side, cap side), and u·v·m² ≤ cap pixels. Fewer than one step → no picture.
- **Rationale**: the file's ratio is exact (REC-014-R3) and dimensions are predictable (1080×1920, 1152×648, 1178×1178), testable as exact numbers.
- **Alternatives**: scale-and-round each side (aspect off by a pixel; non-obvious sizes).

## REC-014-D3: Custom sizes

- **Decision**: Validation when entered: odd → round down to even; clamp to 128...4096. At planning: exactly W×H when it fits all limits (crop, profile side, cap); otherwise the exact even multiple of W:H's reduced ratio (D2) when its long side is at least 90% of the uniform-scale fallback, else uniform scale with both sides floored to even (at least 2). Either way the geometry is marked reduced and Record adds the X9c notice.
- **Rationale**: Keeps the aspect exact whenever the ratio is small (4:5, 2:3) and close when it is not (959:540).

## REC-014-D4: Device memory cap

- **Decision**: `RecordingOutputCap` with two classes by `ProcessInfo.physicalMemory`: compact (< 4 GiB) max side 2560, max pixels 3 686 400 (2560×1440); regular max side 4096, max pixels 8 294 400 (3840×2160); max side also ≤ the GPU texture side (16 384 on every Apple GPU family the app supports, iOS 26 = A12 or later). Applied to every output (Match screen too), through `RecordingEncoderCapabilities.outputCap` (default regular, so injected test capabilities and existing callers keep working).
- **Rationale**: the encoder's frames, its reference frames and the pool of scaled buffers grow with the output's pixels; 4K-class frames on small-memory devices risk jetsam during long recordings. Every current screen fits its class's cap (largest: iPad Pro 13" 2064×2752 = 5.7 MP, regular; 3 GB devices have ≤ 2160 px screens), so Match screen recordings are unchanged on real devices.
- **Alternatives**: a cap from `os_proc_available_memory` (changes from moment to moment, so Settings and Record would disagree); encoder caps only (`canEncode` accepts 8K on recent devices).

## REC-014-D5: Where the aspect lives

- **Decision**: `RecordingSettings.aspect` and `.outputCap` (defaults Match screen, regular), so `RecordingGeometry(drawableWidth:drawableHeight:settings:)` builds the same geometry in the catalog, the recorder and the storage estimate. Catalog functions take `aspect:` (default Match screen) and read the cap from the capabilities.
