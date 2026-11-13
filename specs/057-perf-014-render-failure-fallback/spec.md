# Feature Specification: PERF-014 Render Failure Fallback

**Feature Branch**: `feature/perf-014` (spec directory `057-perf-014-render-failure-fallback`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement PERF-014 (Render failure fallback) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Recover from invalid shader or
missing texture with a safe placeholder." Acceptance, verbatim: "Fault injection preserves app
responsiveness and records reason." P0, effort M, depends on CMP-001 (integrated). Verification:
performance unit + simulator + physical device last stage."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `PERF-014-R1…`, success criteria `PERF-014-S1…`, tasks `PERF-014-T01…`.
Requirements of other features are cited by their own IDs: CMP-001-R9 (nothing is created per frame
at a steady size), FX-019-R11 (a new scene forgets the flash history), VIS-001-R16 (a visual that
cannot be created falls back to projectM with a notice), FR-045 (a preset that fails to load keeps
the previous one), FR-048 (performance overlay).

## Baseline: what exists today (audit of 2026-11-13, commit `4254e58`)

The row's gap status is "Gap candidate". The audit finds most single-frame fallbacks in place; what
is missing is bounded recovery, GPU error handling, a placeholder for a visual that shows nothing,
a recorded reason and a way to inject faults.

| Fault | Today | Gap for this row |
|---|---|---|
| A compositor layer's pipeline or sampler cannot be created (Photo, Video, Camera, Text, materials, graphs: created in the layer's prepare) | CMP-001: the layer becomes unavailable and shows its fallback (transparent or last good frame); the others keep rendering. It is prepared again only on the next size change or an explicit `retryUnavailableLayers()`, which the app never calls. | No automatic, bounded retry; no reason recorded or shown. |
| A layer picture (texture) cannot be created | CMP-001: the layer is unavailable (`resourceUnavailable("layer picture …")`). The composite itself missing → no frame is presented. | Same as above; "missing texture" is not a distinct reason. |
| A layer's render throws a serious error (engine failure, resource unavailable) | The fallback is shown for that frame, and the layer is asked to render again on every following frame. | A persistent failure retries every frame (a tight loop); nothing is counted. |
| Non-finite colours from a layer | Cleaned to 0 in the over pass (CMP-001). | None. |
| GPU command buffer error (timeout, page fault, not permitted in background, out of memory) | Not observed on the compositor visuals; the native spectrum checks status only for a frame capture. | Not counted, no back-off, no recovery. |
| projectM preset fails to load (unreadable file, parse error, invalid shader that does not compile) | FR-045: the previous preset keeps running, a banner shows, the preset is excluded for the session (`PresetTests.testFailedLoadKeepsThePreviousPresetReportsAndExcludesIt`); PRE-012 quarantines imported presets. | Reason not recorded in a render health record or diagnostics; cannot be injected in a UI test. |
| projectM cannot present a frame (window surface swap fails, context lost) | The swap result is ignored; the engine is asked to render on every tick. | Not detected, no back-off, no placeholder. |
| A native spectrum, Camera, Photo, Video or Text visual cannot be created | VIS-001-R16: falls back to projectM with a notice (`NativeVisualUITests`, `-uitestNativeVisualFailure`); glow failure has its own notice (FX-001). | Reason not recorded in a render health record. |
| A visual that shows nothing at all | — | No safe placeholder exists. |
| Diagnostics | Logging of lifecycle and memory events (PERF-011, PERF-006). | No render-fault event. |

MED-014 (safe media decoder) runs in parallel and hardens decoding of imported photos and videos; a
media file that cannot be decoded is MED-014's and MED-001/002's concern (the layer's own failed
state), not a render fault, and this feature does not duplicate it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A broken part of the picture never freezes the app (Priority: P1)

A performer has a visual running when one of its parts cannot be drawn: a layer's shader pipeline
cannot be created, a picture cannot be allocated, or a preset's shader does not compile. The rest of
the visual keeps running (or the previous preset keeps playing), controls respond immediately, the
audio source keeps playing, and the app tries again a few times, spaced further apart each time.
If the fault clears, the part comes back by itself.

**Why this priority**: It is the row's acceptance ("fault injection preserves app responsiveness").
A fault that blocks the main thread or retries every frame makes the app unusable during a show.

**Independent Test**: Inject each fault kind into a running visual: the frame counter keeps
advancing, the other layers keep drawing, retries happen only at the back-off frames and stop after
the limit, and clearing the fault brings the part back at the next retry.

**Acceptance Scenarios**:

1. **Given** the Photo visual is running, **When** the photo layer's pipeline cannot be created,
   **Then** the spectrum keeps drawing over black, the frame loop keeps ticking, and the photo layer is
   tried again after 30 frames, then 60, 120 and 240 frames, and not again after that.
2. **Given** a layer is waiting for its next retry, **When** the fault clears before that retry,
   **Then** the retry succeeds and the layer is shown again from that frame.
3. **Given** a layer's render throws a serious error on every frame, **When** frames continue,
   **Then** the layer is not asked to render again until its next retry (no per-frame retry).
