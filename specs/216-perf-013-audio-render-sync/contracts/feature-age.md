# Contract: feature age meter and overlay line (PERF-013)

## C1 Meter
- `frame(stamp, arrival, presentation)`, frame thread, once per presented frame; `stamp` nil = no frame consumed yet
  this session (no sample). A stamp with a new `sequence` is an observation (residual = arrival − busHost).
- Age sample = presentation − (busHost + applied correction) of the newest consumed stamp; < 0 → anomaly.
- Correction step per call ≤ 0.25 ms, toward the target, never past it. Session change → estimate, correction and
  the newest stamp reset (histograms of the counting session are not reset by an analysis session change).
- `beginCountingSession()` (each overlay attach): the counting figures, the estimate, the correction and the newest
  stamp reset (another visual feeds another pipeline); the app-session histogram (the report's) is kept.

## C2 Overlay line
- `audio age <smoothed> ms p95 <p95> ms` + ` offset <n> ms` when the AUD-013 offset is > 0 + `, drift <±n> ppm
  corrected` when detected. One decimal place.
- No consuming visual or no sample yet: `audio age unavailable`.

## C3 Signpost
- `DiagnosticsLog.audioSync("drift detected <ppm> ppm")` / `("drift cleared")` on a verdict change seen at the
  overlay refresh; numbers only.

## C4 Report
- `audioSync` (optional) in the PERF-012 report, schema version 1 (amended): `sampleCount` ≥ 1, `p50Ms`, `p95Ms`,
  `maxMs`, `driftDetected`, `driftPpm` (only when detected), `detections`.
