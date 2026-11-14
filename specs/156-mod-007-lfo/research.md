# Research: MOD-007 LFO Sine and Triangle

## MOD-007-D1 Waveform definition

- **Decision**: φ = frac(phaseOffset + rate·t); bipolar wave w(φ): sine sin(2πφ); triangle 4φ on
  [0, ¼), 2 − 4φ on [¼, ¾), 4φ − 4 on [¾, 1). Output = clamp(centre + amplitude/2 · w, 0, 1).
- **Rationale**: the triangle has the sine's zero crossings and peaks, so switching shape keeps the
  timing; amplitude as peak-to-peak fraction makes amplitude 1, centre 0.5 the full 0…1 sweep that
  bindings expect (their input range is 0…1).
- **Alternatives**: a unipolar 0…1 wave scaled by amplitude from 0 (centre implicit) — rejected: the
  brief asks for an offset/centre and a breathing parameter needs a centre.

## MOD-007-D2 Exact phase from integer time

- **Decision**: elapsed time is a `UInt64` of nanoseconds. Split into whole seconds `s` and remainder
  `r` (< 1e9). p = rate·s rounded; e = fma(rate, s, −p) is its exact rounding error; frac(p) is exact
  in floating point. φ = frac(frac(p) + e + rate·r·1e-9 + phaseOffset).
- **Rationale**: no accumulated state (no drift), and the multi-hour product's rounding error is
  recovered by the fused multiply-add, so the phase error stays ~1e-16 cycles even after days; the
  1e-9 acceptance has nine orders of margin. Pure stdlib (`addingProduct`), builds on Linux.
- **Alternatives**: integer modulo the period in nanoseconds — exact only when the period is an
  integer number of nanoseconds (rate 0.3 Hz is not); an accumulated phase — drifts with frame jitter.

## MOD-007-D3 Origin and bank

- **Decision**: `LFOBank` holds up to 8 oscillators and one origin, set at the first sample after
  `set(_:)`; elapsed = t − origin, or 0 when t ≤ origin.
- **Rationale**: a scene's oscillators keep their stored phase relation; restarting at scene load is
  predictable; no wall clock.

## MOD-007-D4 Binding source

- **Decision**: `AudioFeatureSource.lfo(Int)`, ID `audio.lfo.<index>` (0…7, decimal, no leading zero),
  value read from `AudioFeatureFrame.lfos[index]` (finite, clamped 0…1; missing → 0). The binding
  validator refuses an out-of-range index with the new error `lfoIndexOutOfRange`. Expression catalog
  rejects LFO names; the compiler's exhaustive switch emits constant 0 for the unreachable case. The
  inspector names them "LFO 1"… .
- **Rationale**: every existing path that parses a source ID (scene bindings, connections, MOD-013
  restore, migrations, which require the `audio.` prefix) keeps working unchanged, and an older app
  orphans instead of drops the binding. Range, curve, envelope, mix and ACC-012 apply unchanged.
- **Alternatives**: a separate `ModulationSource` enum (changes `AudioFeatureBinding.source`'s type,
  breaking MOD-002 callers); a `lfo.` prefix (older apps reject and drop the binding); a graph generator
  node (the graph has no evaluator yet; MOD-008/009 inputs such as rate modulation can add it).

## MOD-007-D5 Flash safety

- **Decision**: `LFOBank.reduceFlashingMaximumRateHz = 3`; effective rate = min(rate, cap). The app
  passes the cap while `NativeSpectrumHost.reduceFlashing` (ACC-012's effective setting) is true.
- **Rationale**: 3 per second is WCAG 2.3.1's flash threshold and the app's FR-072 basis; a 20 Hz LFO
  on brightness would otherwise strobe. The stored rate is untouched.

## MOD-007-D6 Scene field

- **Decision**: optional top-level `lfos` array of objects kept verbatim:
  `{"shape": "sine", "rate": 0.5, "phase": 0, "amplitude": 1, "center": 0.5}` (`shape`, `rate` required;
  others default). Issues: `invalidLFO` (missing/wrong field, out of range, beyond 8), `unknownLFO`
  (unknown shape), warnings at the entry's path; entries accepted at all: 64.
- **Rationale**: mirrors MOD-006 `triggers` exactly; format version unchanged; QA-004 gains no row.
  `read` keeps positions (nil for an unusable entry) because bindings name an oscillator by index.

## MOD-007-D7 App feed

- **Decision**: `NativeSpectrumHost.setLFOs(_:)` replaces the bank (origin restarts);
  `applyModulation` fills an 8-slot scratch with the bank's values and passes it as `frame.lfos`.
  `AppCoordinator.connectLFOs(_:)` sets the scene's oscillators when the native visual is created,
  before the restored bindings are bound; the scene carry writes `lfos` back unchanged.
- **Rationale**: the same path as MOD-006 triggers; allocation-free per frame.
