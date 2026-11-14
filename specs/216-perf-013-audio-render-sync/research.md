# Research: PERF-013 Audio-render synchronization

## PERF-013-D1 What clock pair is compared

- **Decision**: the bus host time of a feature frame (ANL-016: session anchor + session sample at the nominal
  44.1 kHz) against the monotonic host time at which the frame loop first reads that frame (`MonotonicClock`,
  CLOCK_UPTIME_RAW, the same clock as `CADisplayLink` timestamps × 10⁹). The presentation time is the display link's
  `targetTimestamp`.
- **Rationale**: the anchor is taken once per session, so any rate difference between the audio clock and the host
  clock accumulates linearly in the residual `arrival − busHost`. Both clocks are already available on the frame
  thread; no capture or pipeline change is needed (the pipeline's injected clock and its existing tests stay as
  they are).
- **Alternatives**: re-anchoring inside `AnalysisPipeline` per chunk (changes ANL-016's clock contract and its tests);
  AVAudioTime host times from the capture backends (not carried through the normalized ring).

## PERF-013-D2 Drift estimator

- **Decision**: residual r (ns) per first-read frame; bucket by audio time e = sessionSample / 44,100 into 1 s
  buckets keeping the minimum r and its e; least-squares slope through up to 64 bucket minima (ring); verdict needs
  ≥ 10 buckets; detect |slope| ≥ 50 ppm and ≥ 3 standard errors, clear < 25 ppm. A closing bucket whose minimum
  differs from the previous bucket's minimum + slope × Δe by more than 10 ms is a step: it starts a new segment, and
  the fit is a pooled within-segment regression (one slope, one intercept per segment), so a step never biases the
  slope and no history is lost.
- **Measured during implementation** (AudioClockDriftTests' simulation: 512-sample hop, 0-10 ms one-sided jitter,
  60 Hz reads): each bucket minimum carries about 1 ms of noise (the read quantization beats against the hop). With
  8 buckets and no drift the slope reached ±100 ppm, and 4 ms steps fired spuriously. A lower-convex-hull fit (the
  classic one-way-delay skew estimate) was tried and rejected: its two-point edges were noisier than least squares.
  Restarting the fit after a step and holding the slope gave 7 ms errors (a short refit's slope error times the
  whole session's audio time); segment intercepts fixed that.
- **Rationale**: arrival jitter (10 ms worker timer, 512-sample hop, display interval) is one-sided, so the minimum
  per bucket tracks the floor latency; a linear fit of the floor gives the drift. 64 buckets bound the work (once per
  second) and memory (preallocated). Steps (AUD-013 offset slews, route changes) are not drift.
- **Alternatives**: least squares on raw observations (jitter of ±5 ms gives ±150 ppm slope noise over 10 s); a
  PLL-style filter (harder to bound and prove "never overshoots").

## PERF-013-D3 Correction

- **Decision**: target = slope × e (ns) while detected, 0 otherwise; the applied correction moves toward the target by
  at most 0.25 ms per presented frame and stops at it. Corrected audio time = bus host time + applied correction.
- **Rationale**: the intercept of the fit is the true pipeline latency, which belongs to the age; only the slope is
  clock error. Slew-limited, monotone approach to the target cannot overshoot the target; the target cannot overshoot
  the truth beyond the slope error × e.
- **Budget**: ±500 ppm → verdict at about 11-13 s (error up to 6 ms before it), catch-up at 0.25 ms per frame,
  error ≤ 3 ms from 15 s and ≤ 2 ms from 30 s to 60 s, correction ≤ 2 ms past the truth (four jitter sequences).

## PERF-013-D4 Age statistics

- **Decision**: age = presentation − corrected audio time of the newest consumed frame, every frame. EMA with time
  constant 0.5 s for the "smoothed" figure; PERF-012's `FrameIntervalHistogram` (0.1 ms buckets to 250 ms, exact max)
  for p50/p95/max; negative ages counted as anomalies. Two histograms: the overlay's counting session and the app
  session (the report), matching PERF-012's since-launch scope.

## PERF-013-D5 Where the meter attaches

- **Decision**: like PERF-007: an attachment holds one meter and sets it on the shown visual while the overlay is
  shown; attaching begins a counting session. projectM (`ANGLERenderer`) consumes no feature frames: "unavailable".
- **Rationale**: same cost gating as the existing telemetry (PERF-013-R11).
