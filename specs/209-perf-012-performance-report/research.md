# Research: PERF-012 Diagnostic performance report

## PERF-012-D1 Where frame intervals come from
- **Decision**: `FrameDropCounter.submit` records `timestamp − previous timestamp` into a shared
  `FrameIntervalRecorder` when one was given at init.
- **Rationale**: every visual path (projectM via ANGLE, native, camera, photo, video, text) already calls `submit`
  with display-link timestamps while the overlay is shown; the duplicate-timestamp rule already filters repeats.
- **Alternatives**: a new hook in each visual (six edits in files other agents touch); PERF-001's window p95
  (only the last window, no p99/max).

## PERF-012-D2 Histogram, not a sample buffer
- **Decision**: 2,500 fixed 0.1 ms buckets (0–250 ms; the last also takes longer ones), exact max, sum, count and
  exact counts at ≥ 25, 50 and 100 ms. A percentile is the upper edge of the nearest-rank bucket, capped by the max.
- **Rationale**: constant memory (10 KB), no allocation per frame, error ≤ 0.1 ms, never optimistic.
- **Alternatives**: keep every interval (unbounded); P² estimators (approximate, untestable bounds).

## PERF-012-D3 Locking
- **Decision**: `Mutex<FrameIntervalHistogram>` (Synchronization), mutated in place.
- **Rationale**: one writer (the shown visual's frame thread) and a rare reader (export): uncontended. The buckets
  live in one array mutated in place under the lock, so no copy and no allocation per frame.
- **Alternatives**: 2,500 atomics (Swift has no array of `Atomic`), lock-free double buffer (complex).

## PERF-012-D4 Privacy by construction
- **Decision**: the report type has no free-text field. Fixed-set strings (`visual`, `thermal`, `profile`, output and
  stage names) map unknown values to `unknown` (or drop the entry); system strings (model, OS version and build, app
  version and build) keep only `[A-Za-z0-9 .,_()-]`, at most 40 characters. The builder's inputs carry no media,
  names, paths, text or addresses at all.
- **Rationale**: the acceptance test can then assert, for every string in the file, that it is in an allowed set or
  equals a system metadata value — a structural proof stronger than searching for the seeded strings alone.

## PERF-012-D5 Memory and pool counters
- **Decision**: `phys_footprint` from `task_info(TASK_VM_INFO)` (the figure Xcode and jetsam use), its peak as sampled
  at each overlay refresh and at export, and `os_proc_available_memory()`; pool counters summed over
  `SharedTexturePool`'s pools.
- **Rationale**: public APIs, not on the required-reason list; already used by the RenderGoldens soak driver.

## PERF-012-D6 Sharing
- **Decision**: reuse REC-012 (`ShareFileStore` copy in `<tmp>/Sharing/<UUID>/`, `ActivitySharePresenter`, copy
  deleted on every outcome, Save to Photos and Assign to Contact excluded), with a new share kind.
- **Rationale**: one sharing code path; launch cleanup already covers the folder.

## PERF-012-D7 MetricKit
- **Decision**: not used (Clarifications): daily aggregates, not this session.

## PERF-012-D8 Session duration and the required-reason API
- **Decision**: the session duration and timeline times come from `ProcessInfo.systemUptime` differences, under the
  app's existing SystemBootTime reason 35F9.1: only the time elapsed between events inside the app leaves the device
  (in the user-shared file), which that reason allows. No new privacy manifest entry
  (`check_privacy_manifest.py` OK on the Debug build).
