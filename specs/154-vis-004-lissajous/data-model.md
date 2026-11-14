# Data Model: VIS-004 Lissajous Scope

## LissajousMode (package, `String` raw value)

| Case | Stored | x | y |
|---|---|---|---|
| `xy` (default) | `xy` | L | R |
| `midSide` | `midSide` | (R − L)/√2 | (L + R)/√2 |

## LissajousConfiguration (package)

| Field | Type | Range / default |
|---|---|---|
| `mode` | LissajousMode | `.xy` |
| `persistenceHalfLife` | Double seconds | 0 (off) or 0.01…0.5; non-finite or negative → 0 |
| `lineThickness` | Double, fraction of the shorter side | 0.001…0.05, default 0.006 |
| `palette` | VisualPalette | `.spectrum` |
| `background` | LinearColor | opaque black |

Constants: `nominalHalfLife` 0.2 s; `persistenceHalfLife(enabled:clamp:)` returns 0 when disabled,
else min(0.2, intensity limit × 0.5 when the clamp caps intensity, 0.25 with Reduce flashing); a cap
≤ 0 returns 0.

## LissajousAutoGain (package, value type)

| Field | Meaning |
|---|---|
| `level` | current full-scale reference, ≥ 0.01 |
| `sinceRise` | seconds since the last rise |

`update(peak:frameDuration:) -> Double`; constants `floor` 0.01, `holdSeconds` 0.5,
`releaseHalfLife` 0.5, `maxFrameDuration` 0.1. `reset()` returns to the floor.

## Stereo history (VisualBandFeed)

`WaveformTap.stereoOutput: WaveformFrameBuffer` — 4,096 floats = the newest 2,048 frames
interleaved (L, R), oldest first; total = frames written.

## Snapshot (internal to LissajousLayout)

128 normalized points (u, v in −1…1) and the frame-clock time it was taken. Ring of 8.

## Settings (app)

| Key | Type | Default | Invalid |
|---|---|---|---|
| `settings.visual` | String | `projectM` | `lissajous` is new |
| `settings.lissajous.mode` | String | `xy` | anything else → `xy` |
| `settings.lissajous.persistence` | Bool | false | absent → false |

## State transitions

- Loop restart (pause/resume): gain reset, snapshots cleared, clock 0.
- Mode change: snapshots cleared, gain kept.
- Persistence half-life → 0: snapshots cleared.
