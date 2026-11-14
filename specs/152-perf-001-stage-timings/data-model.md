# Data Model: PERF-001 Per-stage frame timings

## FrameStage (enum, `FrameTiming`)

| Case | Label | Conditional | Meaning |
|---|---|---|---|
| audio | `audio` | no | Frame-thread audio intake (analysis read, smoothing, modulation, or projectM PCM feed) |
| render | `render` | no | Drawing the visual (projectM engine, native generator and glow) |
| composite | `composite` | no | Compositor layer stack |
| output | `output` | no | Final screen pass (flash guard, grade, output; projectM's flash-limiter pass) |
| encode | `encode` | yes | REC-003 recording copy; reported only when measured in the window |
| present | `present` | no | Present + commit, or `eglSwapBuffers` |

Frame order = declaration order. Pipelines: projectM `[audio, render, output, present]`; native
`[audio, render, encode, present]`; compositor `[audio, composite, output, encode, present]`.

## StageStatistic (enum)

- `unavailable`
- `measured(samples: Int, medianMs: Double, p95Ms: Double)` — finite, ≥ 0.

## StageSummary

`stage: FrameStage`, `label: String`, `cpu: StageStatistic`, `gpu: StageStatistic`.

## FrameStageReport

- `frames: Int` — frames in the window (≤ capacity).
- `stages: [StageSummary]` — the pipeline's stages in frame order; conditional stages only when measured.
- `frameGPU: StageStatistic` — whole frame's GPU time.
- `rejectedSamples: Int` — samples rejected since the window started.
- `lines: [String]` — overlay text (see contract).

## FrameStageTimer (final class, single-thread)

- `capacity` (default 120), `clock: () -> UInt64` (ns).
- `pipeline: [FrameStage]` — set by `configure(pipeline:)`, which clears the window.
- Ring: `cpu`/`gpu` values `[Double]` (capacity × 6, seconds), per-frame masks `[UInt16]`
  (bits 0-5 CPU, bits 8-13 GPU), `frameGPU` ring `[Double]` with its own count/index.
- Current frame: `starts [UInt64]` (6), `currentCPU/currentGPU [Double]` (6), `currentMask`, `inFrame`.

Rules: `begin(stage)` stamps; `end(stage)` records `now − start` if begun this frame and `now ≥ start`,
else rejects (counted) when the clock went backwards; `record(stage, cpuSeconds:)`,
`record(stage, gpuSeconds:)` and `recordFrameGPU(seconds:)` reject NaN, ±∞ and negatives;
`endFrame()` commits the frame's mask and values into the ring (overwriting the oldest) — a frame with
an empty mask is not committed; `reset()` clears.

## DiagnosticsSnapshot.FrameTimings (Codable, `Diagnostics`)

```json
"frameTimings": {
  "windowFrames": 120,
  "rejectedSamples": 0,
  "frameGPUMedianMs": 4.1, "frameGPUP95Ms": 5.0,
  "stages": [ { "name": "audio", "samples": 120, "cpuMedianMs": 0.05, "cpuP95Ms": 0.09 } ]
}
```

`name` ∈ the six labels; GPU and CPU keys absent when unavailable; at most 6 stages.
