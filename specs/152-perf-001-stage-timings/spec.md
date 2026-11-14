# Feature Specification: PERF-001 Per-stage frame timings

**Feature Branch**: `feature/perf-001` (spec directory `152-perf-001-stage-timings`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PERF-001 (Per-stage frame timings) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Measure audio, render, composite and encode costs separately." Acceptance,
verbatim: "Synthetic frame reports finite timings with correct stage labels." P1, size M, no dependencies.
Verification: performance unit, simulator, physical device last."

Identifiers carry the roadmap ID: requirements `PERF-001-R1…`, success criteria `PERF-001-S1…`, tasks
`PERF-001-T01…`. Other features are cited by their own IDs: FR-048 (performance overlay), T062/T063 (audio
pipeline signposts, no allocation or lock in audio callbacks), PERF-011 (presentation-bound resources),
PERF-014 (render health), CMP-001/CMP-013 (compositor, render cache), FX-009 (trails GPU bench),
FX-019 (flash envelope), REC-003 (video recording), FR-021 (diagnostics export).

## Baseline: what exists today (audit of 2026-11-14, commit `1fe5f95c`)

The audit confirms the gap: nothing measures where a frame's time goes, stage by stage.

| Area | Today |
|---|---|
| Performance overlay (FR-048, T103) | `settings.performanceOverlay`, off by default. Shows fps and mean/max frame time over 1 s windows (`FrameRateMeter`, from presentation timestamps), the audio state, AUD-012's sanitized count and PERF-014's render line. One number for the whole frame. |
| Audio signposts (T062) | `PipelineSignposts`: "Ring + conversion" interval and "Capture delivery"/"Normalized residency" points on the analysis work queue. Nothing on the frame thread. |
| Render health (PERF-014, PERF-011) | Fault counts, back-off and suspension; no timings. |
| Compositor (CMP-001, CMP-013) | `composite(into:)` encodes the layer stack, the FX-019 flash guard and the output pass into the caller's command buffer; CMP-013 counts cache reuse. No stage times. |
| GPU time (FX-009 and other benches) | Package bench tests read `gpuStartTime`/`gpuEndTime` of committed command buffers on the Mac; the app never does. |
| Recording (REC-003) | `MetalFrameRecorder` copies the shown frame into a pixel buffer in the frame's command buffer while a recording runs. Not timed. |
| projectM (ANGLE) | `ANGLERenderer.renderFrame`: PCM feed, engine render into the flash limiter target, limiter post-pass, optional read-back, `eglSwapBuffers`. Not timed. |
| Diagnostics export (FR-021) | CaptureLab's metadata-only JSON (`DiagnosticsSnapshot`, schema version 2, `additionalProperties: false`). No frame data. The visualizer app has no diagnostics export; its device measurements are JSON reports written by `AutomationRunner`. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: Which stages are measured? → A: Six, in frame order, with fixed labels: `audio` (the frame thread's audio intake: reading the analysis output, smoothing and modulation, or feeding projectM its PCM), `render` (drawing the visual: the projectM engine or the native generator, glow included), `composite` (the compositor's layer stack), `output` (the final screen pass: flash guard, grade and output, or projectM's flash-limiter pass), `encode` (copying the frame for a running video recording) and `present` (handing the frame to the display: present and commit, or the swap). A visual reports only the stages its pipeline has.
- Q: How is time measured? → A: CPU time per stage on the frame thread from an injected monotonic clock. GPU time where the platform reports it (Metal command buffers' GPU start and end times), else marked unavailable; never estimated or filled with 0.
- Q: When does measuring run? → A: Only while the performance overlay is shown. Off, the frame path does no timing work at all (one absent-timer check per frame).
- Q: What summary is shown? → A: The median and 95th percentile of each stage over the most recent frames (a fixed window of 120 frames, 2 s at 60 fps), in milliseconds.
- Q: Where can the numbers be taken away? → A: In the diagnostics export format as an optional `frameTimings` section (metadata only), written by the app's automation device run; CaptureLab, which has no frame loop, leaves it out.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How are the median and the 95th percentile computed? → A: Over the stage's samples in the window, sorted: the median is the middle value (the mean of the two middle values for an even count); p95 is the nearest-rank value (index ⌈0.95·n⌉ − 1). Exact and deterministic, so tests can assert equality.
- Q: Does the window restart when the shown visual changes or the overlay is turned off? → A: Yes to both: attaching the timer to another visual clears it, and turning the overlay off detaches it from every visual and drops the window. No new settings key; nothing persists across launches.
- Q: How is the frame's GPU time shown when per-stage GPU time is unavailable? → A: As its own line, `gpu`, after the stage lines (median/p95 of the whole frame's command buffer), or "gpu unavailable" where the platform gives none (projectM on ANGLE, the simulator). Per-stage GPU columns appear only for stages that measured them.
- Q: Can the timing data leave the device? → A: Only by a person's action: the automation run's JSON in the app's Documents, copied off by the Mac script. It is metadata only (labels, counts and milliseconds), never audio or identifiers, and nothing is sent anywhere (FR-068).
- Q: How many rejected samples are tolerated before something is reported? → A: None is hidden: the report carries the count of rejected samples (overlay shows "rejected N" only when N > 0); no threshold or alert, since a rejected sample means a clock fault worth seeing, not a failure.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See where a frame's time goes (Priority: P1)

