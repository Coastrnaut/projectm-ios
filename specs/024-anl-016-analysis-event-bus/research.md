# Research: ANL-016 Analysis Event Bus

Decisions are numbered `ANL-016-D1…`. Each lists the decision, rationale and alternatives.

## ANL-016-D1 Restart signal from the analysis tap

- **Decision**: `NormalizedPCMRing.reset()` (called by `AudioAnalyzer.resetSession` at every new
  capture attempt: start, restart, switch) drains the tap, then increments an `Atomic<UInt64>`
  session generation (release). The tap reader exposes it through a new public protocol
  `AnalysisSessionReporting`. The worker loads it (acquire) before and after each chunk read:
  - before ≠ after: the chunk may straddle the reset → discard it, begin a new session;
  - before = after ≠ last seen: the reset happened between reads → begin a new session, keep the chunk.
- **Why it is safe**: drain happens before the increment, and new-session writes start only after
  `reset()` returns. If a read saw new-session audio, the increment is visible to the later load
  (the ring's indices publish with release/acquire), so the chunk is discarded. If both loads see
  the new generation, the drain has finished, so no old audio remains to be read.
- **Alternatives**: a CaptureKit callback (CaptureKit is another agent's package and the app's
  lifecycle code would need wiring); comparing dropped counters (ambiguous); timestamps on PCM
  (a larger AudioCore change).

## ANL-016-D2 One clock: session sample position, timeline, host mapping

- **Decision**: the primary clock is the sample count. Session position of an item = input samples
  consumed in the session up to the end of its window (`frame.index + size` with the `.silence`
  lead-in, ≥ hop). Timeline = session base + session position; each new base = previous base +
  samples consumed in the previous session, so the timeline never decreases (new items are ≥ base
  + hop > any previous item). Host time = anchor + position × 10⁹ / rate (integer math), the
  anchor set at the session's first chunk to `clock() − chunkDuration`, clamped to the last
  published host time.
- **Rationale**: sample counts are exact and deterministic; host time from a mapping (not a
  reading per frame) is deterministic under an injected clock and monotonic by construction.
  PERF-013 may later re-anchor for drift.
- **Alternatives**: the stream's per-frame clock reading (scheduling dependent); host time only
  (not exact, not deterministic).

## ANL-016-D3 Delivery: polling, per-subscriber slots

- **Decision**: per subscription one `Mutex` guarding a latest-frame slot (128 floats + metadata,
  fresh flag, overwritten counter) and an event ring (capacity 1…1,024, default 64, drop-oldest,
  dropped counter). The pipeline's subscriber list is a fixed-capacity array (16) under its own
  `Mutex`; publishing iterates it under that lock and takes each subscription's lock in turn (lock
  order list → subscription; readers take only the subscription lock, so no cycle).
- **Rationale**: bounded constant work per item, no allocation (fixed storage, value structs with
  no references), the worker never runs subscriber code, cancel is synchronous.
- **Alternatives**: `AsyncStream` (allocates per element, unbounded by default, actor hops);
  callbacks on the worker (a slow subscriber stalls analysis); lock-free triple buffers per
  subscriber (single-reader only, cannot be cleared at a restart from the writer side without
  more protocol).

## ANL-016-D4 IDs

- **Decision**: one `UInt64` counter per pipeline, confined to the worker, starting at 1, shared by
  frames and events; never reset. Detector and tracker sequence numbers stay internal.
- **Alternatives**: a process-global atomic (breaks run-to-run equality in tests); per-kind
  counters (no total order).

## ANL-016-D5 Worker

- **Decision**: a serial `DispatchQueue` (`org.projectmios.analysis-pipeline`, user-interactive)
  confines all analysis state; public calls use `queue.sync` (never from the queue itself:
  subscriber code never runs there). A `DispatchSourceTimer` (10 ms, 2 ms leeway) runs steps only
  between `startWorker()` and `stopWorker()`; tests call `step()` synchronously instead.
- **Alternatives**: a Swift actor (async hops, harder to drive synchronously in tests; allocation
  of tasks); a thread with a semaphore (more code, no benefit).

## ANL-016-D6 Circular spectrum on the bus

- **Decision**: `LiveBandAnalyzer` keeps its API but owns `AnalysisPipeline` (bands = bar count,
  floor −80 dB, 2,048/512 mid) and one subscription; `output` is a `LiveBandOutput` reading the
  subscription. The app's host code is unchanged. The bus's `.silence` lead-in shifts only the
  first window after a start (zeros before the first sample), which the VIS-001 tests tolerate.
- **Alternatives**: leave it on its own timer (two analysis paths in production); change the app's
  host to poll the bus directly (touches app code for no gain).
