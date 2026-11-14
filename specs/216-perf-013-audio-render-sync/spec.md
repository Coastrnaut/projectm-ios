# Feature Specification: PERF-013 Audio-render synchronization

**Feature Branch**: `feature/perf-013` (spec directory `216-perf-013-audio-render-sync`)

**Created**: 2026-11-14

**Status**: Clarified 2026-11-14

**Input**: User description: "Implement PERF-013 (Audio-render synchronization) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Track age of analyzed audio features at frame presentation." Acceptance, verbatim:
"Injected timestamp drift is detected and corrected within budget." P1, size L, gap candidate; depends on ANL-016."

Identifiers carry the roadmap ID: requirements `PERF-013-R1…`, success criteria `PERF-013-S1…`, tasks
`PERF-013-T01…`. Other features are cited by their own IDs: ANL-016 (analysis event bus and its clock), AUD-013
(source latency offset), PERF-001/002 (stage timings, overlay), PERF-007 (frame drop telemetry), PERF-012
(performance report), FR-048 (performance overlay).

## Baseline: what exists today (audit of 2026-11-14, commit `cd89f309`)

| Area | Today |
|---|---|
| ANL-016 bus clock | Every `AnalysisFrame` carries an `AnalysisTimestamp`: session, session sample (end of the analysed window), timeline sample and a host time = the session's anchor (the monotonic clock at the session's first chunk minus that chunk's duration) + session sample at the nominal 44.1 kHz rate. The anchor is taken once per session: if the audio's sample clock runs faster or slower than the host clock, every later host time is off by the accumulated difference. Nothing measures this. |
| Native visuals (`LiveBandOutput.readLatest`) | The native, camera, photo, video and text visuals read the newest frame each display-link tick (nil when none arrived since the last read). The frame's host time and ID reach the visual; its session sample does not. |
| AUD-013 | `LatencyOffsetSetting` delays the audio reaching the analysis by 0…250 ms (slewed). The bus's host times then describe when the audio entered analysis, after the intended delay. |
| PERF-001/007/012 | While the performance overlay is shown, stage timings, frame-drop counts and a session-long frame-interval histogram are measured; PERF-012 exports them (schema version 1). Nothing relates a presented frame to the audio it shows. |
| Signposts | `DiagnosticsLog` emits Points of Interest events (presentation, power profile, performance report, render fault). |

The gap: nobody can tell how old the audio features on screen are, and a slowly drifting audio clock silently skews
every analysis host time for the rest of a session.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See how old the audio on screen is (Priority: P1)

A user who tunes visuals to music turns on the performance overlay. Next to the frame timings a line reads, for
example, "audio age 24.1 ms p95 31.0 ms": the time between the moment the analysed audio entered analysis and the
moment the frame showing it is presented. When an AUD-013 offset is set, the line also shows it, so the user sees the
intended part separately.

**Why this priority**: it is the roadmap's observable behaviour.

**Independent Test**: feed a meter with frames and presentation times on injected clocks; the reported age and
percentiles equal the known values.

**Acceptance Scenarios**:

1. **Given** frames whose audio entered analysis 20 ms before each presentation, **When** the overlay refreshes,
   **Then** the age line shows about 20 ms (median and p95 within the 0.1 ms resolution).
2. **Given** a visual that consumes no analysis frames (projectM), **When** the overlay is shown, **Then** the age is
   shown as unavailable, never 0.
3. **Given** the PERF-012 report is exported after age was measured, **Then** it carries the age percentiles and the
   drift state; without measurements the section is absent.

### User Story 2 - Detect and correct clock drift (Priority: P1)

During a long session the audio's sample clock runs 500 ppm fast relative to the device's host clock. The app notices
that the analysed audio arrives progressively "earlier" than its timestamps claim, estimates the drift, and corrects
its mapping from samples to host time a little at a time, so the measured age stays true. Without drift nothing is
corrected.

**Why this priority**: it is the roadmap's acceptance.

**Independent Test**: inject a sample clock with known drift and jittered arrivals; the estimator detects it and
brings the age error within budget in the documented time without overshooting; with no drift it never corrects.

**Acceptance Scenarios**:

1. **Given** +500 ppm (and −500 ppm) drift with arrival jitter, **When** 60 s of frames are simulated, **Then** the
   drift is detected, the age error is within 1 ms from 10 s on, and the applied correction never moves past the
   true drift offset by more than 1 ms.
2. **Given** no drift with the same jitter, **Then** no drift is detected and the correction stays exactly 0.
3. **Given** a step in arrival latency (e.g. the AUD-013 offset changed by 100 ms), **Then** it is not mistaken for
   drift: no correction is applied.
4. **Given** each correction step, **Then** the mapping moves by at most 0.25 ms per presented frame.

### Edge Cases

- A new analysis session (source restart, visual change): the estimate and correction start over.
- Ages longer than the measurement range (250 ms) count in the top bucket; the maximum stays exact.
- A presentation time earlier than the frame's audio time (clock anomaly): counted separately, not as an age.
- The display link pauses (background): no samples; nothing extrapolates across the gap.
- Too few observations (under 8 s of audio): no drift verdict, no correction.

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-013-R1**: For every presented frame of a visual that consumes analysis frames, the age of the newest
  consumed feature frame is computed as presentation time − the corrected time its audio entered analysis.
