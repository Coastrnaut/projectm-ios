# Contract: attack/release envelope (MOD-005)

Package `ParameterGraph`, types `AudioFeatureEnvelope` and `AudioFeatureModulator`.

## E1 Definition

`attackSeconds` and `releaseSeconds` are one-pole time constants τ. After a step of the target from
s₀ to x at t = 0 (and no further change), the signal is `x + (s₀ − x)·exp(−t/τ)`: 63.2 % of the
distance at t = τ. The 10–90 % rise time is `τ·ln 9`; `riseTime10To90(timeConstant:)` and
`timeConstant(riseTime10To90:)` convert.

## E2 Step

`step(from current: Double, toward target: Double, elapsedSeconds: Double) -> Double`:

1. A non-finite `target` reads 0; `target` is clamped to 0…1.
2. A non-finite `current` returns the target.
3. τ = `attackSeconds` when target > current, else `releaseSeconds`.
4. τ ≤ 0 (or not finite) returns the target.
5. `elapsedSeconds` ≤ 0 or not finite returns `current` clamped to 0…1.
6. Otherwise returns `current + (target − current)·(1 − exp(−elapsedSeconds/τ))`, clamped to 0…1.

Pure, deterministic, allocation-free.

## E3 Frame-rate independence

For any sequence of positive Δt with constant target, the result after Σ Δt equals the analytic
curve of E1 up to rounding (≤ 1e-9 absolute in tests; the acceptance tolerance is 0.01).

## E4 Clock (modulator, MOD-002, unchanged)

Δt comes from `advance(frame:timeNanoseconds:)`: 0 on a binding's first advance or when the time does
not increase; at most 0.25 s per advance.

## E5 Validation (unchanged)

Times must be finite and within 0…60 s; `bind` and `setEnvelope` throw `invalidEnvelope` otherwise
and leave the modulator unchanged.

## E6 Live change

`setEnvelope(_ envelope:, for target:) throws(AudioFeatureBindingError)`: `unknownTarget` when the
target is not bound; `invalidEnvelope` per E5; otherwise the binding's envelope is replaced and its
signal and clock are kept, so the next advance continues from the current signal.

## E7 Scenes

The optional `envelope {attack, release}` object is unchanged (missing fields = 0). An invalid
envelope rejects the binding at restore, keeps it for re-save, and reports SCN-012 `invalidBinding`
at `$.bindings[i].envelope`.
