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

### All three stages with the visualizer (task T114)

2026-11-09, iOS 27.2 simulator (not device evidence): ProjectMiOS (Debug, `-autostart inAppPlayback`)
with `CaptureManager` passing `DiagnosticsLog.pipeline`, recorded with `xctrace record --template
Logging` for 25 s while the ANGLE renderer drained `normalizedOutput`:

| Stage | Signpost | Count | Value |
|-------|----------|-------|-------|
| Ring + conversion | interval | 226 | — |
| Capture delivery | point | 88 | median 85.8 ms, max 87.3 ms (simulator In-App Playback tap; see T062 note) |
| Normalized residency | point | 61 | median 36.9 ms, **max 50.0 ms** (freshness rule cap) |

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

Measured 2026-11-09 with RendererLab (Release build; `RendererLab.yml`, `Apps/RendererLab`), driven
by `devicectl`. Reports: `docs/test-reports/exports/rendererlab/D1|D2|D3/*.json`. Each sweep loads
every upstream test preset (37) and every starter preset (28), renders each for 2.2 s with the
reference track as audio, and records the load result, load time and the frame rate of the last
complete 1-second window. Full display resolution (D1 1179 × 2556, D2 2064 × 2752, D3 at its
native scale); default engine mesh size; no quality tier applied yet.

**Owner ruling 2026-11-09: the 10-minute sessions are not required.** The frame-rate column
therefore uses the sweeps' per-preset frame rates (starter presets at or above the threshold), not
a sustained session. Thermal state stayed "nominal" in every run.

| Option | Device | Test presets OK | Starter presets OK (≥ 95%) | Starter presets ≥ 55 fps (D1) / ≥ 30 fps (D2, D3) | Slowest preset | App size Δ (≤ 30 MB) | Flash limiter cost (< 2 ms) | Pass? |
|--------|--------|-----------------|----------------------------|----------------------------------------------------|----------------|----------------------|-----------------------------|-------|
| A (OpenGL ES) | D1 iPhone 15, iOS 27.0.1 | 37/37 | 28/28 | 15/28 ≥ 55 | 13.9 fps | +1.4 MB (0.45 MB zipped) | not measured | No (frame rate) |
| A (OpenGL ES) | D2 iPad Pro M5, iPadOS 27.2 | 37/37 | 28/28 | 25/28 ≥ 30 | 13.8 fps | same | not measured | No (frame rate) |
| A (OpenGL ES) | D3 iPad A16, iPadOS 26.5 | 37/37 | 28/28 | 15/28 ≥ 30 | 13.0 fps | same | not measured | No (frame rate) |
| B (ANGLE/Metal) | D1 iPhone 15, iOS 27.0.1 | 37/37 | 28/28 | 22/28 ≥ 55 | 26.0 fps | +7.3 MB (2.3 MB zipped) | not measured | No (frame rate) |
| B (ANGLE/Metal) | D2 iPad Pro M5, iPadOS 27.2 | 37/37 | 28/28 | 28/28 ≥ 30 (all at 60 fps) | 60.0 fps | same | not measured | Yes, except the limiter row |
| B (ANGLE/Metal) | D3 iPad A16, iPadOS 26.5 | 37/37 | 28/28 | 26/28 ≥ 30 | 15.9 fps | same | not measured | No (frame rate) |

App size: the frameworks each option adds to a Release app (`projectM-4.framework`, plus
`libEGL.framework` and `libGLESv2.framework` for B), uncompressed and as a zip, standing in for
the download size. Load times: slowest 39 ms (A) and 385 ms (B, Metal shader compilation on D3),
all under SC-007's 1 s. No engine errors in any run.

Findings:
- Option B is faster than Option A on every device at the same resolution: on D2 it holds 60 fps on
  every preset, where A drops to 14 fps on the three heaviest starter presets.
- Neither option meets the frame-rate threshold on D1 or D3 at full resolution with the default
  mesh. The quality tiers (render scale, mesh size; research R-08) are the lever the ADR provides;
  they are not measured yet.
- The heaviest presets are the same on every device ("Reaction Diffusion 3 (Overload Mix 2)",
  "Star to Another World", "The Beast Mandala Chaser").

**Owner ruling 2026-11-09: the Reduce-flashing cost and the quality tiers are not required for Gate 3, and the owner accepts the rendering as measured ("everything rendered fine and looks ready").** The frame-rate shortfall on D1 and D3 and the unmeasured limiter column are accepted as they stand.

RI-009 on devices: with an unpatched engine, the GL resolver tried to `dlopen` eleven EGL/GLES
names on D1, D2 and D3 (none opened); with fork patch 3 (`ca1fc0d`), D3 (A) and D2 (B) logged no
attempt at all (see ADR-0003).

## Reduce-flashing post-pass cost (task T104; FR-072)

RendererLab `RL_BACKEND=angle RL_MODE=flashcost` on D1 (iPhone 15, iOS 27.0.1, 1179 x 2556 surface,
thermal nominal, Low Power Mode off), 2026-11-10. Per starter preset (28): 30 warm-up frames,
then 5 rounds of 40 frames with Reduce flashing off and 40 on, each frame rendered without
presenting and followed by `glFinish`, so the time includes the GPU work. Cost = median frame time
on minus off. Target: at most 2 ms per frame.