4. **Given** projectM is playing preset A, **When** the next preset's shader does not compile,
   **Then** preset A keeps playing (FR-045), and the reason is recorded.
5. **Given** any visual and fault, **When** the user opens and closes Settings, **Then** both happen
   at once and the audio source is not restarted.

---

### User Story 2 - A visual that cannot draw at all shows a calm placeholder (Priority: P1)

When nothing of the chosen visual can be shown any more (the GPU keeps rejecting its work, or
projectM cannot present frames, and the retries are used up), the app fades to a calm black
placeholder with a small "Visual unavailable" note instead of a frozen or flickering picture. The
placeholder never flashes. Choosing a visual again, or returning to the app, tries once more.

**Why this priority**: It is the row's "safe placeholder". A frozen frame looks like a hang; a
flickering retry loop is a photosensitivity hazard (FX-019).

**Independent Test**: Inject a persistent GPU error: after the bounded retries the placeholder
fades in, its luminance change is a single transition, frames keep ticking; clearing the fault and
resuming the visual removes the placeholder.

**Acceptance Scenarios**:

1. **Given** a compositor visual, **When** its GPU work fails, **Then** the visual draws plain black
   (no layers) for the back-off and then tries again; while it waits, further errors are not counted
   again.
2. **Given** the retries are used up, **When** the next frame comes, **Then** the placeholder fades in
   over 0.5 s and stays until the user changes visual or the visual is resumed (pause/resume,
   returning to the app).
3. **Given** the placeholder is shown, **When** the user resumes or changes the visual and the fault
   has cleared, **Then** the visual comes back and the placeholder fades out.
4. **Given** the app goes to the background and the GPU refuses work there, **When** the app returns,
   **Then** the visual's retry budget starts again from zero.

---

### User Story 3 - The reason is recorded where a developer can see it (Priority: P2)

A developer investigating a report sees, in the performance overlay and in the system log, which
fault happened, how often and at which frame, without any user content.

**Why this priority**: The acceptance requires the reason to be recorded; without it device faults
cannot be diagnosed.

**Independent Test**: After an injected fault the shown visual's health names the reason, the count
and the frame; the log event carries only those; the overlay shows a health line while the visual is
not healthy.

**Acceptance Scenarios**:

1. **Given** a fault was recorded, **When** the performance overlay is on, **Then** it shows the
   visual's health (state, last reason, count).
2. **Given** a fault was recorded, **When** the system log is read, **Then** one event names the
   visual, the reason, the count and the frame, and no preset name, file name, text or audio.
3. **Given** a debug build launched with the fault-injection flag, **When** faults are injected,
   **Then** a hidden readout shows the shown visual's health for UI tests.

### Edge Cases

- A fault happens before the visual's first frame (prepare at the first size): the layer starts on its
  fallback and the back-off counts from that frame.
- The output size changes (rotation) while a layer waits: every layer is prepared again at the new
  size (CMP-001), and the retry budget starts again.
- A layer whose fallback is "last good frame" fails after showing frames: the last good picture
  stays during the back-off (no luminance change at all).
- Several layers fail at once: each has its own back-off; the visual's health shows the latest reason
  and the total count.
- GPU errors from frames already submitted before the back-off began arrive during the back-off: they
  are coalesced into the fault already recorded.
- A successful GPU frame that was encoded before a retry began does not count as a recovery.
- The fault clears while the placeholder is shown: nothing changes until a reset (no automatic
  flicker back).
- A preset fails to load when no preset played yet: projectM keeps its idle picture (FR-045); the
  reason is recorded.
- The app is paused by the user (FR-046) while waiting: back-off counts only frames that ran.

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-014-R1**: Render faults MUST be classified into a closed set of reasons: layer prepare
  failed (pipeline or resource), missing texture (picture), layer render failed, GPU timeout, GPU page
  fault, GPU not permitted, GPU out of memory, other GPU error, preset load failed (invalid shader or
  preset), engine presentation failed, visual unavailable (could not be created). Routine conditions
  (content not ready, a skipped frame, an empty output size) MUST NOT count as faults.
- **PERF-014-R2**: Every visual MUST keep one render health record: state (healthy, recovering,
  degraded, placeholder), fault count, last reason, the frame of the last fault (the visual's frame
  clock, never wall time) and the number of recoveries.
- **PERF-014-R3**: A compositor layer whose prepare fails or whose picture cannot be created MUST show
  its declared fallback while the other layers keep rendering, and MUST be prepared again only at its
  back-off frames.
