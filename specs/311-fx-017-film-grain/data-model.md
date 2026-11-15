# Data Model: FX-017 Film grain

## FilmGrain (Compositor, plain Swift)

| Field | Type | Range / default | Rule |
|-------|------|-----------------|------|
| isEnabled | Bool | false | off = no pass |
| opacity | Double | 0…1, 0.3 | NaN → default, else clamped |
| size | Int | 1…3, 1 | clamped (Double inputs rounded) |
| isColor | Bool | false | false = monochrome (channel 0 for r, g, b) |
| seed | Int | 0…9999, 1 | clamped (Double inputs rounded, NaN → default) |
| isAnimated | Bool | false | temporal variation |

- `amplitude` = 0.08 (fixed); `scale` = Float(opacity) × 0.08.
- `isActive(width:height:)`: on, opacity > 0 and frame ≥ 2 × 2.
- `grainFrame(presentationTimeNanoseconds:reduceFlashing:)`: 0 unless animated and not Reduce flashing; else
  UInt32(truncatingIfNeeded: t ÷ 41 666 667) (`framePeriodNanoseconds`).
- `effective(reduceMotion:)`: `isAnimated` false when Reduce Motion is on (app).
- `Block` (shader `CMPFilmGrain`, 32 bytes, `setFragmentBytes`): `scale: Float` (0 when off), `size: UInt32`,
  `seed: UInt32`, `frame: UInt32`, `channels: UInt32` (1 monochrome, 3 colour), three `UInt32` pads.

## Settings keys (app)

`settings.filmGrain.enabled` (Bool), `.opacity` (Double), `.size` (Int), `.color` (Bool), `.seed` (Int),
`.animated` (Bool).

## Scene entry

`fx.filmGrain`: `opacity` 0…1, `size` 1…3, `color` 0…1 (≥ 0.5 colour), `seed` 0…9999, `animated` 0…1 (≥ 0.5 on).