- **PERF-013-R2**: The age is summarised as a smoothed value, p50, p95 and the exact maximum over the counting
  session, with a fixed 0.1 ms resolution; unavailable values are absent, never 0.
- **PERF-013-R3**: Drift between the analysis sample clock and the host clock is estimated from the arrival times of
  feature frames against their sample positions, robust to one-sided arrival jitter.
- **PERF-013-R4**: Drift is reported as detected when its magnitude is at least 50 ppm over at least 8 s of audio,
  and cleared below 25 ppm; below detection no correction is applied.
- **PERF-013-R5**: While drift is detected, the sample-to-host mapping is corrected toward the estimate; each step
  moves it by at most 0.25 ms per presented frame and never past the target.
- **PERF-013-R6**: A sudden change of arrival latency (more than 4 ms between consecutive observation buckets beyond
  the drift prediction) restarts the estimate without changing the applied correction.
- **PERF-013-R7**: A new analysis session resets the estimate, the correction and the per-session figures.
- **PERF-013-R8**: The performance overlay shows one age line (smoothed age, p95, the AUD-013 offset when set, and
  the drift verdict with the estimate when detected); unavailable when no visual consumes analysis frames.
- **PERF-013-R9**: The PERF-012 report gains an optional `audioSync` section (age sample count, p50, p95, max,
  drift verdict and estimate, correction count); absent without measurements.
- **PERF-013-R10**: Each drift detection and each clear is marked with a Points of Interest signpost event carrying
  numbers only, emitted outside the frame path.
- **PERF-013-R11**: Measurement follows the existing telemetry cost model: only while the performance overlay is
  shown, nothing allocated per frame, nothing stored on disk or in preferences, nothing sent anywhere, nothing passed
  to projectM.

### Key Entities

- **Clock observation**: a feature frame's sample position, its bus host time and the host time it was first read.
- **Drift estimate**: slope of arrival residuals over sample time (ppm), detected flag, the target and applied
  correction (ns).
- **Age summary**: count, smoothed age, percentiles, maximum, anomalies.

## Success Criteria *(mandatory)*

- **PERF-013-S1**: With ±500 ppm injected drift, the age error is within 1 ms within 10 s of audio after the session
  start, and stays within 1 ms to the end of a 60 s run.
- **PERF-013-S2**: With no drift, 0 corrections in 100% of runs (jittered arrivals included).
- **PERF-013-S3**: No correction step exceeds 0.25 ms, and the applied correction never passes the true drift
  offset by more than 1 ms.
- **PERF-013-S4**: The overlay age equals a known injected age within 0.1 ms.
- **PERF-013-S5**: On D1, the overlay age line shows a plausible age (under 100 ms) on a native visual with
  microphone audio, and a 5-minute session reports no false drift detection `{device}`.

## Assumptions

- "Audio entered analysis" is the bus's host time (ANL-016-D2 anchor); delivery latency before the analysis tap and
  the intended AUD-013 offset are outside the measured age (the offset is shown beside it).
- Drift is constant within a session (crystal tolerance); steps come from route or offset changes.
- Simulator results are not performance evidence; S5 is checked on D1 last.

## Clarifications

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: From which moment is a feature frame's age measured? → A: From the bus's host time for the frame's audio
  (ANL-016-D2: when the audio entered analysis, mapped through the session anchor), corrected for drift. Delivery
  latency before the analysis tap is not observable without new capture hooks and is excluded; the AUD-013 offset is
  intended delay and is shown beside the age, not added to it (PERF-013-R1, R8).
- Q: What does the drift correction change? → A: Only the meter's sample-to-host mapping used to measure age (and
  reported). The visuals keep consuming the newest frame as today; nothing re-times what is drawn and nothing reaches
  projectM (Constitution VIII). A future consumer may read the corrected mapping (PERF-013-R5, R11).
- Q: How is drift estimated robustly against jittery arrivals? → A: Arrival residual = first-read host time − bus host
  time. Residuals are grouped in 1 s buckets of audio time and each bucket keeps its minimum (arrival jitter is
  one-sided: frames are never early). A least-squares line through up to 64 bucket minima gives the drift (ppm). At
  least 8 buckets are needed for a verdict; detection at ≥ 50 ppm, cleared below 25 ppm (hysteresis). A bucket more
  than 4 ms off the previous one's drift prediction is a latency step: the buckets restart, the applied correction
  stays (PERF-013-R3, R4, R6).
- Q: What is the correction budget? → A: Correction target = estimated drift × audio time since the session start;
  the applied correction moves toward it by at most 0.25 ms per presented frame and never past it. Budget: with
  ±500 ppm drift, age error ≤ 1 ms from 10 s of audio on, until at least 60 s; no drift → no correction
  (PERF-013-R5, S1-S3).
- Q: Does the PERF-012 report need a new schema version for the `audioSync` section? → A: No. PERF-012 was
  integrated on 2026-11-14 and has not shipped in any release, so no version 1 report exists outside development.
  The optional section is added to schema version 1 (contract amended, the copy kept equal, `additionalProperties:
  false` kept). Recorded in the PERF-012 contract's description (PERF-013-R9).
- Q: Where are the signposts emitted? → A: On the overlay refresh (main thread, once a second) when the drift verdict
  changes, as `DiagnosticsLog` Points of Interest events with numbers only; never from the frame path or an audio
  callback (PERF-013-R10).
