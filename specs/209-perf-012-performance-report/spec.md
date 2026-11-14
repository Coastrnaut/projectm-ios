# Feature Specification: PERF-012 Diagnostic performance report

**Feature Branch**: `feature/perf-012` (spec directory `209-perf-012-performance-report`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (PERF-012-T01-T16 verified: FrameTiming and Diagnostics package tests on the
host, app unit and UI tests on the feature's iOS 27.2 simulator "PERF12 iPhone 17"). Open: T17 `{device}` (D1 export).
Simulator results are not performance evidence.

**Input**: User description: "Implement PERF-012 (Diagnostic performance report) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Export local JSON with frame percentiles and resource counters." Acceptance, verbatim:
"Export omits personal media and includes versioned schema." P1, size M, extension of the existing
DiagnosticsExporter; depends on PERF-001."

Identifiers carry the roadmap ID: requirements `PERF-012-R1…`, success criteria `PERF-012-S1…`, tasks
`PERF-012-T01…`. Other features are cited by their own IDs: FR-021/FR-061/FR-068 (diagnostics export privacy),
FR-048 (performance overlay), FR-049 (quality governor), PERF-001 (stage timings), PERF-002 (frame budget), PERF-004
(texture pool), PERF-007 (frame drop telemetry), PERF-008 (power profile), REC-012 (share via Files).

## Baseline: what exists today (audit of 2026-11-14, commit `9baece96`)

| Area | Today |
|---|---|
| `DiagnosticsExporter` (Diagnostics package, T031) | Writes CaptureLab's `DiagnosticsSnapshot` (schemaVersion 2, `contracts/diagnostics-export.schema.json` of feature 001) as JSON + text for the share sheet. Metadata only: no audio, no identifiers (FR-021). Optional additive sections `frameTimings` (PERF-001/002/003) and `frameDrops` (PERF-007) are filled only by the automation runner. |
| PERF-001 / PERF-002 | While the performance overlay is shown, a `FrameStageTimer` gives per-stage CPU/GPU medians and p95 over a rolling window, and a budget verdict. No p50/p90/p99/max of whole frames; no session-long figures. |
| PERF-007 | While the overlay is shown, `FrameDropCounter` counts submitted, skipped, presented, late and discarded frames per output (device, external, recording); a counting session restarts on each visual change. |
| PERF-008 / FR-049 | `QualityGovernor.current()` gives the frame-rate cap and render scale from thermal state, Low Power Mode and the power profile. Nothing records how they changed over time. |
| PERF-004 | `SharedTexturePool` holds per-device texture pools with counters (live, retired, hits, misses, evictions, purges). Shown nowhere. |
| REC-012 | `ShareFileStore` temporary copies + `ActivitySharePresenter` (system share sheet, copy deleted on every outcome). |
| In the app | No user-facing performance export exists; the CaptureLab export lives in the separate CaptureLab harness. |

The gap: a user who sees stutter cannot hand over a self-contained, privacy-safe performance file.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Export a performance report (Priority: P1)

A user notices stutter. They turn on the performance overlay, play for a while, open Settings → Performance and tap
"Export performance report". The share sheet offers one JSON file, which they save to Files or send to whoever helps
them. The file says how smooth frames were (percentiles), how many were dropped, what thermal, Low Power and power
profile states the device went through, the render scale, and the texture and memory counters — and nothing about
their photos, videos, texts, presets, scenes, recordings or network peers.

**Why this priority**: it is the roadmap behaviour and its acceptance.

**Independent Test**: build a report from a session seeded with personal media and check the JSON.

**Acceptance Scenarios**:

1. **Given** a session with frame data, **When** the user exports, **Then** the JSON has the documented
   `schemaVersion`, app/OS/device model, session duration, frame-time p50/p90/p95/p99/max, drop counts, the state
   timeline, render scale and resource counters, and validates against the documented schema.
2. **Given** a session that showed a user photo, a text overlay, a user preset, a named scene, a recording and an
   OSC peer, **When** the report is built, **Then** none of their names, texts, file names, paths or addresses
   appear anywhere in the file.
3. **Given** the share sheet closes (any outcome), **Then** the temporary copy is deleted (REC-012 behaviour).

### User Story 2 - Report without frame data (Priority: P2)

A user exports without having shown the overlay. The report is still valid: frame figures are reported as
unavailable (absent, never 0), and the footer explains that frame figures need the performance overlay.

**Acceptance Scenarios**:

1. **Given** no frame was measured, **When** exported, **Then** the frames section has `sampleCount` 0 and no
   percentile keys; the file still validates.

### Edge Cases

- Very long sessions: the state timeline keeps at most a fixed number of entries and says when it was cut.
- A frame interval longer than the histogram range: counted in the top bucket; `maxMs` stays exact.
- Export while a recording runs: allowed; nothing about the recording but its frame counts is included.
- Writing the file fails: a notice, no sheet (REC-012-R11 behaviour).

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-012-R1**: Settings → Performance offers "Export performance report", a user action; nothing is exported,
  written or sent otherwise.
- **PERF-012-R2**: The report is one JSON file named `projectM-performance-<UTC yyyyMMdd-HHmmss>.json`, shared
  through the system share sheet as a temporary copy deleted on every outcome; the app sends nothing anywhere.
- **PERF-012-R3**: The report carries `schemaVersion` (an integer, 1 for this feature) and a fixed `kind`; its shape
  is documented in a JSON Schema contract with `additionalProperties: false` throughout.
- **PERF-012-R4**: The report carries app version and build, OS version and build, the hardware model identifier
  and the session duration since launch; no device name, user name, serial, vendor or advertising identifier.
- **PERF-012-R5**: The report carries frame-interval percentiles p50, p90, p95, p99 and the exact maximum in
  milliseconds over every frame measured this session, the sample count, measured seconds, the histogram
  resolution, and counts of frames at least as long as fixed thresholds (25, 50, 100 ms). Unavailable values are absent, never 0.
- **PERF-012-R6**: The report carries the PERF-007 drop counts per output and, when available, the PERF-001/002
  stage timings in the existing diagnostics formats.
- **PERF-012-R7**: The report carries the thermal state, Low Power Mode, power profile, frame-rate cap and render
  scale now and as a timeline of changes (seconds since launch), at most a fixed number of entries.
- **PERF-012-R8**: The report carries texture pool counters (PERF-004) and memory counters (current and peak
  footprint, available memory where the OS reports it).
- **PERF-012-R9**: Every string in the report is either system metadata (model, OS, app version) or one of a fixed,
  documented set of values; the report never contains user media, file names, paths, preset, scene, text overlay
  or recording names, OSC peer addresses, audio, or any user-entered text.
- **PERF-012-R10**: Each export is marked with a Points of Interest signpost event carrying counts only.
- **PERF-012-R11**: Frame measurement keeps the existing cost model: it runs only while the performance overlay is
  shown (PERF-001/007), allocates nothing per frame, and stores nothing on disk or in preferences.

### Key Entities

- **Performance report**: versioned document (environment, session, frames, drops, timings, states, resources).
- **Frame interval histogram**: fixed buckets of frame-to-frame intervals plus the exact max, sum and count.
- **State sample**: time, thermal state, Low Power Mode, profile, frame-rate cap, render scale.

## Success Criteria *(mandatory)*

- **PERF-012-S1**: In 100% of tested reports seeded with personal media, none of the seeded strings or paths
  appears in the exported file.
- **PERF-012-S2**: 100% of exported reports declare the documented schema version and validate against the
  documented schema.
- **PERF-012-S3**: Percentiles of known interval sets are within one histogram resolution step of the exact
  nearest-rank value, and the maximum is exact.
- **PERF-012-S4**: A user can export a report from Settings in at most two taps after opening Settings → Performance.
- **PERF-012-S5**: On D1, an exported report after a 1-minute session shows plausible percentiles and counters
  `{device}`.

## Assumptions

- Frame figures exist only for time the performance overlay was shown (the existing telemetry gating).
- Simulator results are not performance evidence; S5 is checked on D1 last.
- No new stored preference: the report lives in memory for the app session only.

## Clarifications

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: May the report name the preset that was showing (bundled presets are not personal)? → A: No preset identity at
  all, bundled or not. Only the visual kind (one of `projectM`, `native`, `camera`, `photo`, `video`, `text`,
  `none`) is recorded. A bundled preset path still reveals listening habits, and a user preset name is user text;
  one rule for all is simpler to prove (PERF-012-R9).
- Q: Which time span do frame figures cover? → A: Every frame measured since launch while the performance overlay
  was shown, accumulated across visual changes and overlay sessions (not reset by PERF-007's per-visual counting
  sessions). The state timeline covers the whole app session from launch. The report is never persisted: a relaunch
  starts empty (PERF-012-R11).
- Q: What is a "frame time" for the percentiles? → A: The interval between consecutive frames handed to the display
  (display-link timestamps of submitted frames), the figure the user perceives as smoothness, on every visual path
  (projectM included). Fixed 0.1 ms buckets up to 250 ms; a percentile is the upper edge of its nearest-rank bucket
  capped by the exact max (never optimistic). Long-frame thresholds: 25 ms, 50 ms and 100 ms. Per-stage CPU/GPU
  figures stay PERF-001's window medians/p95 (Metal GPU times), included as they are.
- Q: Is MetricKit used ("MetricKit where appropriate")? → A: No. MetricKit delivers aggregated payloads about once
  a day, not for the session being reported, so it adds nothing to a user-initiated report; the report uses the
  app's own counters and an `os_signpost` event per export.
- Q: Should the file be a new schema or a new version of the CaptureLab diagnostics schema? → A: A new document
  with its own `schemaVersion` (1) and `kind` `projectM-iOS.performanceReport`, written by an extension of
  `DiagnosticsExporter` and reusing its `frameTimings` and `frameDrops` section types unchanged. The CaptureLab
  schema (version 2) is untouched.
