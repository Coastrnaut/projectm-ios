# Data Model: VIS-001 Circular Spectrum

All types are in `Packages/VisualGenerators` unless marked "app".

## SpectrumBarCount (enum, Int raw value)

`b16 = 16`, `b32 = 32`, `b64 = 64`, `b128 = 128`; `maximum = 128`. Mirrors ANL-002's `BandCount`
without depending on it (VIS-001-D1).

## RingDirection (enum)

`clockwise` (d = +1, default), `counterClockwise` (d = −1).

## VisualPalette (enum)

| Case | Colors (sRGB) | Bar k of N |
|---|---|---|
| `spectrum` (default) | HSV hue 0° → 270° at full saturation and value | hue = 270° · k / (N − 1) |
| `ice` | `#2EC4FF` → `#E8F7FF` | linear interpolation (in linear light) by k / (N − 1) |
| `mono` | `#FFFFFF` | constant |

Colors are converted to linear once per configuration; `relativeLuminance(linear)` = 0.2126 R +
0.7152 G + 0.0722 B.

## CircularSpectrumConfiguration (struct, Sendable, Equatable)

| Field | Type | Range (clamped) | Default |
|---|---|---|---|
| barCount | SpectrumBarCount | 16/32/64/128 | 64 |
| innerRadius | Double (radius units) | 0.05…0.9 | 0.3 |
| lengthScale | Double | 0…(1 − innerRadius) | 0.65 |
| gap | Double (fraction of pitch) | 0…0.9 | 0.2 |
| rotationOffsetDegrees | Double | any finite (non-finite → 0) | 0 |
| startAngleDegrees | Double | any finite (non-finite → 0) | 0 |
| direction | RingDirection | — | clockwise |
| palette | VisualPalette | — | spectrum |
| background | LinearColor (premultiplied RGBA) | components 0…1 | opaque black |

Derived: `pitchDegrees = 360 / N`; `halfWidthDegrees = (1 − gap) · pitch / 2`;
`centerDegrees(k) = start + d · (k + 0.5) · pitch + offset` (not reduced mod 360 in the API; the
layout reports it normalized to [0, 360)).

## BarGeometry (struct)

`centerDegrees` [0, 360), `halfWidthDegrees`, `innerRadius` and `outerRadius` (pixels),
`color` (LinearColor, before the flash gain). Lit ⇔ `outerRadius > innerRadius`.

## CircularSpectrumLayout (final class, not Sendable; one owner)

Preallocated `BarGeometry` × 128 and vertex scratch. State: configuration, output width/height
(pixels), `radiusUnit = min(W, H) / 2`, centre `(W/2, H/2)`.
- `layout(values:width:height:)`: sanitizes values (VIS-001-R8), fills `bars[0..<N]`.
- `tessellate(into:capacity:gain:) -> Int`: writes `SpectrumVertex` (x, y in NDC; premultiplied
  r, g, b, a) for lit bars, 24 per bar; returns the count.
- `meanRelativeLuminance(gain:)`: Σ area_k · Y_k · gain / (W · H) + background luminance × uncovered
  fraction.
- Screen mapping: angle θ clockwise from up; pixel `(cx + r·sin θ, cy − r·cos θ)` (y down);
  NDC `(2x/W − 1, 1 − 2y/H)`.

## SpectrumVertex (struct, 24 bytes)

`x, y, r, g, b, a: Float` — matches the shader's `packed_float2` + `packed_float4`.

## FlashSafetyLimiter (final class, not Sendable)

State: `displayed[128]`, `previousLuminance`, `hasPrevious`. Constants: `maxBarStepPerSecond = 4.0`,
`maxLuminanceRisePerSecond = 0.25`, `maxFrameTime = 0.1`.
- `limitValues(targets:count:frameTime:enabled:) -> UnsafeBufferPointer<Float>`: slew when enabled,
  copy when not.
- `gain(forLuminance:frameTime:enabled:) -> Float`: when enabled and the unlimited luminance rises
  more than the step, `gain = (previous + step) / luminance`, else 1; records the displayed
  luminance. `reset()` restarts from the next frame.

## BandFrameBuffer (final class, Sendable)

Three slots of `[Float]` capacity 128 (allocated in init), `count`, `timestampNanoseconds`,
`sequence`; `Atomic<Int>` middle index with a fresh bit.
- Writer (one thread): `write(values:count:timestamp:)`.
- Reader (one thread): `readLatest(into:capacity:) -> BandFrameInfo?` (nil when nothing new;
  the reader keeps its last values).

## SpectrumBandFeed (final class, not Sendable) — target VisualBandFeed

Owns `SpectrumStream` (2,048, hop 512, mid, 44.1 kHz), `BandReducer` (44.1 kHz), a 128-Float band
scratch, the band count. `pull(from: NormalizedPCMReader) -> Bool` (true when at least one new
spectrum was reduced; the newest is in `bands`), `setBandCount`, `reset()`. Scale: decibels, floor
`BandMath.defaultFloorDecibels` (−80 dB).

## LiveBandAnalyzer (final class, Sendable via confinement) — target VisualBandFeed

Serial queue, `DispatchSourceTimer` (10 ms) created on `start(reader:)`, cancelled on `stop()`;
`setBandCount(_:)` takes effect at the next tick; output `BandFrameBuffer`. States: stopped ⇄
running; `start` while running and `stop` while stopped do nothing.

## App (Apps/projectM-iOS)

- `VisualChoice` (String raw value): `projectM` (default), `circularSpectrum`; stored under
  `settings.visual`; unknown → projectM.
- `AppSettings.circularSpectrumBars`: Int under `settings.circularSpectrum.bars`; not in
  {16, 32, 64, 128} → 64.
- `AppCoordinator`: `showsNativeVisual = settings.visual == .circularSpectrum && nativeVisual != nil
  && screen == .visualizer`; `nativeVisualUnavailable: Bool` (creation failed this launch).
- `CircularSpectrumHost`: states running / paused (user or projectM shown) / suspended (PERF-011);
  draws only when running and not suspended.
