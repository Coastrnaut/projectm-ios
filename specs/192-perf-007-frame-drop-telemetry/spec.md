# Feature Specification: PERF-007 Frame drop telemetry

**Feature Branch**: `feature/perf-007` (spec directory `192-perf-007-frame-drop-telemetry`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PERF-007 (Frame drop telemetry) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Count late, skipped and presented frames by output." Acceptance, verbatim:
"Counters reset per session and never double-count a frame." P1, size S, depends on PERF-001."

Identifiers carry the roadmap ID: requirements `PERF-007-R1…`, success criteria `PERF-007-S1…`, tasks
`PERF-007-T01…`. Other features are cited by their own IDs: PERF-001 (stage timings, `FrameStageTimer`), PERF-002
(budget meter), PERF-003 (adaptive quality), OUT-001/OUT-002 (external display placement and hot-plug), REC-003
(video recording statistics), REC-006 (recording dropped slots), FR-048 (performance overlay), FR-020 (diagnostics
export), SC-103 (feature 002 scrolling frame meter).

**"Telemetry" here means local counting only.** Nothing is sent anywhere. The constitution forbids telemetry and
network calls in the audio and capture path and the app has no networking; the counts live in memory on the
device, are shown in the performance overlay and may be written into the diagnostics export file the user shares
by hand. No MetricKit upload, no analytics, no network symbol.

## Baseline: what exists today (audit of 2026-11-14, commit `0cad6578`)

| Area | Today |
|---|---|
| Stage timings (PERF-001) | `FrameStageTimer` (FrameTiming target of Packages/Compositor): per-stage CPU/GPU windows, attached to the shown visual only while the overlay is shown (`FrameStageAttachment`, `AppCoordinator+FrameStages.swift`). |
| Budget (PERF-002), quality (PERF-003) | `FrameBudgetMeter` judges the stage report once a second; the native visual's effect ladder reads its verdict. |
| Overlay (FR-048) | `PerformanceOverlay`: fps, frame time, audio state, render health, stage and budget lines; refreshed once a second. |
| Frame loops | Every visual runs its own `CADisplayLink` on the main run loop. The native spectrum, Camera, Photo, Video and Text hosts present a `CAMetalDrawable` (`commands.present(drawable)`); projectM (`ANGLERenderer`) presents through `eglSwapBuffers`, so the app never sees its drawable. |
| External display (OUT-001/002) | The same visual view moves to the external window (`ExternalDisplayCoordinator.place()`); no second frame loop. `showsVisualExternally` says where the visual is. |
| Recording (REC-003, REC-006) | `MetalFrameRecorder.statistics`: `written`, drops by cause, and `droppedSlots` (grid slots between the first and last appended frame with no frame). `VideoRecordingCoordinator.lastRecording` keeps the last recording's statistics. |
| Scrolling meter (SC-103) | `FrameMeter` (Debug/automation only): a display link that counts callbacks and missed refresh slots while a list scrolls. Not about the visualizer. |
| Diagnostics (FR-020) | `DiagnosticsSnapshot.frameTimings` (optional): stage timings, budget, effect quality. |

The gap: nothing counts how many frames each output actually showed, showed late, or skipped, and nothing proves a
frame is counted once.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Is any of this sent off the device? → A: No. Local, in-memory counting only, shown in the overlay and in the optional `frameDrops` section of the diagnostics export (a file the user shares by hand). No network, no MetricKit payload upload, no analytics.
- Q: Which outputs are counted? → A: Three: the device display, the external display and the recording. The visual is shown on exactly one display at a time (OUT-001), so its frames count into the device or the external counter depending on where it is placed; the recording's counts come from the recorder's own statistics (REC-003/REC-006).
- Q: What does each counter mean? → A: `presented`: frames the display reported as shown (a presented time later than zero). `late`: presented frames whose presented time is more than half a refresh interval after the frame's target time (a subset of `presented`). `skipped`: refresh slots with no new frame, from the display-link timestamps of consecutive submitted frames (slots between them minus one). `discarded`: submitted frames the display reported as never shown (presented time zero). `submitted`: frames the visual handed to the display. For the recording: `presented` = frames written to the file, `skipped` = REC-006's dropped slots; `late` and `discarded` do not apply.
- Q: What if a path cannot measure something? → A: It is shown and exported as unavailable, never as 0 and never estimated. projectM presents through ANGLE (`eglSwapBuffers`) and exposes no drawable, so its `presented`, `late` and `discarded` are unavailable; its `submitted` and `skipped` come from its display link. The recording has no `late` or `discarded`.
- Q: When do counters reset (the "session")? → A: The device and external counters each start a new session whenever the visual they count changes, the visual moves between outputs (an external display connects, settles or disconnects), the overlay is turned on, or the visualizer is entered. The recording counter's session is one recording. Counting runs while the performance overlay is shown (the PERF-001 attachment rule): with it off, no frame does any counting work.
- Q: How is double counting prevented? → A: Every submitted frame gets a frame ID, unique within its session and increasing. A presented report is counted only if its ID is newer than the newest one already counted for that session (presented reports arrive in presentation order), so a repeated callback for the same frame is ignored. A display-link timestamp is counted only if it is later than the previous one. Every event carries its session token; an event whose token is not the current session's is ignored (counted as stale), including one that arrives after a reset.
- Q: May the counting lock or allocate on the frame path? → A: No. The counter is lock-free (atomic compare-and-exchange on 64-bit cells that pack the session generation with the count) and preallocated. The only per-frame allocation is Metal's own presented-handler block, attached only while counting is on.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See how many frames each output showed, showed late or skipped (Priority: P1)

A performer opens the performance overlay while the visualizer runs. Below the stage and budget lines the overlay
shows, for the output the visual is on (and the recording while one runs), how many frames were presented, how many
were late and how many refresh slots were skipped since the session began. Values a path cannot measure read
"unavailable".

**Why this priority**: it is the roadmap behaviour: drops must be visible per output to diagnose stutter on an
external display or in a recording.

**Independent Test**: inject a sequence of frame events (IDs, target times, presented times, display-link
timestamps) into a counter and check the exact counts; show the overlay in the app on a simulator and read the
"frames device" line.

**Acceptance Scenarios**:

1. **Given** a session with frames 1-5 submitted at consecutive refresh slots except one missed slot, and presented reports for frames 1-4 (frame 3 presented 0.6 refresh intervals after its target, frame 5 reported with presented time 0), **When** the counts are read, **Then** submitted 5, skipped 1, presented 4, late 1, discarded 1.
2. **Given** the visual is projectM, **When** the overlay shows the device line, **Then** submitted and skipped have values and presented, late and discarded read "unavailable".
3. **Given** a recording is running, **When** the overlay is read, **Then** a recording line shows frames written and REC-006 dropped slots, and late reads "unavailable".

### User Story 2 - Counters reset per session and never double-count a frame (Priority: P1)

**Why this priority**: the roadmap acceptance.

**Independent Test**: unit tests on the counter with duplicated reports and late reports from a previous session.

**Acceptance Scenarios**:

1. **Given** presented reports for frame 7 arrive twice and a display-link timestamp is repeated, **When** the counts are read, **Then** frame 7 counts once as presented and the repeated timestamp adds no frame and no skipped slot.
2. **Given** a session with counts, **When** a new session begins, **Then** every counter reads 0.
3. **Given** a presented report from the previous session arrives after the new session began, **When** the counts are read, **Then** it is not counted (the stale count goes up by one).
4. **Given** the visual moves from the device to an external display, **When** frames are then submitted, **Then** they count into the external counter's new session and the device counter stops changing.

### User Story 3 - The counts are in the diagnostics export (Priority: P2)

**Why this priority**: automation and device runs need the numbers in a file.

**Independent Test**: encode and decode a snapshot with a `frameDrops` section; unavailable values are absent keys.

**Acceptance Scenarios**:

1. **Given** a snapshot with per-output counts, **When** it is encoded and decoded, **Then** it is equal, and an unavailable counter is an absent key, never 0.
2. **Given** a snapshot without counts, **When** it is encoded, **Then** the `frameDrops` key is absent (schema version unchanged).

### Edge Cases

- A display-link timestamp earlier than or equal to the previous one (duplicate or clock reset): ignored, no frame, no slot.
- A frame period of zero or not finite: the frame counts as submitted, no skipped slots are inferred.
- A presented report for a frame ID never submitted in the session (too new): ignored as stale.
- Presented time earlier than target time (early): presented, not late.
- Out-of-order presented reports (an older ID after a newer one): the older one is not counted (the display reports in presentation order, so this only happens for a duplicate or a stale report).
- Session generation wrap (65,536 sessions): a stale event would need to be exactly 65,536 sessions old; accepted.
- Overlay off: no counting work; the overlay shows nothing and the export carries no section.
- External display disconnects mid-frame: the frame's late presented report carries the external session token and is ignored by the device counter.

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-007-R1**: The app MUST count, per output (device display, external display, recording), the frames presented, late, skipped and (for the displays) submitted and discarded, as defined in Clarifications.
- **PERF-007-R2**: A presented frame MUST count as late when its presented time exceeds its target time by more than half a refresh interval; late frames are also presented frames.
- **PERF-007-R3**: Skipped slots MUST come from the display-link timestamps of consecutive submitted frames: round(gap / refresh interval) − 1, never negative.
- **PERF-007-R4**: Each frame MUST be counted at most once: by frame ID for presented, late and discarded; by strictly increasing display-link timestamp for submitted and skipped.
- **PERF-007-R5**: Every event MUST carry the session token it was produced under; an event of another session MUST NOT change the counts (it increments only the stale count).
- **PERF-007-R6**: Counters MUST reset to zero when a session begins: per visualizer session and visual (device), per external display placement (external), per recording (recording); see Clarifications.
- **PERF-007-R7**: A value a path cannot measure MUST be reported as unavailable (overlay text "unavailable", absent export key), never 0 and never estimated. projectM's presented, late and discarded are unavailable; the recording's late and discarded are unavailable.
- **PERF-007-R8**: Recording on the frame path MUST NOT lock, wait or allocate (beyond Metal's presented-handler block); the presented report may arrive on any thread.
- **PERF-007-R9**: The counting logic MUST be pure Swift that builds and tests on Linux.
- **PERF-007-R10**: The performance overlay MUST show one "frames <output>" line for the output the visual is on, plus a recording line while a recording runs or exists in the session, only while the overlay is shown.
- **PERF-007-R11**: The diagnostics export MUST accept an optional `frameDrops` section (per output: name, counts, unavailable as absent keys) without a schema version change.
- **PERF-007-R12**: Nothing about these counts MUST leave the device except inside the diagnostics file the user exports by hand; no network API, no telemetry upload.

### Key Entities

- **Frame drop output**: device, external, recording.
- **Frame drop session**: a token (generation) identifying one counting session of one output.
- **Frame drop counts**: submitted, skipped, presented, late, discarded and stale per output; each may be unavailable.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PERF-007-S1**: For an injected event sequence, every count equals the expected value exactly, with every duplicate report counted once (acceptance test).
- **PERF-007-S2**: After a session reset every count is 0, and 100% of late events from the previous session are excluded.
- **PERF-007-S3**: Frames of one output never change another output's counts.
- **PERF-007-S4**: Unavailable values read "unavailable" in the overlay and are absent from the export in 100% of cases.
- **PERF-007-S5**: The diagnostics export with a `frameDrops` section round-trips unchanged.

## Assumptions

- Presented reports for one display arrive in presentation order (Metal calls presented handlers in presentation order), so "newer than the newest counted ID" is a complete duplicate filter.
- The refresh interval of a frame is the display link's `targetTimestamp − timestamp` at submission.
- Simulator results are not performance evidence; device counts on D1 with an external display are a `{device}` task.
