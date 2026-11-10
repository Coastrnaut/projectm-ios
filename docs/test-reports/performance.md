# Performance Report

All values must come from physical devices listed in [devices.md](devices.md). Status: **no
measurements yet.**

## Phase A real-time check (Constitution VII; task T050)

> T050 is not required (owner ruling 2026-11-09, ADR-0001 ruling 18). Constitution VII still
> applies; the audio callbacks are allocation-free by design and covered by unit tests, but no device
> allocation trace was recorded.

| Adapter | Device | Run length | Heap allocations on audio thread (0) | Lock acquisitions (0) | Pass? |
|---------|--------|------------|--------------------------------------|-----------------------|-------|
| System/App Capture | | 60 s | | | |
| Microphone | | 60 s | | | |
| In-App Playback | | 60 s | | | |

## Plan Phase B latency signposts (task T062)

The analyzer reports the three R-06 stages to `PipelineSignposts` (Diagnostics/Logging.swift), in
the Points of Interest track of subsystem `org.projectmios`:

| Stage (budget) | Signpost | Kind |
|----------------|----------|------|
| Ring + conversion (≤ 20 ms) | `Ring + conversion` | interval around each work-queue drain that has audio |
| Capture delivery (≤ 30 ms) | `Capture delivery` | point, max ms since the last report (≤ 4/s), from the buffer's capture timestamp (CMSampleBuffer PTS, or the AVAudioTime host time of a tap) to its arrival in PCMSink |
| Normalized residency (≤ 50 ms) | `Normalized residency` | point, ms of audio waiting when the renderer last read the normalized ring |

Delivery and residency can only be measured after the fact, so they are points carrying the
measured value (private, per R-13), not intervals.

**Simulator trace, 2026-11-09 (project Mac; not evidence, see Constitution V):** `xctrace record
--template Logging` on the iOS 27.2 simulator while the CaptureLab UI tests ran In-App Playback:
79 `Ring + conversion` intervals (median 0.03 ms, max 0.30 ms) and 31 `Capture delivery` points
(about 85 ms; the mixer tap's timestamp marks when the 1,024-frame buffer was rendered, so this may
include tap buffering). No `Normalized residency` points: nothing reads the normalized ring until
the Phase C renderer exists. T062 stays open until a trace shows all three stages; the Capture
delivery figures need a device trace before anyone draws a conclusion from them.

**Owner rulings 2026-11-09:** T062 is closed on these two stages; points carrying the measured
ms are accepted for delivery and residency; the residency trace is T114 in Phase C.

## Plan Phase B exit (task T063)

Run 2026-11-09 on D1 (iPhone 15, `iPhone15,4`, iOS 27.0.1), CaptureLab build 2, Debug
configuration, commit `20c79ca`, Xcode 27.2 (27B52). **Owner ruling 2026-11-09: the CPU run is
3 minutes instead of 30.**

| Adapter | Allocations in the callback (0) | Lock waits in the callback (0) | CPU, 3 min (< 15% of one core) | Pass? |
|---------|---------------------------------|--------------------------------|--------------------------------|-------|
| System/App Capture (Spotify) | 0 in 61 s | 0 syscalls in 61 s | 7.36% mean, 8.09% p95, 8.37% max | Yes |
| Microphone | 0 in 61 s | 0 syscalls in 61 s | not measured (ruling: one CPU run) | Yes |
| In-App Playback | 0 in 61 s (after the two fixes below) | 0 syscalls in 61 s | not measured (ruling: one CPU run) | Yes |

**Method.** `xctrace record --template Allocations --instrument "System Call Trace"` launched
CaptureLab on D1; the tester started each source by hand. The window is 61 s, from 1 s before the
first `Ring + conversion` signpost (so the first callbacks count). An allocation or syscall counts
as "in the callback" when its call stack passes through `PCMSink.write`,
`SampleBufferAudioWriter.write`, the SCStreamOutput `didOutputSampleBuffer` handler, or a tap closure
of `AVMicrophoneBackend`/`AVInAppPlaybackBackend`. Stacks were symbolicated: each trace shows the
start-up allocations and syscalls of these types, so a callback allocation would have been seen
(the first In-App Playback run did see them). The CPU run used the Activity Monitor template plus
Points of Interest: cumulative CPU time of the whole CaptureLab process (UI included, so an upper
bound for capture + pipeline) over 3 minutes from the first signpost; audio flowed throughout
(longest gap between drains 0.03 s). The trace's threads match System/App Capture (CoreMedia
queue, no AURemoteIO thread).

**Limit of the lock check.** A blocking or contended lock shows up as a syscall
(`psynch_mutexwait`, `ulock_wait`, ...); none occurred inside a callback. An uncontended
`os_unfair_lock` taken by system code makes no syscall, so no trace can show it. Our callback code
takes no locks (atomics only, by design and review).
Owner ruling 2026-11-09: this limit is accepted; zero lock-wait syscalls meets T063's
"zero lock acquisitions".

**Fixes made during T063** (commit `20c79ca`):
1. The first In-App Playback run found 22 allocations on the first callback:
   `MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)` in `PCMSink.write(_:format:frameCount:)`
   (and in `SampleBufferAudio.buffersHold`) builds a KeyPath object at run time in Debug. Replaced
   by a layout constant, `PCMSink.audioBuffersOffset`, tested against the key-path value.
2. The next run found 1 allocation: the Objective-C method cache filled by the tap closure's first
   message sends. `AVAudioTapWarmUp` now sends those messages before installing the tap and again
   after engine start (a warm-up only before the tap still left it, since engine start can reset
   the caches). The following run had none.

Traces stay on the project Mac (several hundred MB each); the analysis scripts are not committed.

## ADR-0003 renderer measurements (Gate 3)

| Option | Device | Test presets OK | Starter presets OK (≥ 95%) | fps ≥ 55 for 95% (ref) / ≥ 30 (oldest) | App size Δ (≤ 30 MB) | Flash limiter cost (< 2 ms) | Pass? |
|--------|--------|-----------------|----------------------------|-----------------------------------------|----------------------|-----------------------------|-------|

## Stage 2 success criteria (Gate 4)

| Criterion | Target | D1 iPhone 15 (reference) | D2 iPad Pro M5 | D3 iPad A16 | Pass? |
|-----------|--------|------------------|---------------|-------------|-------|
| SC-005 frame rate | ≥ 55 fps for 95% of 10 min (60 fps cap on 120 Hz) | | | | |
| SC-006 audio→visual delay | median < 150 ms (20 clicks) | | n/a | n/a | |
| SC-007 preset switch | 95% first frame < 1 s; blend ≤ 2 s | | | | |
| SC-008 memory | drift ≤ 10% (min 5→30); peak < 300 MB | | | | |
| SC-009 cycles + lifecycle | 0 crashes | | | | |
| SC-013 thermal | never critical; ≥ 30 fps; no termination | | | | |
| SC-014 battery | ≤ 20% per 60 min | | | | |
| SC-015 cold launch | < 2 s D1 / < 4 s D3 | | | | |

## Stage 2 thresholds (finalized at Gate 4)

| Threshold | Initial | Final | Evidence |
|-----------|---------|-------|----------|
