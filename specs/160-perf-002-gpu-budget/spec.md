# Feature Specification: PERF-002 GPU budget meter

**Feature Branch**: `feature/perf-002` (spec directory `160-perf-002-gpu-budget`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PERF-002 (GPU budget meter) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Display bounded render-time estimate against frame deadline." Acceptance,
verbatim: "Exceeding threshold flags specific pass without blocking render." P1, size M, depends on
PERF-001. Verification: performance unit, simulator, physical device last."

Identifiers carry the roadmap ID: requirements `PERF-002-R1…`, success criteria `PERF-002-S1…`, tasks
`PERF-002-T01…`. Other features are cited by their own IDs: PERF-001 (per-stage frame timings,
`specs/152-perf-001-stage-timings`), FR-048 (performance overlay), FR-049 (quality governor frame-rate cap),
T063 (no allocation or lock in audio callbacks), FR-021 (diagnostics export), ACC-* (accessibility announcer).

## Baseline: what exists today (audit of 2026-11-14, commit `2c4317ae`)

| Area | Today |
|---|---|
| Stage timings (PERF-001) | `FrameStageTimer` (target `FrameTiming`, Compositor package): six stages (audio, render, composite, output, encode, present), a 120-frame ring, median/p95 per stage, CPU per stage, GPU per stage only when reported (never in the app today), the whole frame's GPU time from the Metal visuals' single command buffer; projectM on ANGLE reports "gpu unavailable". Runs only while the overlay is shown. |
| Overlay (FR-048, PERF-001-R9) | Fps, mean/max frame time, audio state and the stage lines (`FrameStageReport.lines`), refreshed once a second; one combined accessibility element. No deadline, no budget, no flag. |
| Frame rate (FR-049) | Every visual's display link uses `QualityGovernor` (cap 60 fps, 30 under Low Power or serious/critical thermal state), bounded by the screen's maximum refresh rate. |
| Diagnostics (PERF-001-R10) | Optional `frameTimings` section (labels, counts, CPU/GPU median and p95). No budget verdict. |

The gap: nothing compares the measured times with the time a frame is allowed to take, and nothing points
at the pass that uses up the budget.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: What is the frame deadline? → A: One frame period of the target frame rate: the lower of the display's maximum refresh rate and the visual's frame-rate cap (FR-049), e.g. 60 fps → 16.67 ms, 120 → 8.33 ms, 30 → 33.33 ms. An invalid or missing rate falls back to 60 fps.
- Q: Which figure is compared? → A: Each pass's 95th percentile over PERF-001's window (120 frames), never a single frame, so one hiccup does not flag.
- Q: What is a "pass"? → A: A PERF-001 stage measured on the CPU (frame thread), a stage measured on the GPU where the platform reported it, and the whole frame's GPU time (labelled "gpu frame"). Each domain is labelled (cpu or gpu) and judged separately; a figure that is unavailable is shown as unavailable and never flagged.
- Q: What is the threshold? → A: A share of the deadline, 80% by default (13.33 ms at 60 fps), configurable in code; not a user setting (no new stored key).
- Q: Does a flag change anything? → A: No. The meter only reads the report the overlay already asks for once a second; it never skips a frame, lowers quality or touches the render path.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How many samples must a pass have before it can be flagged? → A: At least 30 in the window (half a second at 60 fps). Fewer samples (a window just restarted) show the figure but never flag, so a fresh window cannot flag on one or two frames.
- Q: Should a flag be spoken by VoiceOver when it appears? → A: No spoken announcement. The overlay is a diagnostic that refreshes every second; announcing would interrupt the performer. The budget and flag lines are part of the overlay's combined accessibility label, so VoiceOver reads them when the overlay is focused.
- Q: Should per-pass GPU timing be added now (counter sampling at encoder boundaries, or one command buffer per pass)? → A: No. Counter sampling needs per-encoder sample attachments inside the compositor and every visual and is unsupported on some devices; splitting command buffers costs submission time on every frame. GPU passes are judged from what PERF-001 reports (today the whole frame's GPU time); a stage's GPU figure is flagged as soon as it is measured.
- Q: When is the verdict recomputed and when is its flag state forgotten? → A: Once per overlay refresh (1 s), from the same report as the stage lines. The flags are forgotten when the shown visual changes (the window restarts) or the overlay is turned off.
- Q: What exactly does the overlay say? → A: A budget line `budget 16.67 ms @60 fps, limit 13.33 ms (80%)`, an estimate line `estimate cpu 4.10 ms, gpu 3.20 ms` (or `gpu unavailable`), and per flagged pass `over budget: composite cpu 14.20 ms > 13.33 ms`. Flag lines use a highlight colour and keep the text, so the meaning does not depend on colour.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See which pass blows the frame budget (Priority: P1)

A performer or tester with the performance overlay on sees the frame deadline, a bounded render-time
estimate against it, and, when a pass's time goes over the budget, a highlighted line naming that pass
(for example "over budget: composite cpu 14.20 ms > 13.33 ms"), so they know what to simplify.

**Why this priority**: The roadmap row.

**Independent Test**: Inject stage times where only composite exceeds the threshold; the verdict flags
exactly "composite" and the overlay text names it.

**Acceptance Scenarios**:

1. **Given** a window where composite's p95 is above 80% of the deadline and every other pass is below, **When** the verdict is computed, **Then** exactly one pass, "composite", is flagged.
2. **Given** a flagged pass, **When** frames keep rendering, **Then** exactly as many frames are rendered, with exactly the same rendering calls, as without the meter.
3. **Given** a pass whose time is unavailable (no GPU figure on ANGLE or the simulator), **When** the verdict is computed, **Then** it is shown as unavailable and never flagged.
4. **Given** a flagged pass whose p95 drops below the threshold but stays above the clear level, **When** the verdict is recomputed, **Then** it stays flagged; **When** it drops below the clear level, **Then** the flag clears.
5. **Given** the overlay is on, **When** a VoiceOver user focuses it, **Then** the budget line and any flag are read with it.

### User Story 2 - Take the verdict away (Priority: P2)

A tester running the automation device session gets the budget verdict (deadline, threshold, estimate,
flagged passes) in the JSON report next to the frame timings.

**Acceptance Scenarios**:

1. **Given** a verdict, **When** it is exported, **Then** the frame timings section carries an optional budget object; **Given** none, **Then** the export is unchanged and stays schema-valid.

### Edge Cases

- No frames measured yet: every pass is unavailable; nothing is flagged; the estimate is unavailable.
- Fewer than 30 samples for a pass: its figure is shown, it is never flagged, and an existing flag on it is kept until enough samples decide.
- The deadline changes (Low Power Mode drops the cap to 30 fps): the next verdict uses the new deadline.
- The shown visual changes: PERF-001 clears the window; flags from the old visual are dropped.
- The overlay is turned off: the meter forgets its flags.
- A p95 exactly at the threshold: not flagged (strictly greater flags).
- Threshold settings out of range (≤ 0, > 1, or a clear level above the threshold): clamped to valid values.

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-002-R1**: The meter MUST derive the frame deadline from the target frame rate, the lower of the display's maximum refresh rate and the visual's frame-rate cap; 60, 120 and 30 fps give 16.67, 8.33 and 33.33 ms; an invalid rate falls back to 60 fps.
- **PERF-002-R2**: The budget threshold MUST be a configurable share of the deadline (default 0.80) and the clear level a lower share (default 0.70); invalid values are clamped (threshold to (0, 1], clear level to (0, threshold]).
- **PERF-002-R3**: For every pass with a measured figure the meter MUST compare its p95 with the threshold: a pass is flagged when its p95 is strictly greater than the threshold and stays flagged until its p95 falls below the clear level (hysteresis).
- **PERF-002-R4**: Passes MUST be each reported stage's CPU figure, each stage's GPU figure where the platform measured it, and the whole frame's GPU figure, each labelled with its domain. An unavailable figure MUST be shown as unavailable and never flagged; no figure is estimated or invented.
- **PERF-002-R5**: The meter MUST show a bounded render-time estimate: the sum of the stages' CPU p95 (an upper-bound style estimate of the frame thread's work, labelled cpu) and, separately, the whole frame's GPU p95 (labelled gpu), each against the deadline; unavailable when nothing was measured.
- **PERF-002-R6**: The meter MUST be purely observational: it reads only the report, and never skips, delays or alters a frame, its quality or its rendering calls.
- **PERF-002-R7**: The meter MUST be bounded: its state is a fixed set of at most 13 pass flags (6 stages × 2 domains + the frame GPU), it runs off the frame path (once a second with the overlay), and the frame path gains no work.
- **PERF-002-R8**: The overlay MUST show a budget line (deadline, frame rate, threshold), an estimate line and one highlighted line per flagged pass with its figure and the threshold, while it is on; the text is part of the overlay's accessibility label, so VoiceOver reads it. No spoken announcement is made.
- **PERF-002-R9**: The diagnostics frame timings MUST gain an optional budget verdict (deadline, threshold and clear shares, estimates, flagged pass names); exports without it are unchanged and stay schema-valid.
- **PERF-002-R10**: In DEBUG builds a launch argument MUST be able to inject a slow stage into the reported figures (never into rendering) so the flag can be tested in the simulator.
- **PERF-002-R11**: A pass MUST have at least 30 samples in the window before it can be flagged; the verdict is recomputed once per overlay refresh, and the flag state is forgotten on a visual change or when the overlay is turned off.

### Key Entities

- **Frame deadline**: target frame rate and frame period (ms).
- **Budget policy**: threshold share and clear share of the deadline.
- **Pass**: a stage and a domain (cpu or gpu), or the whole frame's GPU time.
- **Budget verdict**: deadline, threshold, per-pass status (unavailable, within, over), estimates, flagged passes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PERF-002-S1**: With injected times where only composite exceeds the threshold, the verdict flags exactly "composite" (roadmap acceptance).
- **PERF-002-S2**: With the meter flagging, the number of rendered frames and of rendering calls equals the number without it (a spy counts them).
- **PERF-002-S3**: Deadlines at 60, 120 and 30 fps are exact to 0.01 ms.
- **PERF-002-S4**: An unavailable pass is never flagged; a flag clears only below the clear level.
- **PERF-002-S5**: In the simulator, with a DEBUG-injected slow stage, the overlay shows the flag within a UI test of under 30 s.
- **PERF-002-S6**: The pure meter builds and passes its tests on Linux.

## Assumptions

- Per-pass GPU times stay unavailable in the app: each visual encodes a frame into one command buffer, and per-encoder GPU timing needs counter sampling (`MTLCounterSampleBuffer` at stage boundaries) or split command buffers; both are out of scope (see research). The meter flags GPU passes as soon as PERF-001 reports per-stage GPU figures.
- CPU stage times are the frame thread's encode time, not GPU execution; the overlay labels them cpu.
- Simulator numbers are never evidence; device numbers are a `{device}` task.
