# Research: AUD-008 Input Trim

## AUD-008-D1: Where the trim sits

- **Decision**: A `NormalizedPCMReader` decorator around the analysis tap (`InputTrimReader`). The
  tap reader copies frames out of its ring into the consumer's buffer (`SPSCRingBuffer.read(into:)`);
  the decorator scales that buffer after the copy. The tap's ring, the main normalized ring
  (projectM), the PCM sink and the classifier never see the gain.
- **Rationale**: The tap already is the "feature-extraction copy" (ANL-001-R9). A decorator is the
  pattern VIS-003 used for `WaveformTap` and keeps ANL-016's pipeline, which ANL-003 is changing in
  parallel, untouched. Every consumer receives the tap from `AppCoordinator`, so one helper covers
  all seven call sites (five native hosts, the oscilloscope host and the tempo's own analysis).
- **Alternatives**: gain in the `Normalizer` or `PCMSink` (changes projectM's input and silence
  detection: violates R1); a gain stage inside `AnalysisPipeline` (two packages and two consumers
  to change, conflicts with ANL-003); scaling the FFT magnitudes (the waveform would not follow and
  saturation could not be modelled).

## AUD-008-D2: Gain law and saturation

- **Decision**: g = 10^(dB/20), dB clamped to [−12, +24], NaN → 0. Unity gain with no ramp: return
  immediately (bit-exact). Otherwise y = softClip(x·g) with a cubic knee: linear for |v| ≤ 0.5,
  `0.5 + 0.5·(u − 4u³/27)`, u = (|v| − 0.5)/0.5, for 0.5 < |v| < 1.25, and ±1 beyond; NaN → 0.
  The cubic f(u) = u − 4u³/27 has f(0) = 0, f'(0) = 1 (continuous slope at the knee), f(1.5) = 1 and
  f'(1.5) = 0, so the curve meets ±1 smoothly.
- **Rationale**: Below −6 dBFS after gain the law is exact, so a test tone changes level by exactly
  the trim (the acceptance criterion). A smooth knee adds far fewer harmonics than a hard clip
  (which would light the upper bands at high trims). No libm call per sample; ±∞ handled by the
  ≥ 1.25 branch, NaN by an explicit check.
- **Alternatives**: hard clip; tanh (libm per sample, never exactly ±1); a limiter with look-ahead
  (state, latency, out of scope for an S row).

## AUD-008-D3: Ramp

- **Decision**: Linear in linear gain, 2,048 frames per change (≈ 46 ms, one 2,048-point FFT
  window), per frame, carried across reads. A new target mid-ramp restarts the ramp from the current
  gain. The final frame sets the gain to the target exactly (so returning to 0 dB is bit-exact
  again). Bound on the per-frame change: (g(24) − g(−12))/2,048 ≈ 0.00762.
- **Rationale**: A step between two FFT frames would show as a one-frame jump in every band (a
  "zipper" in features); one window spreads it over the frames that overlap it.
- **Alternatives**: one-pole smoothing (never exactly reaches the target, breaks bit-exactness);
  per-read step (depends on read size).

## AUD-008-D4: Sharing the target across threads

- **Decision**: `InputTrimControl` stores the target dB as `Float.bitPattern` in an
  `Atomic<UInt32>` (relaxed store from the main actor, relaxed load per read on the analysis
  worker). Each reader converts to linear only when the loaded dB differs from its last one.
- **Rationale**: Lock-free, allocation-free, no ordering needed (a single independent value).

## AUD-008-D5: Session changes and new readers

- **Decision**: A new reader starts at the target with no ramp. Each read compares the wrapped
  reader's `analysisSessionGeneration` with the last one seen; on a change the gain snaps to the
  target.
- **Rationale**: A new session restarts the analysis (ANL-016-R9), so there is no continuity to
  protect; snapping avoids a fade-in at the start of every source.

## AUD-008-D6: Settings and storage

- **Decision**: `InputTrimSetting` (@Observable, @MainActor) owns the key
  `settings.inputTrim.decibels` and the `InputTrimControl`; `didSet` clamps, rounds to whole dB,
  stores and updates the control. Settings gets an "Audio Analysis" section built in its own view
  file (`InputTrimSection`) with a 1 dB-step `Slider`, a readout, and a Reset button. Labels are
  built by a typed static function (`InputTrimSetting.text(for:)`), not inline string arithmetic.
- **Rationale**: Separate files keep ANL-003's and ACC-004's edits to `AppSettings`/`SettingsView`
  from colliding with this row; the formatter is unit-testable.