| Version | Mean source | Median cost | Max cost | Presets over 2 ms | Report |
|---------|-------------|-------------|----------|-------------------|--------|
| First | full-resolution mip chain | 1.75 ms | 2.55 ms | 5 of 28 | `exports/rendererlab/D1/RendererLab-angle-flashcost-2026-11-10T141917Z.json` |
| **Final** | linear blit to 64 x 64, then its mip chain | **1.21 ms** | **1.55 ms** | **0 of 28** | `exports/rendererlab/D1/RendererLab-angle-flashcost-2026-11-10T142354Z.json` |

The heaviest preset (`Martin - The Beast Mandala Chaser FX H`, 24 ms per frame without the pass)
costs 1.55 ms more with it. The limit: mean luminance changes at most 0.3 per second
(`ANGLERenderer.flashLimitPerSecond`). The GLES fallback renderer has no post-pass.

## Stage 2 success criteria (Gate 4)

**Gate 4 waived by the owner on 2026-11-10 (T102 not required).** SC-005, SC-008, SC-013 and
SC-014 were not run; the cells below hold only what was measured. The Stage 2 thresholds keep
their initial values and are not finalized.

| Criterion | Target | D1 iPhone 15 (reference) | D2 iPad Pro M5 | D3 iPad A16 | Pass? |
|-----------|--------|------------------|---------------|-------------|-------|
| SC-005 frame rate | ≥ 55 fps for 95% of 10 min (60 fps cap on 120 Hz) | | | | |
| SC-006 audio→visual delay | median < 150 ms (20 clicks) | | n/a | n/a | |
| SC-007 preset switch | 95% first frame < 1 s; blend ≤ 2 s | 50/50 < 1 s; median 32 ms, p95 223 ms; blend 2 s | | | |
| SC-008 memory | drift ≤ 10% (min 5→30); peak < 300 MB | | | | |
| SC-009 cycles + lifecycle | 0 crashes | 0 crashes; final states correct (In-App, Microphone) | | 0 crashes; final states correct (In-App, Microphone) | |
| SC-013 thermal | never critical; ≥ 30 fps; no termination | | | | |
| SC-014 battery | ≤ 20% per 60 min | | | | |
| SC-015 cold launch | < 2 s D1 / < 4 s D3 | 10/10 < 2 s; median 80 ms, max 83 ms | | 10/10 < 4 s; median 111 ms, max 113 ms | |

### Gate 4 automated runs (tasks T092, T101, T102; 2026-11-10)

Measurement build: Release with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=PROJECTM_AUTOMATION`
(`Apps/ProjectMiOS/Automation/AutomationRunner.swift`), started by devicectl with
`PROJECTM_AUTORUN`. Reports: `docs/test-reports/exports/gate4/`.

**D1 iPhone 15, iOS 27.0.1**
- SC-015: 11 launches in a row, each a new process (the notice was already acknowledged, so all 11
  were recorded; the table uses the last 10). Process start (kernel start time) to the source
  chooser's `onAppear`: 77-83 ms. Limits: the launches were back to back, so the file cache was
  warm; `onAppear` comes just before the chooser's first frame. Both limits are far inside the 2 s
  target.
- SC-007: In-App Playback, 50 × Next, request to the first frame presented after the load: 50/50
  under 1 s, median 32 ms, p95 223 ms, max 245 ms, 0 load failures. Blend duration is 2 s by
  setting.
- SC-009: 50 cycles of In-App Playback → Microphone → stop at 200 ms, then per mode the scripted
  background, foreground, lock, unlock, interruption began, interruption ended (resume) and route
  change (old device unavailable), posting the notifications iOS posts. The run finished and wrote
  its report (no crash). After the cycles: chooser, stopped. In-App Playback: paused on
  background and lock, active on return, interrupted then active, paused (audioRouteChanged) on
  the route change, stopped. Microphone: the same, except the route change leaves it active: the
  built-in microphone is still available, so the backend continues on it (lifecycle matrix;
  `microphoneUnavailable` applies only when no input remains). System/App Capture is not
  automated: every start shows the system picker.

**D3 iPad A16, iPadOS 26.5**
- SC-015: 11 launches in a row, all recorded; the table uses the last 10. Process start to the
  chooser's `onAppear`: 104-113 ms (same limits as D1: warm file cache, `onAppear`).
- SC-009: same sequence as D1; the run finished and wrote its report (no crash). After the cycles:
  chooser, stopped. In-App Playback: identical to D1. Microphone: the room was quiet, so the
  receiving state reads "silent" (audio received) instead of "active"; otherwise the same as D1
  (paused on background and lock, back on return, interrupted then resumed, continues after the
  route change, stopped).

T101 accepted by the owner on 2026-11-10 with System/App Capture not run (it needs a person at the
system picker for every start).

## Stage 2 thresholds (finalized at Gate 4)

| Threshold | Initial | Final | Evidence |
|-----------|---------|-------|----------|
