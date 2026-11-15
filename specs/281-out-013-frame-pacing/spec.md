# Feature Specification: OUT-013 Frame Pacing per Output

**Feature Branch**: `feature/out-013` (spec directory `281-out-013-frame-pacing`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (OUT-013-T01-T11, T13 verified on the Mac host and the iOS 27.2 simulator; T12
`{device}` open). Earlier: (speckit-analyze 2026-11-14: 2 MEDIUM findings fixed: R7 and its edge case scoped to the Metal
visuals; requirement coverage 10/10)

**Input**: Roadmap row OUT-013 (frozen), verbatim: "Coordinate internal and external redraw without unbounded queues."
Acceptance, verbatim: "Slow external output does not stall primary display render loop." P2, L, depends on OUT-001
(integrated).

Identifiers carry the roadmap ID: requirements `OUT-013-R1…`, success criteria `OUT-013-S1…`, tasks `OUT-013-T01…`.
Other features are cited by their own IDs: OUT-001 (external display scene), OUT-002 (hot-plug), OUT-003 (output
resolution), OUT-005 (operator guides), OUT-006 (output mode), OUT-011 (output diagnostics), PERF-001 (stage timings),
PERF-007 (frame drop counts), PERF-011 (presentation suspension), PERF-014 (render health), REC-003/REC-006 (recording
and its bounded frame gate), FR-049 (QualityGovernor frame-rate cap).

## Baseline: what exists today (audit of 2026-11-14, commit `71b5865e`)

| Area | Today | Gap for this row |
|---|---|---|
| Visual placement (OUT-001, OUT-006) | One visual view. With an external display it moves into the external slot; the device slot is empty. OUT-006 (Same scene / Clean output) only routes overlay layers; it never adds a second render. | None: one render, one output at a time. |
| Device side while external | The device shows the SwiftUI controls, HUD, operator guides (OUT-005), the PERF overlays and Settings. All of it runs on the main thread. | — |
| projectM (ANGLE) loop | `ANGLERenderer` renders **on the main thread** from a `CADisplayLink(target:selector:)` (the main screen's link) at QualityGovernor's range (≤ 60 fps). ANGLE fetches the drawable inside the frame (`[CAMetalLayer nextDrawable]`); when that returns nil, ANGLE retries **with the timeout disabled, waiting indefinitely** (`SurfaceMtl.mm` `obtainNextDrawable`). `eglSwapBuffers` commits and presents. | The frame loop follows the device's screen, not the screen showing the frame; nothing bounds frames in flight; a slow output can block the main thread inside ANGLE. |
| Native and compositor hosts | `NativeSpectrumHost`, `CameraVisualHost`, `PhotoVisualHost`, `VideoVisualHost`, `TextVisualHost`: each a main-screen `CADisplayLink` on the main run loop, `layer.nextDrawable()` (up to 1 s blocking by default), one command buffer per frame, `present`, `commit`. | Same: main-screen pacing, no in-flight bound, a blocking drawable wait on the main thread. |
| Analysis feed | `LiveBandAnalyzer` runs on its own queue; frames read the newest vector without waiting (latest-value, no queue). projectM reads the normalized PCM ring (bounded, overwrite-oldest) once per frame. | Already bounded; must stay unaffected by output speed. |
| Recording (REC-003, REC-006) | The recorder has its own bounded frame gate that drops slots. | Already bounded; unchanged. |
| Telemetry (PERF-001, PERF-007) | Stage timings and frame drop counts per output (`device`, `external`, `recording`). | No count of frames an output refused because it was behind. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human interaction);
each answer is the conservative, local-first option.

- Q: What is the "primary display render loop" when the visual is on the external display? → A: Everything the
  device's own screen shows and updates on the main thread: controls, HUD, operator guides, overlays, gestures and
  their frame callbacks, plus the analysis feed that drives them. With OUT-001's single render there is no device copy
  of the visual, so the requirement is that the visual's output never blocks the main thread or the analysis queue.
- Q: Which clock paces the visual? → A: The display link of the screen that shows the visual's view (the external
  screen while it is placed there, the device's screen otherwise). The link is rebuilt when the view moves to another
  screen; its frame-rate range (FR-049) is kept.
- Q: What happens when the output is behind? → A: The tick is dropped: no audio read beyond what the frame already
  does, no drawable request, no render. Frames are never queued for later. Each drop is counted with its cause.
- Q: Is any user interface added? → A: No. The counts are kept in memory for tests, the DEBUG probe and later
  diagnostics; no new setting, no new UserDefaults key, no new screen.

### Session 2026-11-14 (speckit-clarify)

- Q: Does the pacing apply only to the external output? → A: No: every output uses the same per-screen link and gate
  (the device output too). One mechanism, so moving the visual never changes its rules.
- Q: When does a frame stop being "in flight"? → A: When the GPU has completed it: the command buffer's completion for
  the Metal visuals, a GL fence that has signalled for projectM on ANGLE. The display's own hold on a drawable is covered
  by pacing from that display's link (OUT-013-R1) and the drawable-wait back-off (OUT-013-R7).
- Q: What does a dropped projectM tick do with the audio? → A: It reads nothing; the normalized PCM ring is bounded and
  overwrites its oldest samples, and the next rendered frame reads at most one frame's maximum (no catch-up backlog).
- Q: Where are the counts shown? → A: Nowhere new: in memory on each visual, readable by tests and diagnostics code
  through each visual's `outputPacing` counts. PERF-007's counters already show the skipped refresh slots a drop causes. No user interface change,
  so no UI test.
- Q: Are counts reset when the visual moves to another screen? → A: No. The gate is the visual's; frames in flight
  complete wherever they were submitted, and the counts are cumulative for the visual's life (tests read deltas).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The device stays responsive while the external output struggles (Priority: P1)

A performer drives a projector or TV that refreshes slowly (30 or 50 Hz, a slow adapter) or a preset that is too heavy
for the external resolution. The device's controls, HUD and guides keep moving smoothly at the device's own rate; the
external picture drops frames instead of making the device stutter.

**Why this priority**: it is the row's acceptance criterion; a frozen control surface during a show is the failure the
row exists to prevent.

**Independent Test**: a pacing model with an injected clock: an external output that needs 100 ms per frame while the
device ticks at 120 Hz for 10 simulated seconds; and an app test with a slowed external output and a device-side probe.

**Acceptance Scenarios**:

1. **Given** the visual is on an external output that completes a frame only every 100 ms, **When** the device ticks at
   120 Hz for 10 s, **Then** no device tick is delayed by more than the tolerance, the output never has more frames in
   flight than the bound, the queue depth stays constant, and the dropped external frames are counted.
2. **Given** the same slow output in the app, **When** the device-side probe ticks on the main thread, **Then** it keeps
   ticking at rate and the output's in-flight count and dropped count stay bounded.

### User Story 2 - Each output keeps its own rate (Priority: P2)

When the visual is placed on an external display, its frames follow that display's refresh; when it returns to the
device, they follow the device's again.

**Independent Test**: the visual's frame link is rebuilt for the screen of the window its view joins, keeping its
frame-rate range and pause state.

**Acceptance Scenarios**:

1. **Given** the visual is on the device, **When** it moves to the external slot (OUT-001), **Then** its frame link is the
   external screen's link with the same frame-rate range.
2. **Given** the visual is paused (FR-046), **When** it moves, **Then** the new link is paused too.

### Edge Cases

- The output stops consuming entirely (cable pulled): OUT-002 removes the slot; in-flight frames complete or are
  abandoned and the gate empties; a later output starts with a clean count of frames in flight.
- The drawable request returns nothing (Metal visuals): the tick is dropped (counted as a drawable drop); nothing is
  retried in a loop.
- A drawable wait that took longer than half the output's refresh interval: the next tick is skipped (one-tick
  back-off) so the output can catch up.
