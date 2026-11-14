# Contract: frame budget meter (PERF-002)

## C1 Deadline

`FrameDeadline(displayMaximumFPS: Double?, frameRateCap: Double?)`: fps = min of the valid inputs, else 60.
60 → 16.67 ms, 120 → 8.33 ms, 30 → 33.33 ms (± 0.01).

## C2 Evaluation

`FrameBudgetMeter.evaluate(_ report: FrameStageReport, deadline: FrameDeadline) -> FrameBudgetVerdict`

- Passes, in frame order: for each reported stage, its CPU pass (always listed; unavailable if not measured)
  and its GPU pass (listed only when measured); then `gpu frame` (always listed).
- A pass is over when it is available, has ≥ `minimumSamples`, and p95 > threshold; it stays over until
  p95 < clear level with ≥ `minimumSamples`. An unavailable pass is never over and loses any flag.
- Pure function of (report, deadline, previous flags). Never touches a renderer, timer or frame.
- Allocates only for the verdict (once a second with the overlay), never on the frame path.

## C3 Overlay lines

```
budget 16.67 ms @60 fps, limit 13.33 ms (80%)
estimate cpu 4.10 ms, gpu 3.20 ms        (or "cpu unavailable" / "gpu unavailable")
over budget: composite cpu 14.20 ms > 13.33 ms     (one per flagged pass)
```

Numbers use two decimals; fps is rounded to an integer. Lines starting with `over budget:` are highlighted
by the overlay and read by VoiceOver as part of the overlay label. No announcement.

## C4 Export

`DiagnosticsSnapshot.FrameTimings.budget` (optional). Without it the JSON is byte-identical to PERF-001's
and validates against the schema.

## C5 DEBUG injection

`-uitestSlowStage <stage>:<ms>` (DEBUG builds only). Replaces the CPU statistic of `<stage>` in the
report given to the overlay and the meter; it has no effect when the stage is not in the shown visual's
pipeline or has no samples yet. Rendering is untouched.
