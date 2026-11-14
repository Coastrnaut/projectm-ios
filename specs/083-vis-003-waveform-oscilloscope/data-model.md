# Data Model: VIS-003 Waveform Oscilloscope

## OscilloscopeConfiguration (value)

| Field | Type | Range / default |
|---|---|---|
| windowMilliseconds | Int | 10, 20 (default), 40 offered; clamped 5…40 |
| lineThickness | Double | fraction of the shorter output side, 0.001…0.05; default 0.008 (Medium) |
| amplitude | Double | fraction of the half height a full-scale sample reaches, 0.1…1; default 0.9 |
| palette | VisualPalette | default `.spectrum` |
| background | LinearColor | premultiplied linear; default opaque black |

`windowSamples = round(windowMilliseconds × 44.1)` (441, 882, 1,764). Non-finite values take defaults.

## WaveformTriggerResult (value)

| Field | Meaning |
|---|---|
| start | fractional history index of the window's first sample |
| mode | `.triggered` or `.freeRun(reason)` with reason `silence`, `noCrossing`, `aperiodic` |
| crossingCount | qualifying crossings found |
| periodSamples | mean crossing interval (nil with fewer than 2 crossings) |

## WaveformTrigger (state, fixed storage)

- `crossings`: ≤ 32 fractional positions (ring of the newest).
- `reference`: 64 floats + `hasReference`.
- `scores`: ≤ 32 doubles.

## Waveform history (WaveformFrameBuffer slots)

Three slots of 4,096 floats; per slot: `written` (total samples written so far, UInt64). Oldest
sample first, newest last; before 4,096 samples arrived the leading part is 0.

## OscilloscopeLayout (state, fixed storage)

- `points`: ≤ 1,024 (x, y) pixel positions.
- `segments`: ≤ 1,023 rectangles (4 corners each) and ≤ 1,022 bevel triangles, and their colors.
- The FX-019 area model: `SpectrumFlashAreas(regionCapacity: 2,045)` (rectangles, then bevels).

## User settings

| Key | Values | Unknown / absent |
|---|---|---|
| `settings.visual` | adds `oscilloscope` | projectM |
| `settings.oscilloscope.line` | `thin`, `medium`, `thick` | medium |
| `settings.oscilloscope.window` | 10, 20, 40 (Int, ms) | 20 |
