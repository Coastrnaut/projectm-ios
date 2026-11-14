# Data Model: FX-009 Motion Feedback

## MotionFeedback (value, `Packages/Compositor`, plain Swift, Linux-testable)

| Field | Range | Default | Step hint | Meaning |
|---|---|---|---|---|
| isEnabled | Bool | false | — | Trails on |
| halfLifeSeconds | 0.05…0.50 (user); effective may be lower | 0.20 | 0.01 | time for a trail to fade to half |

- `clamped`: NaN → default, out of range → nearest bound (user values).
- `isActive`: enabled and half-life > 0.
- `decay(frameDuration:) -> Double`: `min(0.5^(Δt/h), 0.99)`; Δt NaN or negative → 0 (research FX-009-D2).
- `limited(by: SafetyClamp) -> MotionFeedback`: research FX-009-D6 (cap = 0.5 × intensity limit, ≤ 0.25 with
  Reduce flashing; cap 0 → disabled).
- `static blend(current:previous:decay:reset:) -> SIMD4<Float>`: the CPU reference of `cmp_trails` (D1, D4).

## Compositor state (Metal)

- `motionFeedback: MotionFeedback` (default off); setting an inactive value returns the pair to the pool; inactive →
  active sets the reset flag.
- `trailsHistory`, `trailsTarget: MTLTexture?` — pooled, composite size; nil while inactive.
- `trailsResetPending: Bool`; `lastOutputFormat: MTLPixelFormat?`.
- `trailsFrames` (frames drawn through the pass), `trailsResets` (reset frames) — tests, diagnostics.

## Shader block `CMPTrails` (16 bytes)

`float decay; uint reset; uint pad0; uint pad1;`

## MotionFeedbackCatalog (MOD-001)

| ID | Kind | Range / default | Unit | Modulation |
|---|---|---|---|---|
| `effect.feedback.enabled` | boolean | false | none | discrete manual |
| `effect.feedback.halfLife` | continuous | 0.05…0.50, default 0.20, step 0.01 | seconds | continuous default |

Group `effect.feedback` ("Trails").

## App setting `MotionFeedbackSetting`

| Key | Type | Absent |
|---|---|---|
| `settings.feedback.enabled` | Bool | false |
| `settings.feedback.halfLife` | Double | 0.20 |

`allKeys` = both; in `LibrarySettingsPolicy.includedKeys`, `ALLOWED_KEYS` and the UI-test reset.

## State transitions (one compositor)

```
off ──enable──▶ active(reset pending) ──frame──▶ active(trailing) ──frame──▶ …
active ──scene change / size / format / render-health reset / unfinished frame──▶ active(reset pending)
active ──disable or cap 0──▶ off (pair returned to the pool)
```
