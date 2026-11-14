# Contract: Render soak (QA-006)

## S1 — Frame loop

For frame n in 0..<frames: if n is a multiple of `dwellFrames` and n > 0, the dwell of the current
scene ends (S3), then the next scene in order is built and shown: `transition(to:spec:reduceMotion:
false)` with a crossfade of `transitionSeconds`, or `show(_:)` (a cut) when the switch index is a
multiple of `cutEvery`. Frame 0 shows scene 0 with a cut. The frame's presentation time is `start +
n × interval`; the audio context gets `GoldenAudio.seededBands(count: 32)` for frame n and the soak
seed. Each frame is encoded with `encodeFrame` into a 128 × 96 `rgba16Float` target, committed and
awaited. A cycle ends after every scene was shown once (`dwellFrames × scenes` frames).

## S2 — Release

After each frame the driver drops every scene holder whose compositor is neither the bus's live nor
outgoing scene, adding its `health.faultCount` to the errors and removing its temporary files.

## S3 — Dwell end

Before each switch and after the last frame: record `RenderSoakDwellSample` (pool checked-out
textures and bytes, live scene compositors counted through weak references).

## S4 — Cycle end

At each cycle end record `RenderSoakCycleSample` (memory high-water of the cycle's frames, memory now,
pool live bytes, pool misses). Leak injection happens at the start of every cycle.

## S5 — Errors

A scene build error, an `encodeFrame` false, a command buffer `error`, and every PERF-014 fault are
recorded with frame and scene; the soak continues.

## S6 — End

After the last frame: the bus and every scene are dropped, then the release record is taken
(checked-out textures, live scene objects). The verdict follows `data-model.md`. The report is
written as `<name>.json` to `QA006_REPORT_DIR`, else the temporary folder, and its path returned.

## S7 — Verdict rules (`RenderSoakRecorder.verdict()`)

| Rule | Fails when |
|---|---|
| `renderErrors` | errorCount > 0 |
| `memorySlope` | slope of measured high-water marks > ε |
| `memoryBound` | a measured high-water > bound |
| `poolBaseline` | a dwell's checked-out textures or bytes differ from that scene's post-warm-up baseline |
| `liveObjects` | a dwell has live scenes > `maxLiveScenesAtDwellEnd` |
| `releaseNotEmpty` | after release, checked-out textures > 0 or live objects > 0 |
| `tooFewCycles` | measured cycles < minimum (outcome inconclusive unless another rule failed) |