- **PERF-014-R4**: A compositor layer whose render throws a serious error (not "not ready" or "frame
  skipped") MUST show its fallback and MUST NOT be asked to render again before its next back-off
  frame.
- **PERF-014-R5**: Back-off MUST be measured in frames: the first retry 30 frames after the fault,
  each following delay doubled, at most 4 retries (30, 60, 120, 240 frames); after the last failed
  retry the part stays on its fallback (or the visual on the placeholder) until a reset. Faults that
  occur while a part waits for its retry MUST be coalesced (counted once).
- **PERF-014-R6**: A reset (the user changes or resumes the visual, the visual's frame loop restarts
  after a pause, background or presentation loss, or the output size changes) MUST clear the retry
  budgets and retry failed parts at once; the counters (faults, recoveries, last reason) are kept.
- **PERF-014-R7**: Compositor visuals MUST detect GPU command buffer errors without waiting for the
  GPU and without per-frame allocation, map them to a reason (R1), draw no layers (calm black) during
  the back-off, retry with the R5 policy, and count a recovery only for a frame encoded after the
  retry began.
- **PERF-014-R8**: A projectM preset that fails to load (including a shader that does not compile)
  MUST keep the previous preset (FR-045, unchanged) and MUST record the reason "preset load failed"
  in projectM's health record without changing its state.
- **PERF-014-R9**: projectM MUST detect a frame it could not present, stop rendering for the back-off
  (R5, counted in display ticks), retry by recreating its drawing surface, and enter the placeholder
  state after the last failed retry.
- **PERF-014-R10**: When the shown visual's state is placeholder, the app MUST cover it with a black
  placeholder carrying a small "Visual unavailable" note, faded in and out over 0.5 s, so each switch
  is one monotonic luminance change within the strobe safety envelope (FX-019). The placeholder MUST
  NOT alternate with the visual on its own; only a reset can remove it.
- **PERF-014-R11**: A visual that cannot be created MUST keep VIS-001-R16's fallback to projectM with a
  notice, and the reason "visual unavailable" MUST be recorded and logged.
- **PERF-014-R12**: Fault handling MUST NOT block the main thread or the frame loop: no waits for the
  GPU, no retries outside back-off frames, no allocation per frame at a steady size (CMP-001-R9) while
  healthy or while faulted; the frame counter keeps advancing while a fault is active.
- **PERF-014-R13**: Each counted fault and each recovery MUST log one diagnostics event naming the
  visual kind, the reason, the counts and the frame; it MUST NOT carry preset names, file names, user
  text or audio. Layer names are fixed identifiers (e.g. "photo", "spectrum") and may be logged.
- **PERF-014-R14**: The performance overlay (FR-048) MUST show the shown visual's health line while
  the state is not healthy or a fault was recorded; debug builds MUST expose the health as a hidden
  accessibility value for UI tests.
- **PERF-014-R15**: Debug builds MUST offer fault injection behind a launch flag and a probe: a layer's
  prepare failing (by layer name), a layer's picture missing, a layer's render failing, GPU errors of
  a given reason on a compositor visual, the next projectM preset load failing as an invalid shader,
  and projectM presentation failing. Injection works by making creation or the result check fail; no
  faulty shader is added. Clearing an injection lets the next retry succeed. Release builds contain
  none of it.
- **PERF-014-R16**: A layer's switch to its fallback and back MUST pass through the composite flash
  guard (FX-019), as every composited frame does; the back-off spacing (≥ 30 frames) MUST keep retry
  switches below the envelope's transition budget.

### Key Entities

- **Render fault reason**: one of R1's reasons; a stable identifier with no user content.
- **Retry state**: per failing part (a layer, the GPU work of a visual, projectM's presentation):
  retries used, the next retry frame, or given up.
- **Render health record**: per visual: state, fault count, last reason, last fault frame, recoveries.
- **Fault injection**: the debug-only set of armed faults for a visual.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PERF-014-S1**: For each injectable fault kind, the expected reason is recorded within the frame
  of the fault (unit tests), and the count rises by exactly one per fault episode or failed retry.
- **PERF-014-S2**: While any fault is active, the visual's frame counter advances on every frame
  (unit tests) and the shown visual's frames keep advancing on the simulator.
- **PERF-014-S3**: Retries happen exactly at 30, 90, 210 and 450 frames after the first fault, and no
  retry happens in the following 1,000 frames (unit tests).
- **PERF-014-S4**: When the fault clears, the next retry succeeds, the state returns to healthy and the
  recovery count rises by one.
- **PERF-014-S5**: Each placeholder switch and each fallback switch produces at most one luminance
  transition per second in the flash analysis (unit tests on the fade and on the composite).
- **PERF-014-S6**: With injected layer and preset faults on the simulator, Settings opens and closes,
  the reason appears in the debug readout, and the audio source start count stays 1; the UI test runs
  in under 30 s.
- **PERF-014-S7** `{device}`: On D1 (iOS 27) and D3 (iPadOS 26.5), the injected faults behave as on the
  simulator (debug build), with no hang and the reason logged.

## Assumptions

- The frame clock of each visual (the compositor's frame index, projectM's display ticks) is the time
  base for back-off; at 60 fps the four retries span about 7.5 s.
- Real GPU errors cannot be produced on demand on the simulator; they are injected at the status
  check, the only place the app reads them.
- MED-014 owns media decoding failures; this feature does not change them.
- The native spectrum's runtime GPU errors are not handled by this feature (its creation failure is
  covered by VIS-001-R16); recorded as a decision in Clarifications.
- Simulator results are not device evidence (Constitution X); the device task stays open.
