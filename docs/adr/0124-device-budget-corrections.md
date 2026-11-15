# ADR-0124: QA-010 budget corrections from the first device measurements

- **Status**: Accepted (2026-11-15, decided under the owner's standing delegation; owner rule 12)
- **Context feature**: QA-011 final device matrix; changes QA-010's `docs/performance/thresholds.json` (version 2)

## Context

On 2026-11-15 the QA-011 matrix measured every QA-010 metric on D1 (iPhone 15) and D2 (iPad Pro 13-inch M5) for the
first time (a new `perf012` automation mode supplies the PERF-012 report). Three results failed:

| Metric | D1 | D2 | Limit (version 1) |
|---|---|---|---|
| `audioAgeP95Ms` | 96.7 ms (p50 35.6) | 76.8 ms | 50 |
| `peakMemoryMB` | 243 MB | 466 MB | 300 |
| `fps1sP5` | 60.1 | 45.0 (warm rerun 58) | 55 |

Investigation:

1. **Audio age.** The judge reads PERF-013's `audioSync.p95Ms`: the time from the audio entering analysis to the
   presented frame. Its limit cited R-06's *normalized ring residency* (≤ 50 ms), which is one part of that span. R-06's
   SC-006 budget gives the span itself as residency ≤ 50 ms plus engine frame and display ≤ 50 ms, and PERF-013-S5
   calls an age under 100 ms plausible. The metric and its limit described different quantities.
2. **Peak memory on D2.** SC-008 sets 300 MB for the reference device only and asks D2 and D3 to be "measured and
   published"; QA-010 had copied 300 MB to them without a measurement. D2's footprint (344 MB, peak 466 MB) is about
   twice D1's (174 / 243 MB), in line with its 1.88× pixel count; the report shows no leak.
3. **First-second frame rate.** `perf001` sampled five 1-second windows, so the nearest-rank 5th percentile was the
   single worst second. On D2 the first second after a fresh install ran at 44-45 fps while Metal's shader caches
   were cold; the next nine seconds and a warm rerun were at 58-60 fps. SC-005 is defined over 95% of 1-second
   windows of a session, not over five.

## Decision

1. `audioAgeP95Ms` ≤ **100 ms** on every class (SC-006's analysis-to-presentation share; PERF-013-S5).
2. `peakMemoryMB`: D1 stays at 300 MB (SC-008). D2 **600 MB** and D3 **400 MB**: the reference budget scaled by
   pixel count (5.68 M and 3.87 M against D1's 3.01 M), rounded up to 50 MB.
3. `perf001` samples **60** one-second windows (`fpsTimerOff`) from the same start, so the cold first second still
   counts, as one window of 60. The limit stays 55 fps.

## Consequences

- `thresholdsVersion` 2; the measured values are published in the QA-011 records and test report.
- D1's audio age passes with little margin (96.7 of 100 ms); it is reported as such, and the 136 ms maximum and a
  drift detection during the visual switch are noted for PERF-013's own device check (PERF-013-S5).
- The cold-cache first second on D2 remains a known first-launch cost (PERF-009's warm-up territory), not hidden:
  it stays in the 60 windows.
- None of these changes alters app behaviour.
