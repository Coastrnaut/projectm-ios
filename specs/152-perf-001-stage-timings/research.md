# Research: PERF-001 Per-stage frame timings

## PERF-001-D1: Where the timer lives

- **Decision**: New target `FrameTiming` in the Compositor package, added to the `Compositor` library
  product; Foundation/Dispatch only, with the Metal poller behind `#if canImport(Metal) && !COMPOSITOR_NO_METAL`.
- **Rationale**: The compositor's GPU integration test, ANGLERendering (already depends on the product)
  and the app all import it without new package edges; the package already runs on Linux in CI.
- **Alternatives**: Diagnostics (would make Compositor and ANGLERendering depend on Diagnostics);
  Rendering (UIKit, not Linux-tested); a new package (more CI wiring for ~300 lines).

## PERF-001-D2: CPU clock

- **Decision**: An injected `() -> UInt64` nanosecond clock; the app uses `DispatchTime.now().uptimeNanoseconds`
  (monotonic, available on Linux). End before begin (a backwards clock) rejects the sample.
- **Alternatives**: `ContinuousClock` (Duration arithmetic, heavier); `CACurrentMediaTime` (QuartzCore only).

## PERF-001-D3: GPU time

- **Decision**: Only the whole frame's GPU time, from the frame's command buffer (`gpuEndTime - gpuStartTime`),
  read by polling `status == .completed` on later frames (a 4-slot ring of pending buffers). Per-stage GPU
  values are unavailable in the app; the timer API still accepts them for a stage that owns a command buffer.
  projectM on ANGLE: unavailable. A start time ≤ 0, an end before start, or a non-finite value is rejected
  (the simulator may report zeros).
- **Rationale**: Each visual encodes a frame into one command buffer; splitting it (extra command buffers or
  counter sample buffers) changes the frame path and is PERF-002's concern. `addCompletedHandler` would
  allocate a closure per frame and run on a Metal thread (needing a lock or atomics); polling needs neither.
- **Alternatives**: `MTLCounterSampleBuffer` stage boundaries (not on every GPU family, more setup);
  completion handlers (allocation, cross-thread).

## PERF-001-D4: Stage split inside the compositor

- **Decision**: `Compositor.stageClock: (() -> UInt64)?` (nil by default) and
  `lastOutputPassStartNanoseconds`, stamped once per frame where the FX-019 flash guard begins (the start
  of the output pass). The host times `composite(into:)` as a whole and splits it at that mark:
  composite = mark − start, output = end − mark.
- **Rationale**: One nil check per frame when off; no Compositor dependency on FrameTiming; minimal edit
  in a file other agents also edit.

## PERF-001-D5: Window and statistics

- **Decision**: 120 frames; median (mean of the two middle values for even n) and nearest-rank p95. Report
  sorting happens at report time (once a second from the overlay), never on the frame path.

## PERF-001-D6: No allocation, no lock

- **Decision**: All storage is preallocated `[Double]`/`[UInt64]`/`[UInt16]` arrays owned by a final class
  and mutated in place; `begin`/`end`/`endFrame` never append. The timer is used on the main thread only
  (all frame loops run there). Verified by an allocation-free design review and a bench test of the cost.

## PERF-001-D7: Signposts

- **Decision**: No per-stage `os_signpost` in this row.
- **Rationale**: The overlay is the user-facing view; Instruments' Metal System Trace already shows GPU
  work; a signpost per stage per frame adds cost while the overlay is on. PERF-002 can add them.

## PERF-001-D8: Diagnostics export

- **Decision**: Optional top-level `frameTimings` in `DiagnosticsSnapshot` (schema version stays 2: the
  field is optional and additive, older exports remain valid; `check_capturelab_export.py` unaffected).
  Unavailable values are absent keys. The visualizer app has no diagnostics export screen; its device
  runs write the section through `AutomationRunner` mode `perf001`. CaptureLab leaves it nil.

## PERF-001-D9: Overhead

- **Decision**: Off = one optional check per frame (the hosts load `stageTimer` once). On = measured by
  `FrameStageTimerTests.testBenchCostPerFrame` on the host (reported, not asserted) and on D1 by the
  automation mode (`{device}`).

## Measurements (filled in at implementation)

- Host bench: see tasks.md PERF-001-T05.
