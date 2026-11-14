# Contract: Frame stage timer (PERF-001)

## C1 Timer API (`import FrameTiming`)

```swift
public enum FrameStage: Int, CaseIterable, Sendable { case audio, render, composite, output, encode, present
    public var label: String; public var isConditional: Bool }
public final class FrameStageTimer {
    public static let defaultCapacity = 120
    public init(capacity: Int = defaultCapacity, clock: @escaping () -> UInt64)
    public static func systemClock() -> UInt64          // DispatchTime uptime ns
    public func configure(pipeline: [FrameStage])         // clears the window
    public func reset()
    public func beginFrame()
    public func begin(_ stage: FrameStage)
    public func end(_ stage: FrameStage)
    @discardableResult public func record(_ stage: FrameStage, cpuSeconds: Double) -> Bool
    @discardableResult public func record(_ stage: FrameStage, gpuSeconds: Double) -> Bool
    @discardableResult public func recordFrameGPU(seconds: Double) -> Bool
    public func endFrame()
    public func now() -> UInt64
    public func report() -> FrameStageReport              // allocates; call off the frame path
}
```

- C1.1 `begin`/`end`/`record`/`endFrame` never allocate and never lock. Single thread (the frame thread).
- C1.2 Rejected: NaN, ±∞, negative, end before begin. Counted in `rejectedSamples`; never stored.
- C1.3 `end` without `begin` in this frame does nothing.
- C1.4 A stage not in the pipeline is ignored.

## C2 Report

- C2.1 `stages` lists the pipeline's stages in frame order; `encode` (conditional) only when at least one
  frame in the window measured it.
- C2.2 A stage with no CPU samples has `cpu == .unavailable`; no GPU samples → `gpu == .unavailable`.
- C2.3 Median: middle (mean of two middles for even n); p95: nearest rank, sorted index ⌈0.95·n⌉ − 1.
- C2.4 Values are milliseconds, finite, ≥ 0.

## C3 Overlay lines (`FrameStageReport.lines`)

```
stages ms (median/p95)
audio 0.05/0.09
render 2.10/3.40 gpu 1.00/1.20     # " gpu …" only when the stage's GPU is measured
composite –                        # "–" when CPU unavailable
gpu 4.10/5.00                      # or "gpu unavailable"
rejected 3                         # only when > 0
```

Two decimals, `%.2f`.

## C4 Compositor split

`Compositor.stageClock: (() -> UInt64)?` (default nil); when set, `lastOutputPassStartNanoseconds` is
stamped once per `composite(into:)` frame immediately before the flash guard (start of the output pass);
0 when the frame failed before it.

## C5 Metal GPU poller (`MetalGPUFrameTimes`, Apple only)

`track(_ commandBuffer:)` after commit (4 slots, the oldest is dropped when full);
`drain(into timer:)` at the start of a frame records each `.completed` buffer's
`gpuEndTime − gpuStartTime` with `recordFrameGPU` (rejecting start ≤ 0), drops `.error` buffers.
`reset()` forgets pending buffers.

## C6 Export

`DiagnosticsSnapshot.frameTimings: FrameTimings?` per data-model.md; absent key when nil;
schema property `frameTimings` (optional, `additionalProperties: false`).