- PERF-011 suspension: no ticks; frames already in flight complete normally.
- PERF-014's presentation back-off still applies on top: a held tick is not counted as a pacing drop.
- REC-001 still capture and REC-003 recording ride on a rendered frame; a dropped tick carries no capture and no
  recording copy (the pending capture waits for the next rendered frame; REC-006 counts the recording's own slots).

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-013-R1**: Each visual's frame loop MUST be driven by the display link of the screen that shows its view, and
  MUST move to the new screen's link when the view moves, keeping the frame-rate range and the paused state.
- **OUT-013-R2**: Each output MUST have at most a fixed number of frames in flight (submitted, not yet completed by the
  GPU): 2.
- **OUT-013-R3**: A tick that would exceed the bound MUST be dropped without blocking: no waiting for a frame slot, a
  drawable or the GPU on the main thread or the analysis queue.
- **OUT-013-R4**: Nothing between analysis, render and output may grow with time: no frame queue, no backlog of
  dispatched work per tick; the maximum depth of every pacing structure is a constant independent of run length.
- **OUT-013-R5**: Every drop MUST be counted per cause (frames in flight, no drawable, back-off), with the frames begun
  and completed and the largest number in flight seen; counts are local, in memory only, and cumulative for the visual's
  life (a screen move does not reset them).
- **OUT-013-R6**: The visual layers MUST state their drawable policy explicitly: three drawables and a bounded drawable
  wait.
- **OUT-013-R7**: Where the app requests the drawable itself (the Metal visuals), a drawable wait longer than half of
  the output's refresh interval MUST skip the output's next tick, and a request that returns nothing MUST be a counted
  drop. projectM's drawable is fetched inside ANGLE and is covered by R1 and R8 (research OUT-013-D3).
- **OUT-013-R8**: projectM's frames on ANGLE MUST be bounded the same way without waiting: completion is polled once per
  tick with a zero timeout.
- **OUT-013-R9**: The pacing rules MUST be a pure model testable with an injected clock (no wall clock), and build where
  the package builds today (Linux included).
- **OUT-013-R10**: No public-API exception, no new UserDefaults key, no new network use, no user interface change.

### Key Entities

- **Output pacing policy**: frames in flight bound (2) and the slow-wait fraction (0.5 of a refresh interval).
- **Output frame gate**: per output; frames in flight, pending back-off, counts.
- **Output pacing counts**: begun, completed, dropped (in flight, no drawable, back-off), largest in flight.

## Success Criteria *(mandatory)*

- **OUT-013-S1**: With an output that needs 100 ms per frame, a 120 Hz device loop over 10 simulated seconds has no tick
  delayed by more than 1 ms beyond its schedule (a blocking design is late by up to 100 ms in the same model).
- **OUT-013-S2**: Frames in flight never exceed 2 in that run, and the largest pacing depth after 1 s equals the largest
  after 10 s.
- **OUT-013-S3**: Every dropped external frame in that run is counted (begun + dropped = ticks).
- **OUT-013-S4**: In the app with a slowed external output, the device-side probe keeps ticking (no gap longer than
  0.25 s) while the output's frames in flight stay ≤ 2 and its drops are counted.
- **OUT-013-S5** `{device}`: on a real external display with a deliberately heavy preset, the device's controls stay
  smooth and the external drop count rises instead.

## Assumptions

- OUT-001's single render remains: there is never a second copy of the visual on the device (OUT-006 routes overlays
  only).
- The CPU cost of a frame is the same wherever it is shown; this row bounds the waiting caused by the output (GPU and
  drawables), not the engine's own CPU time on the main thread (ANGLE stays on the main thread, as today).
- Simulator results are never performance evidence; the device check stays a `{device}` task.