A performer or tester turns on the performance overlay and sees, next to fps and frame time, one line per
stage of the shown visual with its median and 95th-percentile time, so a slow frame can be traced to audio,
rendering, compositing, the output pass, recording or presentation.

**Why this priority**: The roadmap row; PERF-002 and PERF-007 build on it.

**Independent Test**: A synthetic frame driven through the timer with an injected clock (audio 2 ms, render
3 ms, …) yields a report with exactly the expected labels and exactly those durations; the overlay in the
simulator shows the stage lines.

**Acceptance Scenarios**:

1. **Given** a synthetic frame whose stages take known injected durations, **When** the report is read, **Then** it lists exactly the pipeline's stage labels in frame order, every value is finite, non-negative and equal to the injected duration, and stages with no GPU measurement say "unavailable" (not 0, not NaN).
2. **Given** the overlay is on and a visual is shown, **When** a second passes, **Then** the overlay shows a stages header and one line per measured stage.
3. **Given** a video recording is running, **When** frames are shown, **Then** an `encode` stage appears; **Given** no recording, **Then** no `encode` stage appears.

### User Story 2 - Take the numbers away (Priority: P2)

A tester running an automated device session gets the per-stage summary in a JSON report in the
diagnostics export format, to compare devices.

**Independent Test**: A snapshot with frame timings encodes, validates against the schema, decodes to the
same value; a snapshot without them encodes exactly as before.

**Acceptance Scenarios**:

1. **Given** a stage report, **When** it is exported, **Then** each stage carries its label and its CPU (and, where available, GPU) median and p95 in ms; unavailable values are absent.
2. **Given** an export without frame timings (CaptureLab), **When** it is encoded, **Then** the JSON has no `frameTimings` key and still validates.

### Edge Cases

