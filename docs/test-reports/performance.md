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

## Plan Phase B exit (task T063)

| Adapter | Allocations (0) | Locks (0) | Capture + pipeline CPU, 30 min (< 15% of one core) | Pass? |
|---------|-----------------|-----------|----------------------------------------------------|-------|

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
