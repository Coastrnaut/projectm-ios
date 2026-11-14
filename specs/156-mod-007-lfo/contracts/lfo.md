# Contract: LFO (MOD-007)

## L1 Oscillator

`LFO(shape:rateHz:phaseOffset: = 0, amplitude: = 1, center: = 0.5)`; `validationProblem: String?` is nil
exactly when MOD-007-R1 holds (finite; rate 0.01…20 Hz; phase, amplitude, center 0…1).

## L2 Value

`func phase(elapsedNanoseconds: UInt64, rateHz: Double) -> Double` in 0…<1 and
`func value(elapsedNanoseconds: UInt64, maximumRateHz: Double = .infinity) -> Double` in 0…1:
φ = frac(phaseOffset + min(rateHz, maximumRateHz)·t); value = clamp(center + amplitude/2 · w(φ), 0, 1)
(research MOD-007-D1, D2). Pure, allocation-free, deterministic.

## L3 Bank

`LFOBank`: `maximumOscillators = 8`; `reduceFlashingMaximumRateHz = 3`; `set(_ oscillators: [LFO?]) throws(LFOError)`
(validates all; replaces all; clears the origin); `oscillators`; `hasOscillators`;
`values(atNanoseconds:maximumRateHz:into: UnsafeMutableBufferPointer<Double>)` (origin on first call; elapsed 0
for t ≤ origin; slot i gets oscillator i's value or 0). No allocation per call.

## L4 Binding source

`AudioFeatureSource.lfo(Int)`: ID `audio.lfo.<index>`, `init?(id:)` parses index 0…7 only; `value(in:)` reads
`frame.lfos[index]` (missing or non-finite → 0, clamped 0…1). `AudioFeatureModulator.bind` refuses index outside
0…7 with `AudioFeatureBindingError.lfoIndexOutOfRange`. Expressions do not accept LFO names.

## L5 Scene field

Optional top-level `lfos`: array of objects, each kept verbatim; written only when non-nil.
Entry keys: `shape` (`"sine"`, `"triangle"`; required), `rate` (Hz; required), `phase`, `amplitude`, `center`
(optional; defaults 0, 1, 0.5). A non-object entry is a decode error; more than 64 entries refuse the document.

## L6 Scene issues (warnings; the scene loads; the entry is kept)

| Problem | Code | Path |
|---|---|---|
| missing or non-string `shape`, missing or non-finite number | `invalidLFO` | `$.lfos[i].<key>` |
| out-of-range values | `invalidLFO` | `$.lfos[i]` |
| unknown `shape` | `unknownLFO` | `$.lfos[i].shape` |
| entry beyond 8 | `invalidLFO` | `$.lfos[i]` |

## L7 App

The native visual gets the current scene's oscillators when created; each frame the bank's values at the frame's
display time (capped at 3 Hz while Reduce flashing is effective) are passed to the bindings as `frame.lfos`.
