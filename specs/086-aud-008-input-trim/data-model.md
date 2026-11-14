# Data Model: AUD-008 Input Trim

## InputTrim (constants and law; AudioCore)

| Field | Value |
|---|---|
| `minimumDecibels` | −12 |
| `maximumDecibels` | +24 |
| `defaultDecibels` | 0 |
| `rampFrames` | 2,048 |
| `kneeLevel` | 0.5 |
| `clipStart` (where the curve reaches ±1) | 1.25 |
| `clamped(_ dB)` | NaN → 0, else min(max(dB, −12), 24) |
| `linearGain(decibels:)` | 10^(clamped/20) |
| `softClip(_ v)` | see contract C1 |
| `maximumRampStep` | (linearGain(24) − linearGain(−12)) / 2,048 |

## InputTrimControl (shared, Sendable)

| Field | Type | Notes |
|---|---|---|
| target | `Atomic<UInt32>` (Float bits, dB) | written by the app, read per analysis read; always clamped |

## InputTrimProcessor (per reader, value type, scalar only)

| Field | Type | Notes |
|---|---|---|
| gain | Float | current linear gain |
| targetGain | Float | linear gain of `targetDecibels` |
| targetDecibels | Float | last target seen |
| step | Float | per-frame increment of the active ramp |
| remaining | Int | frames left in the ramp (0 = settled) |

State transitions: settled(g) —new target t ≠ current target→ ramping(g → t, 2,048 frames) —frames
pass→ settled(t). snap(t): settled(t) immediately (new reader, new session).

## InputTrimSetting (app, @MainActor @Observable)

| Field | Type | Key | Default |
|---|---|---|---|
| decibels | Double (whole dB, −12…24) | `settings.inputTrim.decibels` | 0 (absent, NaN or not a number) |
| control | `InputTrimControl` | — | kept equal to `decibels` |
