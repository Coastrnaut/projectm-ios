# Research: PERF-002 GPU budget meter

## PERF-002-D1 Deadline source

- **Decision**: target fps = min(display maximum refresh rate, the visual's frame-rate cap); invalid (≤ 0, NaN, ∞) inputs are ignored; nothing valid → 60 fps. Period = 1000 / fps ms.
- **Rationale**: every visual's `CADisplayLink.preferredFrameRateRange` comes from `QualityGovernor` (cap 60, 30 under Low Power / serious thermal), bounded by `UIScreen.maximumFramesPerSecond`. On a 120 Hz iPad Pro the app still targets 60 fps, so a 8.33 ms deadline would flag constantly.
- **Alternatives**: reading `CADisplayLink.targetTimestamp − timestamp` per frame (needs frame-path work and a display link handle in the meter); the screen's maximum alone (wrong under the cap).

## PERF-002-D2 Per-pass GPU timing

- **Decision**: no new GPU instrumentation. GPU passes are each stage's GPU figure where PERF-001 has it (none today) and the whole frame's GPU time (`gpu frame`). CPU passes use PERF-001's frame-thread times (encode work), labelled `cpu`.
- **Rationale**: `MTLCounterSampleBuffer` with `.atStageBoundary` sampling is public, but needs a sample buffer attachment on every render/compute pass descriptor in the compositor and each visual, resolving after completion, and device support checks (`supportsCounterSampling(.atStageBoundary)`); it would touch `Compositor.swift`, which other agents edit in parallel, and adds per-frame resolve work. Splitting the command buffer per pass adds a commit per pass per frame. Attributing the frame's GPU time to passes by CPU encode share would invent numbers (forbidden).
- **Limitation (documented in the overlay contract)**: a GPU-heavy pass shows up as `gpu frame` over budget, not by name; the CPU pass names point at the frame-thread cost. A follow-up can feed `FrameStageTimer.record(_:gpuSeconds:)` from counter samples and the meter flags them without change.

## PERF-002-D3 Statistic and threshold

- **Decision**: p95 over PERF-001's 120-frame window against `thresholdShare × deadline` (0.80); flag when strictly greater; clear below `clearShare × deadline` (0.70); at least 30 samples to change state.
- **Rationale**: p95 ignores single hiccups but catches regular overruns; a 10-point hysteresis band stops a pass hovering at the line from blinking every second.

## PERF-002-D4 Estimate

- **Decision**: cpu estimate = sum of the measured stages' CPU p95 (an upper-bound style figure: the p95 of a sum is at most the sum of p95s for co-occurring peaks, and usually less); gpu estimate = the frame GPU p95. Shown separately, never added (CPU and GPU work overlap in a pipelined frame). Unavailable when nothing was measured.
- **Rationale**: "bounded render-time estimate" — bounded by the fixed window and stated as a conservative bound, never extrapolated.

## PERF-002-D5 Accessibility

- **Decision**: no announcement; the flag lines are part of the overlay's combined accessibility label (already `.combine`). Highlight colour plus the "over budget:" text, so colour is not the only cue.
- **Rationale**: the overlay refreshes every second; announcements would interrupt a performer and `check_status_events.py` would need a new lane for a diagnostic.

## PERF-002-D6 DEBUG injection

- **Decision**: `-uitestSlowStage <stage>:<ms>` (DEBUG only, `ProcessInfo.arguments`) replaces that stage's CPU statistic in the report handed to the meter and the overlay with `measured(samples: n, median: ms, p95: ms)`, n = the stage's real sample count. Rendering is untouched.
- **Rationale**: proves the overlay path end to end in the simulator without slowing a real frame (no sleeps on the frame thread, which would also slow the UI test).

## PERF-002-D7 Where the meter state lives

- **Decision**: in `FrameStageAttachment` (owned by the coordinator), reset whenever the timer is attached to another visual or stopped.
- **Rationale**: the same lifetime as the window it judges; no edit to `AppCoordinator.swift`.