- The clock goes backwards or a delta is NaN or infinite: the sample is rejected and counted, never stored.
- A stage begun but not ended (the frame bailed out early): nothing is recorded for that stage in that frame.
- Fewer frames than the window: statistics use the frames there are; no frames: every stage is unavailable.
- The window wraps: only the most recent 120 frames count.
- The shown visual changes: the window restarts so stages of different visuals never mix.
- GPU times missing (simulator, ANGLE's own command buffers, a command buffer that failed): unavailable.
- Recording stops: `encode` leaves the report once no frame in the window has it.

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-001-R1**: The timer MUST record CPU time per stage for the six stages `audio`, `render`, `composite`, `output`, `encode`, `present`, with these exact labels, from an injected monotonic clock.
- **PERF-001-R2**: The timer MUST keep a fixed-size window of the most recent frames (120) and report, per stage, the sample count, median (mean of the two middle values for an even count) and 95th percentile (nearest rank, index ⌈0.95·n⌉ − 1) in milliseconds. Attaching the timer to another visual, or turning the overlay off, clears the window.
- **PERF-001-R3**: A stage the pipeline has but that recorded no sample in the window, and any GPU value not measured, MUST be reported as unavailable; the report never contains 0 or NaN in place of a missing value.
- **PERF-001-R4**: Samples that are negative, NaN or infinite MUST be rejected (not stored) and counted.
- **PERF-001-R5**: The `encode` stage MUST appear in a report only when at least one frame in the window measured it (a recording was running).
- **PERF-001-R6**: GPU time MUST come only from the platform's own command-buffer GPU start and end times, read after the work completed, without blocking the frame thread; where unavailable it is marked unavailable.
- **PERF-001-R7**: Recording a frame MUST NOT allocate memory or take a lock; the timer MUST never be called from an audio callback (T063 rule).
- **PERF-001-R8**: The visuals MUST measure stages only while the performance overlay is shown; with it off the frame path does no timing work.
- **PERF-001-R9**: The performance overlay MUST show a stages header, one line per reported stage (label, median and p95 in ms, GPU where available), a `gpu` line for the whole frame (or "gpu unavailable"), and "rejected N" when samples were rejected, while it is on.
- **PERF-001-R10**: The diagnostics export format MUST gain an optional `frameTimings` section carrying the report (labels, sample counts, CPU and GPU median/p95 in ms, unavailable values absent); exports without it are unchanged and stay schema-valid.
- **PERF-001-R11**: Every visual of the app MUST report its stages: projectM (audio, render, output, present), the native spectrum and oscilloscope (audio, render, encode, present), and the compositor visuals: camera, photo, video and text (audio, composite, output, encode, present).
- **PERF-001-R12**: The automation runner MUST have a device mode that runs a visual with the timer on and writes the frame timings report (diagnostics format) to Documents.

### Key Entities

- **Frame stage**: one of the six labelled stages; `encode` is conditional.
- **Stage report**: per stage, label, sample count, CPU statistic and GPU statistic; plus the frame's whole GPU time; plus the number of frames in the window and of rejected samples.
- **Statistic**: unavailable, or measured (samples, median ms, p95 ms).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PERF-001-S1**: A synthetic frame reports finite timings with the correct stage labels (roadmap acceptance): labels, values and unavailable markers exactly as injected.
- **PERF-001-S2**: Median and p95 are exact for known sample sets, including after the window wraps.
- **PERF-001-S3**: A real compositor frame on the Mac's GPU yields finite, non-negative composite and output times and a finite frame GPU time.
- **PERF-001-S4**: The overlay shows the stage labels in the simulator within a UI test of under 30 s.
- **PERF-001-S5**: Timing one frame of six stages costs under 1 µs of CPU on the Mac (measured, reported; not asserted), and nothing with the overlay off.
- **PERF-001-S6**: The pure timer builds and passes its tests on Linux.

## Assumptions

- Per-stage GPU times are unavailable in the app: each visual encodes all of a frame's GPU work into one command buffer, so only the whole frame's GPU time is measurable without extra command buffers or counter sampling. Splitting the GPU work is PERF-002's concern.
- ANGLE submits projectM's Metal work itself, so projectM's GPU time is unavailable.
- CPU stage times on the frame thread include encoding only; GPU execution is in the GPU figure.
- No per-stage signposts: Instruments' Metal System Trace already shows GPU work, and the overlay is the user-facing view (decision recorded in research).
- Device numbers are a `{device}` task; simulator numbers are never evidence.
