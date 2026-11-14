# Data model: PERF-002 GPU budget meter

## FrameDeadline (value)

| Field | Type | Rule |
|---|---|---|
| framesPerSecond | Double | min of the valid (finite, > 0) inputs, else 60 |
| periodMs | Double | 1000 / framesPerSecond |

## FrameBudgetPolicy (value)

| Field | Default | Clamp |
|---|---|---|
| thresholdShare | 0.80 | (0, 1]; invalid → 0.80 |
| clearShare | 0.70 | (0, thresholdShare]; invalid → min(0.70, threshold) |
| minimumSamples | 30 | ≥ 1 |

## BudgetPass (value)

Either `stage(FrameStage, domain)` with domain `cpu` or `gpu`, or `frameGPU`. Label: `"composite cpu"`,
`"render gpu"`, `"gpu frame"`. Flag bit index: cpu = stage.rawValue (0-5), gpu = 6 + rawValue (6-11),
frameGPU = 12.

## PassStatus (value)

`pass`, `p95Ms: Double?` (nil = unavailable), `samples: Int`, `isOver: Bool` (only when p95 available).

## FrameBudgetVerdict (value)

| Field | Meaning |
|---|---|
| deadline | FrameDeadline |
| policy | FrameBudgetPolicy |
| thresholdMs, clearMs | share × period |
| passes | PassStatus per reported stage (cpu, then gpu when measured) + frame GPU, frame order |
| cpuEstimateMs | sum of measured CPU p95, or nil |
| gpuEstimateMs | frame GPU p95, or nil |
| flagged | passes with `isOver`, frame order |
| lines | overlay lines (contract C3) |

## FrameBudgetMeter (state)

`flags: UInt16` (13 bits). `evaluate(report, deadline) -> verdict`; `reset()`.
Transitions per pass: unavailable → clear; samples < minimum → unchanged; p95 > threshold → set;
p95 < clear → clear; otherwise unchanged.

## DiagnosticsSnapshot.FrameTimings.Budget (export, optional)

`framesPerSecond`, `deadlineMs`, `thresholdShare`, `clearShare`, `thresholdMs`, `cpuEstimateMs?`,
`gpuEstimateMs?`, `flaggedPasses: [String]` (pass labels, ≤ 13). Absent key = unavailable.
